export ISOLATION_ID ?= local
PWD = $(shell pwd)

ORGANIZATION ?= $(shell git remote show -n origin | grep Fetch | \
												awk '{print $$NF}' | \
												sed -e 's/git@github.com://' | \
												sed -e 's@https://github.com/@@' | \
												awk -F'[/.]' '{print $$1}' )
REPO ?= $(shell git remote show -n origin | grep Fetch | \
												awk '{print $$NF}' | \
												sed -e 's/git@github.com://' | \
												sed -e 's@https://github.com/@@' | \
												awk -F'[/.]' '{print $$2}' )

BRANCH_NAME ?= $(shell git symbolic-ref -q HEAD )
SAFE_BRANCH_NAME ?= $(shell if [ -n "$$BRANCH_NAME" ]; then echo $$BRANCH_NAME; else \
														git symbolic-ref -q HEAD|sed -e \
														's@refs/heads/@@'|sed -e 's@/@_@g'; \
														fi)
VERSION ?= $(shell git describe | cut -c2-  )
LONG_VERSION ?= $(shell git describe --long --dirty |cut -c2- )
UID := $(shell id -u)
GID := $(shell id -g)

MAVEN_SETTINGS ?= $(HOME)/.m2/settings.xml
MAVEN_REVISION != if [ "$(LONG_VERSION)" = "$(VERSION)" ] || \
	(echo "$(LONG_VERSION)" | grep -q dirty); then \
		echo `bin/semver bump patch $(VERSION)`-SNAPSHOT; \
	else \
		echo $(VERSION); \
	fi

MAVEN_REPO_BASE ?= https://dev.catenasys.com/repository/catenasys-maven
MAVEN_REPO_TARGET != if [ "$(LONG_VERSION)" = "$(VERSION)" ] || \
	(echo "$(LONG_VERSION)" | grep -q dirty); then \
		echo snapshots; \
	else \
		echo releases; \
	fi
MAVEN_UPDATE_RELEASE_INFO != if [ "$(LONG_VERSION)" = "$(VERSION)" ] || \
	(echo "$(LONG_VERSION)" | grep -q dirty); then \
		echo false; \
	else \
		echo true; \
	fi
MAVEN_DEPLOY_TARGET = $(MAVEN_REPO_TARGET)::default::$(MAVEN_REPO_BASE)-$(MAVEN_REPO_TARGET)

TOOLCHAIN := docker run --rm -v $(HOME)/.m2/repository:/root/.m2/repository \
		-v $(MAVEN_SETTINGS):/root/.m2/settings.xml -v `pwd`:/project \
		toolchain:$(ISOLATION_ID)
DEPLOY_MVN := $(TOOLCHAIN) mvn -Drevision=$(MAVEN_REVISION)
DOCKER_MVN := $(TOOLCHAIN) mvn -Drevision=$(MAVEN_REVISION) -B

SONAR_HOST_URL ?= https://sonarqube.dev.catenasys.com
SONAR_AUTH_TOKEN ?=
PMD_IMAGE ?= blockchaintp/pmd:latest

.PHONY: all
all: clean build package test analyze archive

.PHONY: dirs
dirs:
	mkdir -p build

.PHONY: clean_dirs
clean_dirs:
	rm -rf build test-dars

.PHONY: build
build: build_mvn

.PHONY: build_mvn
build_mvn: build_toolchain
	$(DOCKER_MVN) compile
	$(TOOLCHAIN) chown -R $(UID):$(GID) /root/.m2/repository
	$(TOOLCHAIN) find /project -type d -name target -exec chown \
		-R $(UID):$(GID) {} \;

.PHONY: fix_permissions
fix_permissions: build_toolchain
	$(TOOLCHAIN) chown -R $(UID):$(GID) /root/.m2/repository
	$(TOOLCHAIN) find /project -type d -name target -exec chown \
		-R $(UID):$(GID) {} \;

.PHONY: build_toolchain
build_toolchain: dirs
	docker-compose -f docker/docker-compose-build.yaml build --parallel

.PHONY: package
package: package_mvn

.PHONY: package_mvn
package_mvn: build
	$(DOCKER_MVN) package verify
	$(TOOLCHAIN) chown -R $(UID):$(GID) /root/.m2/repository
	$(TOOLCHAIN) find /project -type d -name target -exec chown \
		-R $(UID):$(GID) {} \;

.PHONY: test
test: test_mvn

.PHONY: test_mvn
test_mvn:
	$(DOCKER_MVN) test

.PHONY: analyze
analyze: analyze_sonar

.PHONY: analyze_sonar
analyze_sonar: package
	[ -z "$(SONAR_AUTH_TOKEN)" ] || \
	$(DOCKER_MVN) package sonar:sonar \
			-Dsonar.projectKey=$(ORGANIZATION)_$(REPO):$(SAFE_BRANCH_NAME) \
			-Dsonar.projectName="$(ORGANIZATION)/$(REPO) $(SAFE_BRANCH_NAME)" \
			-Dsonar.projectVersion=$(VERSION) \
			-Dsonar.host.url=$(SONAR_HOST_URL) \
			-Dsonar.login=$(SONAR_AUTH_TOKEN)

.PHONY: clean
clean: clean_mvn
	docker-compose -f docker/docker-compose-build.yaml rm -f || true
	docker-compose -f docker/docker-compose-build.yaml down -v || true

.PHONY: clean_mvn
clean_mvn: clean_dirs
	$(DOCKER_MVN) clean || true

.PHONY: archive
archive: dirs
	git archive HEAD --format=zip -9 --output=build/$(REPO)-$(VERSION).zip
	git archive HEAD --format=tgz -9 --output=build/$(REPO)-$(VERSION).tgz

.PHONY: publish
publish: build_toolchain
	$(DOCKER_MVN) -Drevision=0.0.0 versions:set -DnewVersion=$(MAVEN_REVISION)
	$(DOCKER_MVN) clean deploy -DupdateReleaseInfo=$(MAVEN_UPDATE_RELEASE_INFO) \
		-DaltDeploymentRepository=$(MAVEN_DEPLOY_TARGET)
