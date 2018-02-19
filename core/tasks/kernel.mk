# Copyright (C) 2012 The CyanogenMod Project
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Android makefile to build kernel as a part of Android Build

TARGET_AUTO_KDIR := $(shell echo $(TARGET_DEVICE_DIR) | sed -e 's/^device/kernel/g')

## Externally influenced variables
# kernel location - optional, defaults to kernel/<vendor>/<device>
TARGET_KERNEL_SOURCE ?= $(TARGET_AUTO_KDIR)
KERNEL_SRC := $(TARGET_KERNEL_SOURCE)
# kernel configuration - mandatory
KERNEL_DEFCONFIG := $(TARGET_KERNEL_CONFIG)
VARIANT_DEFCONFIG := $(TARGET_KERNEL_VARIANT_CONFIG)
SELINUX_DEFCONFIG := $(TARGET_KERNEL_SELINUX_CONFIG)

## Internal variables
KERNEL_OUT := $(TARGET_OUT_INTERMEDIATES)/KERNEL_OBJ
KERNEL_CONFIG := $(KERNEL_OUT)/.config

TARGET_KERNEL_ARCH := $(strip $(TARGET_KERNEL_ARCH))
ifeq ($(TARGET_KERNEL_ARCH),)
KERNEL_ARCH := $(TARGET_ARCH)
else
KERNEL_ARCH := $(TARGET_KERNEL_ARCH)
endif

TARGET_KERNEL_HEADER_ARCH := $(strip $(TARGET_KERNEL_HEADER_ARCH))
ifeq ($(TARGET_KERNEL_HEADER_ARCH),)
KERNEL_HEADER_ARCH := $(KERNEL_ARCH)
else
KERNEL_HEADER_ARCH := $(TARGET_KERNEL_HEADER_ARCH)
endif

KERNEL_HEADER_DEFCONFIG := $(strip $(KERNEL_HEADER_DEFCONFIG))
ifeq ($(KERNEL_HEADER_DEFCONFIG),)
KERNEL_HEADER_DEFCONFIG := $(KERNEL_DEFCONFIG)
endif


ifneq ($(BOARD_KERNEL_IMAGE_NAME),)
  TARGET_PREBUILT_INT_KERNEL_TYPE := $(BOARD_KERNEL_IMAGE_NAME)
else
  ifeq ($(TARGET_USES_UNCOMPRESSED_KERNEL),true)
    TARGET_PREBUILT_INT_KERNEL_TYPE := Image
  else
    ifeq ($(TARGET_KERNEL_ARCH),arm64)
      TARGET_PREBUILT_INT_KERNEL_TYPE := Image.gz
    else
      TARGET_PREBUILT_INT_KERNEL_TYPE := zImage
    endif
  endif
endif

TARGET_PREBUILT_INT_KERNEL := $(KERNEL_OUT)/arch/$(KERNEL_ARCH)/boot/$(TARGET_PREBUILT_INT_KERNEL_TYPE)

# Clear this first to prevent accidental poisoning from env
MAKE_FLAGS :=

ifeq ($(KERNEL_ARCH),arm64)
  # Avoid "unsupported RELA relocation: 311" errors (R_AARCH64_ADR_GOT_PAGE)
  MAKE_FLAGS += -j23 CFLAGS_MODULE="-fno-pic"
  ifeq ($(TARGET_ARCH),arm)
    KERNEL_CONFIG_OVERRIDE := CONFIG_ANDROID_BINDER_IPC_32BIT=y
  endif
endif

ifneq ($(TARGET_KERNEL_ADDITIONAL_CONFIG),)
KERNEL_ADDITIONAL_CONFIG := $(TARGET_KERNEL_ADDITIONAL_CONFIG)
endif

## Do be discontinued in a future version. Notify builder about target
## kernel format requirement
ifeq ($(BOARD_KERNEL_IMAGE_NAME),)
ifeq ($(BOARD_USES_UBOOT),true)
        $(error "Please set BOARD_KERNEL_IMAGE_NAME to uImage")
