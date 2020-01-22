#!/bin/bash

################################################################################
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
################################################################################

export JDK8_VERSION="jdk8u";
export JDK9_VERSION="jdk9u";
export JDK10_VERSION="jdk10u";
export JDK11_VERSION="jdk11u";
export JDK12_VERSION="jdk12u";
export JDK13_VERSION="jdk13u";
export JDK14_VERSION="jdk14";
export JDKHEAD_VERSION="jdk";

export JDK8_CORE_VERSION="jdk8";
export JDK9_CORE_VERSION="jdk9";
export JDK10_CORE_VERSION="jdk10";
export JDK11_CORE_VERSION="jdk11";
export JDK12_CORE_VERSION="jdk12";
export JDK13_CORE_VERSION="jdk13";
export JDK14_CORE_VERSION="${JDK14_VERSION}";
export JDKHEAD_CORE_VERSION="${JDKHEAD_VERSION}";
export AMBER_CORE_VERSION="amber";

export BUILD_VARIANT_HOTSPOT="hotspot"
export BUILD_VARIANT_HOTSPOT_JFR="hotspot-jfr"
export BUILD_VARIANT_OPENJ9="openj9"
export BUILD_VARIANT_CORRETTO="corretto"
export BUILD_VARIANT_SAP="SapMachine"

export GIT_TAGS_TO_SEARCH=100

export ADOPTOPENJDK_MD_MARKER_FILE="AdoptOpenJDK.md"
