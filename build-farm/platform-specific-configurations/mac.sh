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

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# shellcheck source=sbin/common/constants.sh
source "$SCRIPT_DIR/../../sbin/common/constants.sh"

export MACOSX_DEPLOYMENT_TARGET=10.8
export BUILD_ARGS="${BUILD_ARGS}"

XCODE_SWITCH_PATH="/";

if [ "${FOREST_NAME}" == "${JDK8_VERSION}" ]
then
  XCODE_SWITCH_PATH="/Applications/Xcode.app"
fi
sudo xcode-select --switch "${XCODE_SWITCH_PATH}"


if [ "${FOREST_NAME}" != "${JDK8_VERSION}" ]
then
    export PATH="/Users/jenkins/ccache-3.2.4:$PATH"
fi


if [ "${FOREST_NAME}" == "${JDK11_VERSION}" ] || [ "${FOREST_NAME}" == "${JDKHEAD_VERSION}" ]
then
    export CONFIGURE_ARGS_FOR_ANY_PLATFORM="${CONFIGURE_ARGS_FOR_ANY_PLATFORM} --with-extra-cxxflags=-mmacosx-version-min=10.8"

    export JDK10_BOOT_DIR="$PWD/jdk-10"
    if [ ! -d "$JDK10_BOOT_DIR/bin" ]; then
      mkdir -p "$JDK10_BOOT_DIR"
      wget -q -O - 'https://api.adoptopenjdk.net/v2/binary/releases/openjdk10?os=mac&release=latest' | tar xpzf - --strip-components=2 -C "$JDK10_BOOT_DIR"
    fi
    export JDK_BOOT_DIR=$JDK10_BOOT_DIR
fi