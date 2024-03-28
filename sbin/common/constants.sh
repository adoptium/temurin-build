#!/bin/bash
# ********************************************************************************
# Copyright (c) 2018 Contributors to the Eclipse Foundation
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

# Version Strings
export JDK8_VERSION="jdk8u";
export JDK9_VERSION="jdk9u";
export JDK10_VERSION="jdk10u";
export JDK11_VERSION="jdk11u";
export JDK12_VERSION="jdk12u";
export JDK13_VERSION="jdk13u";
export JDK14_VERSION="jdk14u";
export JDK15_VERSION="jdk15u";
export JDK16_VERSION="jdk16u";
export JDK17_VERSION="jdk17u";
export JDK18_VERSION="jdk18u";
export JDKHEAD_VERSION="jdk";

export JDK8_CORE_VERSION="jdk8";
export JDK9_CORE_VERSION="jdk9";
export JDK10_CORE_VERSION="jdk10";
export JDK11_CORE_VERSION="jdk11";
export JDK12_CORE_VERSION="jdk12";
export JDK13_CORE_VERSION="jdk13";
export JDK14_CORE_VERSION="jdk14";
export JDK15_CORE_VERSION="jdk15";
export JDK16_CORE_VERSION="jdk16";
export JDK17_CORE_VERSION="jdk17";
export JDK18_CORE_VERSION="jdk18";
export JDKHEAD_CORE_VERSION="${JDKHEAD_VERSION}";
export AMBER_CORE_VERSION="amber";

# Variants
export BUILD_VARIANT_HOTSPOT="hotspot"
export BUILD_VARIANT_TEMURIN="temurin"
export BUILD_VARIANT_OPENJ9="openj9"
export BUILD_VARIANT_CORRETTO="corretto"
export BUILD_VARIANT_SAP="SapMachine"
export BUILD_VARIANT_DRAGONWELL="dragonwell"
export BUILD_VARIANT_BISHENG="bisheng"
export BUILD_VARIANT_FAST_STARTUP="fast_startup"
export BUILD_VARIANTS="${BUILD_VARIANT_HOTSPOT} ${BUILD_VARIANT_TEMURIN} ${BUILD_VARIANT_OPENJ9} ${BUILD_VARIANT_CORRETTO} ${BUILD_VARIANT_SAP} ${BUILD_VARIANT_DRAGONWELL} ${BUILD_VARIANT_FAST_STARTUP} ${BUILD_VARIANT_BISHENG}"

# Git Tags to peruse
export GIT_TAGS_TO_SEARCH=100

# Path of marker file in mirror repos containing required text
export TEMURIN_MARKER_FILE="README.JAVASE"
