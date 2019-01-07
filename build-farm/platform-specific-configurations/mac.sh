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

if [ "${JAVA_TO_BUILD}" == "${JDK8_VERSION}" ]
then
  XCODE_SWITCH_PATH="/Applications/Xcode.app"
fi
sudo xcode-select --switch "${XCODE_SWITCH_PATH}"


if [ "${JAVA_TO_BUILD}" != "${JDK8_VERSION}" ]
then
    export PATH="/Users/jenkins/ccache-3.2.4:$PATH"
fi


if [ "${JAVA_TO_BUILD}" == "${JDK11_VERSION}" ] || [ "${JAVA_TO_BUILD}" == "${JDKHEAD_VERSION}" ]
then
  if [ "${VARIANT}" == "openj9" ]; then
    export CONFIGURE_ARGS_FOR_ANY_PLATFORM="${CONFIGURE_ARGS_FOR_ANY_PLATFORM} --with-openssl=fetched --enable-openssl-bundling"
  else
    export CONFIGURE_ARGS_FOR_ANY_PLATFORM="${CONFIGURE_ARGS_FOR_ANY_PLATFORM} --with-extra-cxxflags=-mmacosx-version-min=10.8"
  fi
  if [ ! -d "$JDK10_BOOT_DIR" ]; then
    export JDK10_BOOT_DIR="$PWD/jdk-10"
    if [ ! -d "$JDK10_BOOT_DIR/bin" ]; then
      mkdir -p "$JDK10_BOOT_DIR"
      wget -q -O - 'https://api.adoptopenjdk.net/v2/binary/releases/openjdk10?os=mac&release=latest' | tar xpzf - --strip-components=2 -C "$JDK10_BOOT_DIR"
    fi
  fi
  export JDK_BOOT_DIR=$JDK10_BOOT_DIR
fi

if [ "${VARIANT}" == "openj9" ]; then
  # Needed for the later nasm
  export PATH=/usr/local/bin:$PATH
  # ccache causes too many errors (either the default version on 3.2.4) so disabling
  export CONFIGURE_ARGS_FOR_ANY_PLATFORM="${CONFIGURE_ARGS_FOR_ANY_PLATFORM} --disable-ccache --with-openssl=fetched --enable-openssl-bundling"
  export MACOSX_DEPLOYMENT_TARGET=10.9.0
  if [ "${JAVA_TO_BUILD}" == "${JDK8_VERSION}" ]
  then
    export SED=gsed
    export TAR=gtar
    export SDKPATH=/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX10.8.sdk
    export CONFIGURE_ARGS_FOR_ANY_PLATFORM="${CONFIGURE_ARGS_FOR_ANY_PLATFORM} --with-xcode-path=/Applications/Xcode.app --with-openj9-cc=/Applications/Xcode7/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang --with-openj9-cxx=/Applications/Xcode7/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang++ --with-openj9-developer-dir=/Applications/Xcode7/Xcode.app/Contents/Developer"
  fi
fi
