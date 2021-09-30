#
# Makefile helper for developing Home Assistant addons
# NOTE: This will work only if addons were designed to build with homeassistant builder
#

ROOT_DIR := $(shell dirname $(realpath $(firstword $(MAKEFILE_LIST))))
OUTPUT_DIR:=$(ROOT_DIR)/build

# TODO: detect BUILDER_ARCH from the host system
BUILDER_ARCH := amd64
BUILDER_IMAGE := homeassistant/$(BUILDER_ARCH)-builder

IMAGE_SUFFIX?=-dev

# Find "build.json" in nested dirs
ADDONS_BUILD_JSON_FILES := $(shell find . -name "build.json" -depth 2)

# remove leading "./" and trailing "/"
ADDONS_DIRS = $(subst /,,$(subst ./,,$(dir $(ADDONS_BUILD_JSON_FILES))))

get_addon_build_from_images = $(addprefix $(addon_dir)-, $(patsubst "%",%,$(shell jq '.build_from | keys[]' $(addon_dir)/build.json)))
ALL_ADDON_ARCH_VARIANTS := $(sort $(strip $(foreach addon_dir,$(ADDONS_DIRS),$(get_addon_build_from_images))))

$(ALL_ADDON_ARCH_VARIANTS): ADDON_DIR=$(strip $(foreach D,$(ADDONS_DIRS),$(if $(findstring $(D)-,$@),$D)))
$(ALL_ADDON_ARCH_VARIANTS): ADDON_ARCH=$(@:$(ADDON_DIR)-%=%)
$(ALL_ADDON_ARCH_VARIANTS): ADDON_IMAGE=$(ADDON_DIR)-$(ADDON_ARCH)$(IMAGE_SUFFIX)
$(ALL_ADDON_ARCH_VARIANTS):
	@echo "################################################################"
	@echo "#"
	@echo "# Addon arch variant: $@"
	@echo "#"
	@echo "# ADDON_DIR: $(ADDON_DIR)"
	@echo "# ADDON_ARCH: $(ADDON_ARCH)"
	@echo "# ADDON_IMAGE: $(ADDON_IMAGE)"
	@echo "#"
	@echo "# BUILDER_IMAGE: $(BUILDER_IMAGE)"
	@echo "################################################################"
	@echo ""
	@docker run --rm -ti --name hassio-builder --privileged \
	  -v $(ROOT_DIR)/$(ADDON_DIR):/data \
	  -v /var/run/docker.sock:/var/run/docker.sock:ro \
	  $(BUILDER_IMAGE) -t /data --all --test \
	  -i $(ADDON_IMAGE) -d local
	@echo "################################################################"
	@echo " Docker Build completed, saving in to the tarball..."
	@mkdir -p $(OUTPUT_DIR)
	@docker save -o $(OUTPUT_DIR)/$(ADDON_IMAGE).tar local/$(ADDON_IMAGE)
	@echo "################################################################"
	@echo "# Image saved to $(OUTPUT_DIR)/$(ADDON_IMAGE).tar"
	@echo "#"
	@echo "# You can copy it to target with the next command:"
	@echo "#\tscp $(OUTPUT_DIR)/$(ADDON_IMAGE).tar TARGET_IP:~/"
	@echo "#"
	@echo "# And load it on the target:"
	@echo "#\tdocker load -i $(ADDON_IMAGE).tar"
	@echo "################################################################"


#
# Run base image with architecture of the build machine
# Can be useful during writing Dockerfile for executing commands step-by-step
#

ALL_ADDON_ARCH_VARIANTS_RUN_BASE := $(addsuffix -run-base-image,$(ALL_ADDON_ARCH_VARIANTS))

$(ALL_ADDON_ARCH_VARIANTS_RUN_BASE): VARIANT=$(@:%-run-base-image=%)
$(ALL_ADDON_ARCH_VARIANTS_RUN_BASE): ADDON_DIR=$(strip $(foreach D,$(ADDONS_DIRS),$(if $(findstring $(D)-,$(VARIANT)),$D)))
$(ALL_ADDON_ARCH_VARIANTS_RUN_BASE): ADDON_ARCH=$(VARIANT:$(ADDON_DIR)-%=%)
$(ALL_ADDON_ARCH_VARIANTS_RUN_BASE): BASE_IMAGE=$(shell jq '.build_from.$(ADDON_ARCH)' $(ADDON_DIR)/build.json)
$(ALL_ADDON_ARCH_VARIANTS_RUN_BASE): BASE_IMAGE_NAME=$(ADDON_DIR)-$(ADDON_ARCH)-base
$(ALL_ADDON_ARCH_VARIANTS_RUN_BASE): DATA_OPTIONS_JSON=/tmp/${BASE_IMAGE_NAME}-options.json
$(ALL_ADDON_ARCH_VARIANTS_RUN_BASE): EMPTY_SHELL_SCRIPT=/tmp/${BASE_IMAGE_NAME}-empty-script.sh
$(ALL_ADDON_ARCH_VARIANTS_RUN_BASE):
	@echo "################################################################"
	@echo "#"
	@echo "# Addon arch variant: $@"
	@echo "#"
	@echo "# ADDON_DIR: $(ADDON_DIR)"
	@echo "# ADDON_ARCH: $(ADDON_ARCH)"
	@echo "# BASE_IMAGE: $(BASE_IMAGE)"
	@echo "# BASE_IMAGE_NAME: $(BASE_IMAGE_NAME)"
	@echo "################################################################"
	@echo ""

	@echo "#!/bin/sh" > $(EMPTY_SHELL_SCRIPT)
	@echo "exit 0" >> $(EMPTY_SHELL_SCRIPT)
	@chmod 755 $(EMPTY_SHELL_SCRIPT)

	@echo '{"log_level": "TRACE" }' > $(DATA_OPTIONS_JSON)

	@docker run --rm -it --name $(BASE_IMAGE_NAME) --privileged \
	    -v $(DATA_OPTIONS_JSON):/data/options.json \
	    -v $(EMPTY_SHELL_SCRIPT):/etc/cont-init.d/00-banner.sh \
 		$(BASE_IMAGE) \
 		/bin/sh

#
# Help
#
help:
	@echo "Helper for Home Assistant Addons docker local build\n"
	@echo "Usage: make xxx\n"
	@echo "Addon build targets:"
	@for T in $(ALL_ADDON_ARCH_VARIANTS); do \
		echo "\t$$T"; \
	done
	@echo "Addon run targets:"
	@for T in $(ALL_ADDON_ARCH_VARIANTS_RUN_BASE); do \
		echo "\t$$T"; \
	done


.PHONY: $(ALL_ADDON_ARCH_VARIANTS) $(ALL_ADDON_ARCH_VARIANTS_RUN_BASE) help

.DEFAULT_GOAL := help