else ifeq ($(BOARD_USES_UNCOMPRESSED_BOOT),true)
        $(error "Please set BOARD_KERNEL_IMAGE_NAME to Image")
endif
endif

ifeq "$(wildcard $(KERNEL_SRC) )" ""
    ifneq ($(TARGET_PREBUILT_KERNEL),)
        HAS_PREBUILT_KERNEL := true
        NEEDS_KERNEL_COPY := true
    else
        $(foreach cf,$(PRODUCT_COPY_FILES), \
            $(eval _src := $(call word-colon,1,$(cf))) \
            $(eval _dest := $(call word-colon,2,$(cf))) \
            $(ifeq kernel,$(_dest), \
                $(eval HAS_PREBUILT_KERNEL := true)))
    endif

    ifneq ($(HAS_PREBUILT_KERNEL),)
        $(warning ***************************************************************)
        $(warning * Using prebuilt kernel binary instead of source              *)
        $(warning * THIS IS DEPRECATED, AND WILL BE DISCONTINUED                *)
        $(warning * Please configure your device to download the kernel         *)
        $(warning * source repository to $(KERNEL_SRC))
        $(warning * See http://wiki.cyanogenmod.org/w/Doc:_integrated_kernel_building)
        $(warning * for more information                                        *)
        $(warning ***************************************************************)
        FULL_KERNEL_BUILD := false
        KERNEL_BIN := $(TARGET_PREBUILT_KERNEL)
    else
        $(warning ***************************************************************)
        $(warning *                                                             *)
        $(warning * No kernel source found, and no fallback prebuilt defined.   *)
        $(warning * Please make sure your device is properly configured to      *)
        $(warning * download the kernel repository to $(KERNEL_SRC))
        $(warning * and add the TARGET_KERNEL_CONFIG variable to BoardConfig.mk *)
        $(warning *                                                             *)
        $(warning * As an alternative, define the TARGET_PREBUILT_KERNEL        *)
        $(warning * variable with the path to the prebuilt binary kernel image  *)
        $(warning * in your BoardConfig.mk file                                 *)
        $(warning *                                                             *)
        $(warning ***************************************************************)
        $(error "NO KERNEL")
    endif
else
    NEEDS_KERNEL_COPY := true
    ifeq ($(TARGET_KERNEL_CONFIG),)
        $(warning **********************************************************)
        $(warning * Kernel source found, but no configuration was defined  *)
        $(warning * Please add the TARGET_KERNEL_CONFIG variable to your   *)
        $(warning * BoardConfig.mk file                                    *)
        $(warning **********************************************************)
        # $(error "NO KERNEL CONFIG")
    else
        #$(info Kernel source found, building it)
        FULL_KERNEL_BUILD := true
        KERNEL_BIN := $(TARGET_PREBUILT_INT_KERNEL)
    endif
endif

ifeq ($(FULL_KERNEL_BUILD),true)

KERNEL_HEADERS_INSTALL := $(KERNEL_OUT)/usr
KERNEL_MODULES_INSTALL := system
KERNEL_MODULES_OUT := $(TARGET_OUT)/lib/modules

TARGET_KERNEL_CROSS_COMPILE_PREFIX := $(strip $(TARGET_KERNEL_CROSS_COMPILE_PREFIX))
ifeq ($(TARGET_KERNEL_CROSS_COMPILE_PREFIX),)
ifeq ($(KERNEL_TOOLCHAIN_PREFIX),)
KERNEL_TOOLCHAIN_PREFIX := arm-eabi-
endif
else
KERNEL_TOOLCHAIN_PREFIX := $(TARGET_KERNEL_CROSS_COMPILE_PREFIX)
endif

ifeq ($(KERNEL_TOOLCHAIN),)
KERNEL_TOOLCHAIN_PATH := $(KERNEL_TOOLCHAIN_PREFIX)
else
ifneq ($(KERNEL_TOOLCHAIN_PREFIX),)
KERNEL_TOOLCHAIN_PATH := $(KERNEL_TOOLCHAIN)/$(KERNEL_TOOLCHAIN_PREFIX)
endif
endif

ifneq ($(TARGET_KERNEL_CLANG_VERSION),)
    TARGET_KERNEL_CLANG_PATH ?= $(ANDROID_BUILD_TOP)/prebuilts/clang/host/$(HOST_OS)-x86/$(TARGET_KERNEL_CLANG_VERSION)/bin
    ifeq ($(KERNEL_ARCH),arm64)
        KERNEL_CLANG_TRIPLE ?= CLANG_TRIPLE=aarch64-linux-gnu-
    else ifeq ($(KERNEL_ARCH),arm)
        KERNEL_CLANG_TRIPLE ?= CLANG_TRIPLE=arm-linux-gnu-
    else ifeq ($(KERNEL_ARCH),x86)
        KERNEL_CLANG_TRIPLE ?= CLANG_TRIPLE=x86_64-linux-gnu-
    endif
endif

# ccache
ccache :=
ifneq ($(filter-out false,$(USE_CCACHE)),)
  # Use system if availible
  ccache := $(shell which ccache)

  # Set prebuilt if no system bin
  ifeq ($(ccache),)
      ccache := $(ANDROID_BUILD_TOP)/prebuilts/misc/$(HOST_PREBUILT_TAG)/ccache/ccache
      # Check that the executable is here.
      ccache := $(strip $(wildcard $(ccache)))
  endif
endif

ifneq ($(TARGET_KERNEL_CLANG_VERSION),)
    KERNEL_CROSS_COMPILE := CROSS_COMPILE="$(KERNEL_TOOLCHAIN_PATH)"
    ifeq ($(KERNEL_CC),)
        KERNEL_CC := CC="$(ccache) $(TARGET_KERNEL_CLANG_PATH)/clang"
    endif
else
    KERNEL_CROSS_COMPILE := CROSS_COMPILE="$(ccache) $(KERNEL_TOOLCHAIN_PATH)"
endif
ccache =

define mv-modules
    mdpath=`find $(KERNEL_MODULES_OUT) -type f -name modules.order`;\
    if [ "$$mdpath" != "" ];then\
        mpath=`dirname $$mdpath`;\
        ko=`find $$mpath/kernel -type f -name *.ko`;\
        for i in $$ko; do $(KERNEL_TOOLCHAIN_PATH)strip --strip-unneeded $$i;\
        mv $$i $(KERNEL_MODULES_OUT)/; done;\
    fi
endef

define clean-module-folder
    mdpath=`find $(KERNEL_MODULES_OUT) -type f -name modules.order`;\
    if [ "$$mdpath" != "" ];then\
        mpath=`dirname $$mdpath`; rm -rf $$mpath;\
    fi
endef

ifeq ($(HOST_OS),darwin)
  MAKE_FLAGS += C_INCLUDE_PATH=$(ANDROID_BUILD_TOP)/external/elfutils/libelf/
endif

ifeq ($(TARGET_KERNEL_MODULES),)
    TARGET_KERNEL_MODULES := no-external-modules
endif

$(KERNEL_OUT):
	mkdir -p $(KERNEL_OUT)
	mkdir -p $(KERNEL_MODULES_OUT)

$(KERNEL_CONFIG): $(KERNEL_OUT)
	$(MAKE) $(MAKE_FLAGS) -C $(KERNEL_SRC) O=$(KERNEL_OUT) ARCH=$(KERNEL_ARCH) $(KERNEL_CROSS_COMPILE) $(KERNEL_CLANG_TRIPLE) $(KERNEL_CLANG_PATH) $(KERNEL_CC) VARIANT_DEFCONFIG=$(VARIANT_DEFCONFIG) SELINUX_DEFCONFIG=$(SELINUX_DEFCONFIG) $(KERNEL_DEFCONFIG)
	$(hide) if [ ! -z "$(KERNEL_CONFIG_OVERRIDE)" ]; then \
			echo "Overriding kernel config with '$(KERNEL_CONFIG_OVERRIDE)'"; \
			echo $(KERNEL_CONFIG_OVERRIDE) >> $(KERNEL_OUT)/.config; \
			$(MAKE) -C $(KERNEL_SRC) O=$(KERNEL_OUT) ARCH=$(KERNEL_ARCH) $(KERNEL_CROSS_COMPILE) $(KERNEL_CLANG_TRIPLE) $(KERNEL_CLANG_PATH) $(KERNEL_CC) oldconfig; fi
	$(hide) if [ ! -z "$(KERNEL_ADDITIONAL_CONFIG)" ]; then \
			echo "Using additional config '$(KERNEL_ADDITIONAL_CONFIG)'"; \
			cat $(KERNEL_SRC)/arch/$(KERNEL_ARCH)/configs/$(KERNEL_ADDITIONAL_CONFIG) >> $(KERNEL_OUT)/.config; \
			$(MAKE) -C $(KERNEL_SRC) O=$(KERNEL_OUT) ARCH=$(KERNEL_ARCH) $(KERNEL_CROSS_COMPILE) $(KERNEL_CLANG_TRIPLE) $(KERNEL_CLANG_PATH) $(KERNEL_CC) oldconfig; fi

TARGET_KERNEL_BINARIES: $(KERNEL_OUT) $(KERNEL_CONFIG) $(KERNEL_HEADERS_INSTALL)
	$(MAKE) $(MAKE_FLAGS) -C $(KERNEL_SRC) O=$(KERNEL_OUT) ARCH=$(KERNEL_ARCH) $(KERNEL_CROSS_COMPILE) $(KERNEL_CLANG_TRIPLE) $(KERNEL_CLANG_PATH) $(KERNEL_CC) $(TARGET_PREBUILT_INT_KERNEL_TYPE)
	-$(MAKE) $(MAKE_FLAGS) -C $(KERNEL_SRC) O=$(KERNEL_OUT) ARCH=$(KERNEL_ARCH) $(KERNEL_CROSS_COMPILE) $(KERNEL_CLANG_TRIPLE) $(KERNEL_CLANG_PATH) $(KERNEL_CC) dtbs
	-$(MAKE) $(MAKE_FLAGS) -C $(KERNEL_SRC) O=$(KERNEL_OUT) ARCH=$(KERNEL_ARCH) $(KERNEL_CROSS_COMPILE) $(KERNEL_CLANG_TRIPLE) $(KERNEL_CLANG_PATH) $(KERNEL_CC) modules
	-$(MAKE) $(MAKE_FLAGS) -C $(KERNEL_SRC) O=$(KERNEL_OUT) INSTALL_MOD_PATH=../../$(KERNEL_MODULES_INSTALL) ARCH=$(KERNEL_ARCH) $(KERNEL_CROSS_COMPILE) $(KERNEL_CLANG_TRIPLE) $(KERNEL_CLANG_PATH) $(KERNEL_CC) modules_install
	$(mv-modules)
	$(clean-module-folder)

$(TARGET_KERNEL_MODULES): TARGET_KERNEL_BINARIES

$(TARGET_PREBUILT_INT_KERNEL): $(TARGET_KERNEL_MODULES)
	$(mv-modules)
	$(clean-module-folder)

$(KERNEL_HEADERS_INSTALL): $(KERNEL_OUT) $(KERNEL_CONFIG)
	$(hide) if [ ! -z "$(KERNEL_HEADER_DEFCONFIG)" ]; then \
			rm -f ../$(KERNEL_CONFIG); \
			$(MAKE) $(MAKE_FLAGS) -C $(KERNEL_SRC) O=$(KERNEL_OUT) ARCH=$(KERNEL_HEADER_ARCH) $(KERNEL_CROSS_COMPILE) $(KERNEL_CLANG_TRIPLE) $(KERNEL_CLANG_PATH) $(KERNEL_CC) VARIANT_DEFCONFIG=$(VARIANT_DEFCONFIG) SELINUX_DEFCONFIG=$(SELINUX_DEFCONFIG) $(KERNEL_HEADER_DEFCONFIG); \
			$(MAKE) $(MAKE_FLAGS) -C $(KERNEL_SRC) O=$(KERNEL_OUT) ARCH=$(KERNEL_HEADER_ARCH) $(KERNEL_CROSS_COMPILE) $(KERNEL_CLANG_TRIPLE) $(KERNEL_CLANG_PATH) $(KERNEL_CC) headers_install; fi
	$(hide) if [ "$(KERNEL_HEADER_DEFCONFIG)" != "$(KERNEL_DEFCONFIG)" ]; then \
			echo "Used a different defconfig for header generation"; \
			rm -f ../$(KERNEL_CONFIG); \
			$(MAKE) $(MAKE_FLAGS) -C $(KERNEL_SRC) O=$(KERNEL_OUT) ARCH=$(KERNEL_ARCH) $(KERNEL_CROSS_COMPILE) $(KERNEL_CLANG_TRIPLE) $(KERNEL_CLANG_PATH) $(KERNEL_CC) VARIANT_DEFCONFIG=$(VARIANT_DEFCONFIG) SELINUX_DEFCONFIG=$(SELINUX_DEFCONFIG) $(KERNEL_DEFCONFIG); fi
	$(hide) if [ ! -z "$(KERNEL_CONFIG_OVERRIDE)" ]; then \
			echo "Overriding kernel config with '$(KERNEL_CONFIG_OVERRIDE)'"; \
			echo $(KERNEL_CONFIG_OVERRIDE) >> $(KERNEL_OUT)/.config; \
			$(MAKE) $(MAKE_FLAGS) -C $(KERNEL_SRC) O=$(KERNEL_OUT) ARCH=$(KERNEL_ARCH) $(KERNEL_CROSS_COMPILE) $(KERNEL_CLANG_TRIPLE) $(KERNEL_CLANG_PATH) $(KERNEL_CC) oldconfig; fi
	$(hide) if [ ! -z "$(KERNEL_ADDITIONAL_CONFIG)" ]; then \
			echo "Using additional config '$(KERNEL_ADDITIONAL_CONFIG)'"; \
			cat $(KERNEL_SRC)/arch/$(KERNEL_ARCH)/configs/$(KERNEL_ADDITIONAL_CONFIG) >> $(KERNEL_OUT)/.config; \
			$(MAKE) $(MAKE_FLAGS) -C $(KERNEL_SRC) O=$(KERNEL_OUT) ARCH=$(KERNEL_ARCH) $(KERNEL_CROSS_COMPILE) $(KERNEL_CLANG_TRIPLE) $(KERNEL_CLANG_PATH) $(KERNEL_CC) oldconfig; fi

kerneltags: $(KERNEL_OUT) $(KERNEL_CONFIG)
	$(MAKE) -C $(KERNEL_SRC) O=$(KERNEL_OUT) ARCH=$(KERNEL_ARCH) $(KERNEL_CROSS_COMPILE) $(KERNEL_CLANG_TRIPLE) $(KERNEL_CLANG_PATH) $(KERNEL_CC) tags

kernelconfig: $(KERNEL_OUT) $(KERNEL_CONFIG)
	env KCONFIG_NOTIMESTAMP=true \
		 $(MAKE) -C $(KERNEL_SRC) O=$(KERNEL_OUT) ARCH=$(KERNEL_ARCH) $(KERNEL_CROSS_COMPILE) $(KERNEL_CLANG_TRIPLE) $(KERNEL_CLANG_PATH) $(KERNEL_CC) menuconfig
	env KCONFIG_NOTIMESTAMP=true \
		 $(MAKE) -C $(KERNEL_SRC) O=$(KERNEL_OUT) ARCH=$(KERNEL_ARCH) $(KERNEL_CROSS_COMPILE) $(KERNEL_CLANG_TRIPLE) $(KERNEL_CLANG_PATH) $(KERNEL_CC) savedefconfig
	cp $(KERNEL_OUT)/defconfig $(KERNEL_SRC)/arch/$(KERNEL_ARCH)/configs/$(KERNEL_DEFCONFIG)

TARGET_PREBUILT_DTBO = $(PRODUCT_OUT)/dtbo/arch/$(KERNEL_ARCH)/boot/dtbo.img
ifeq ($(BOARD_AVB_ENABLE),true)
$(TARGET_PREBUILT_DTBO): $(AVBTOOL)
	echo -e ${CL_GRN}"Building DTBO.img"${CL_RST}
	$(MAKE) $(MAKE_FLAGS) -C $(KERNEL_SRC) O=$(PRODUCT_OUT)/dtbo ARCH=$(KERNEL_ARCH) $(KERNEL_CROSS_COMPILE) $(KERNEL_CLANG_TRIPLE) $(KERNEL_CC) $(KERNEL_DEFCONFIG)
	$(MAKE) $(MAKE_FLAGS) -C $(KERNEL_SRC) O=$(PRODUCT_OUT)/dtbo ARCH=$(KERNEL_ARCH) $(KERNEL_CROSS_COMPILE) $(KERNEL_CLANG_TRIPLE) $(KERNEL_CC) dtbo.img
	$(AVBTOOL) add_hash_footer \
		--image $@ \
		--partition_size $(BOARD_DTBOIMG_PARTITION_SIZE) \
		--partition_name dtbo $(INTERNAL_AVB_DTBO_SIGNING_ARGS) \
		$(BOARD_AVB_DTBO_ADD_HASH_FOOTER_ARGS)
else
$(TARGET_PREBUILT_DTBO):
	echo -e ${CL_GRN}"Building DTBO.img"${CL_RST}
	$(MAKE) $(MAKE_FLAGS) -C $(KERNEL_SRC) O=$(PRODUCT_OUT)/dtbo ARCH=$(KERNEL_ARCH) $(KERNEL_CROSS_COMPILE) $(KERNEL_CLANG_TRIPLE) $(KERNEL_CC) $(KERNEL_DEFCONFIG)
	$(MAKE) $(MAKE_FLAGS) -C $(KERNEL_SRC) O=$(PRODUCT_OUT)/dtbo ARCH=$(KERNEL_ARCH) $(KERNEL_CROSS_COMPILE) $(KERNEL_CLANG_TRIPLE) $(KERNEL_CC) dtbo.img
endif #BOARD_AVB_ENABLE
endif # FULL_KERNEL_BUILD

## Install it

ifeq ($(NEEDS_KERNEL_COPY),true)
file := $(INSTALLED_KERNEL_TARGET)
ALL_PREBUILT += $(file)
$(file) : $(KERNEL_BIN) | $(ACP)
	$(transform-prebuilt-to-target)

ALL_PREBUILT += $(INSTALLED_KERNEL_TARGET)
endif

ifeq ($(TARGET_NEEDS_DTBOIMAGE),true)
file := $(INSTALLED_DTBOIMAGE_TARGET)
ALL_PREBUILT += $(file)
$(file) : $(TARGET_PREBUILT_DTBO) | $(ACP)
	$(transform-prebuilt-to-target)

ALL_PREBUILT += $(INSTALLED_DTBOIMAGE_TARGET)
endif

.PHONY: dtbo
dtbo: $(INSTALLED_DTBOIMAGE_TARGET)
