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

ifndef SBOM_FILE
	SBOM_FILE := $(shell ls $(TEST_ROOT)/../jdkbinary/ | grep "sbom" | grep -v "metadata")
	SBOM_FILE := $(TEST_ROOT)/../jdkbinary/$(SBOM_FILE)
endif
ifndef JDK_FILE
	ifneq (,$(findstring win,$(SPEC)))
		JDK_FILE := $(shell find $(TEST_ROOT)/../jdkbinary/ -type f -name '*-jdk_*.zip')
	endif
endif

ifneq (,$(findstring linux,$(SPEC)))
	SBOM_FILE := $(subst $(TEST_ROOT)/../jdkbinary,/home/jenkins/test,$(SBOM_FILE))
endif