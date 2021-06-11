MAKEFILE_DIR := $(dir $(lastword $(MAKEFILE_LIST)))
include $(MAKEFILE_DIR)/standard_defs.mk

build: $(MARKERS)/build_mvn

package: $(MARKERS)/package_mvn

test: $(MARKERS)/test_mvn

analyze: analyze_sonar_mvn

clean: clean_mvn

publish: $(MARKERS)/publish_mvn
