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

WINDOWS_ADOPTIUM_DEVKIT := https://github.com/adoptium/devkit-binaries/releases/download/vs2022_redist_14.40.33807_10.0.26100.1742/vs2022_redist_14.40.33807_10.0.26100.1742.zip

ifndef SBOM_FILE
    SBOM_FILE := $(shell ls $(TEST_ROOT)/../jdkbinary/ | grep "sbom" | grep -v "metadata")
    ifeq ($(strip $(SBOM_FILE)),)
        $(info ERROR! NO SBOM_FILE AVAILABLE)
        SBOM_FILE :=
    else
        SBOM_FILE := $(TEST_ROOT)/../jdkbinary/$(SBOM_FILE)
    endif
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

ifneq (,$(findstring linux,$(SPEC)))
    ifneq ($(strip $(SBOM_FILE)),)
        SBOM_FILE := $(subst $(TEST_ROOT)/../jdkbinary,/home/jenkins/test,$(SBOM_FILE))
    endif
endif

RM_DEBUGINFO := $(shell find $(TEST_JDK_HOME) -type f -name "*.debuginfo" -delete)
