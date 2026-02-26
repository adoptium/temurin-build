# ********************************************************************************
# Copyright (c) 2017 Contributors to the Eclipse Foundation
#
# See the NOTICE file(s) with this work for additional
# information regarding copyright ownership.
#
# This program and the accompanying materials are made
# available under the terms of the Apache Software License 2.0
# which is available at https://www.apache.org/licenses/LICENSE-2.0.
#
# SPDX-License-Identifier: Apache-2.0
# ********************************************************************************

ADOPTIUM_DEVKIT_URL := https://github.com/adoptium/devkit-binaries/releases/download

ifneq (,$(findstring $(JDK_VERSION),21))
  # jdk-21 devkit
  ifneq ($(filter linux_x86-64, $(SPEC)),)
    LINUX_ADOPTIUM_DEVKIT := $(ADOPTIUM_DEVKIT_URL)/gcc-11.3.0-Centos7.9.2009-b04/devkit-gcc-11.3.0-Centos7.9.2009-b04-x86_64-linux-gnu.tar.xz
  else ifneq ($(filter linux_aarch64, $(SPEC)),)
    LINUX_ADOPTIUM_DEVKIT := $(ADOPTIUM_DEVKIT_URL)/gcc-11.3.0-Centos7.6.1810-b04/devkit-gcc-11.3.0-Centos7.6.1810-b04-aarch64-linux-gnu.tar.xz
  else ifneq ($(filter linux_ppc-64_le, $(SPEC)),)
    LINUX_ADOPTIUM_DEVKIT := $(ADOPTIUM_DEVKIT_URL)/gcc-11.3.0-Centos7.9.2009-b04/devkit-gcc-11.3.0-Centos7.9.2009-b04-ppc64le-linux-gnu.tar.xz
  else ifneq ($(filter linux_390-64, $(SPEC)),)
    LINUX_ADOPTIUM_DEVKIT := $(ADOPTIUM_DEVKIT_URL)/gcc-11.3.0-Centos7.9.2009-b04/devkit-gcc-11.3.0-Centos7.9.2009-b04-s390x-linux-gnu.tar.xz
  endif
else
  # jdk-25+ devkit
  ifneq ($(filter linux_x86-64, $(SPEC)),)
    LINUX_ADOPTIUM_DEVKIT := $(ADOPTIUM_DEVKIT_URL)/gcc-14.2.0-Centos7.9.2009-b01/devkit-gcc-14.2.0-Centos7.9.2009-b01-x86_64-linux-gnu.tar.xz
  else ifneq ($(filter linux_aarch64, $(SPEC)),)
    LINUX_ADOPTIUM_DEVKIT := $(ADOPTIUM_DEVKIT_URL)/gcc-14.2.0-Centos7.6.1810-b01/devkit-gcc-14.2.0-Centos7.6.1810-b01-aarch64-linux-gnu.tar.xz
  else ifneq ($(filter linux_ppc-64_le, $(SPEC)),)
    LINUX_ADOPTIUM_DEVKIT := $(ADOPTIUM_DEVKIT_URL)/gcc-14.2.0-Centos7.9.2009-b01/devkit-gcc-14.2.0-Centos7.9.2009-b01-ppc64le-linux-gnu.tar.xz
  else ifneq ($(filter linux_390-64, $(SPEC)),)
    LINUX_ADOPTIUM_DEVKIT := $(ADOPTIUM_DEVKIT_URL)/gcc-14.2.0-Centos7.9.2009-b01/devkit-gcc-14.2.0-Centos7.9.2009-b01-s390x-linux-gnu.tar.xz
  endif
endif

WINDOWS_ADOPTIUM_DEVKIT := $(ADOPTIUM_DEVKIT_URL)/vs2022_redist_14.40.33807_10.0.26100.1742/vs2022_redist_14.40.33807_10.0.26100.1742.zip

ifndef SBOM_FILE
    SBOM_FILE := $(shell ls $(TEST_ROOT)/../jdkbinary/ | grep "sbom" | grep -v "metadata")
    ifeq ($(strip $(SBOM_FILE)),)
        $(info ERROR! NO SBOM_FILE AVAILABLE)
        SBOM_FILE :=
    else
        SBOM_FILE := $(TEST_ROOT)/../jdkbinary/$(SBOM_FILE)
    endif
    $(info sbom $(SBOM_FILE))
endif

ifndef JDK_FILE
    JDK_FILE := $(shell find $(TEST_ROOT)/../jdkbinary/ -type f -name '*-jdk_*.tar.gz')
    ifneq (,$(findstring win,$(SPEC)))
        JDK_FILE := $(shell find $(TEST_ROOT)/../jdkbinary/ -type f -name '*-jdk_*.zip')
    endif
    ifeq ($(strip $(JDK_FILE)),)
        $(info ERROR! NO JDK_FILE AVAILABLE)
    endif
endif

RM_DEBUGINFO := $(shell find $(TEST_JDK_HOME) -type f -name "*.debuginfo" -delete)
