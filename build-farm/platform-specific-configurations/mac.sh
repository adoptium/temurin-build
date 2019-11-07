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

# A function that returns true if the variant is based on Hotspot and should
# be treated as such by this build script. There is a similar function in
# sbin/common.sh but we didn't want to refactor all of this on release day.
function isHotSpot() {
  [ "${VARIANT}" == "${BUILD_VARIANT_HOTSPOT}" ] ||
  [ "${VARIANT}" == "${BUILD_VARIANT_HOTSPOT_JFR}" ] ||
  [ "${VARIANT}" == "${BUILD_VARIANT_SAP}" ] ||
  [ "${VARIANT}" == "${BUILD_VARIANT_CORRETTO}" ]
}

export MACOSX_DEPLOYMENT_TARGET=10.8
export BUILD_ARGS="${BUILD_ARGS}"

XCODE_SWITCH_PATH="/";

if [ "${JAVA_TO_BUILD}" == "${JDK8_VERSION}" ]
then
  XCODE_SWITCH_PATH="/Applications/Xcode.app"
  # See https://github.com/AdoptOpenJDK/openjdk-build/issues/1202
  if isHotSpot; then
    export COMPILER_WARNINGS_FATAL=false
    echo "Compiler Warnings set to: $COMPILER_WARNINGS_FATAL"
  fi
else
  export PATH="/Users/jenkins/ccache-3.2.4:$PATH"
  if [ "${VARIANT}" == "${BUILD_VARIANT_OPENJ9}" ]; then
    export CONFIGURE_ARGS_FOR_ANY_PLATFORM="${CONFIGURE_ARGS_FOR_ANY_PLATFORM} --with-openssl=fetched --enable-openssl-bundling"
  else
    export CONFIGURE_ARGS_FOR_ANY_PLATFORM="${CONFIGURE_ARGS_FOR_ANY_PLATFORM} --with-extra-cxxflags=-mmacosx-version-min=10.8"
  fi
fi

sudo xcode-select --switch "${XCODE_SWITCH_PATH}"

# Any version above 8
if [ "$JAVA_FEATURE_VERSION" -gt 8 ]; then

    BOOT_JDK_VERSION="$((JAVA_FEATURE_VERSION-1))"
    BOOT_JDK_VARIABLE="JDK$(echo $BOOT_JDK_VERSION)_BOOT_DIR"
    if [ ! -d "$(eval echo "\$$BOOT_JDK_VARIABLE")" ]; then
      export $BOOT_JDK_VARIABLE="$PWD/jdk-$BOOT_JDK_VERSION"
      if [ ! -d "$(eval echo "\$$BOOT_JDK_VARIABLE/Contents/Home/bin")" ]; then
        mkdir -p "$(eval echo "\$$BOOT_JDK_VARIABLE")"
        wget -q -O - "https://api.adoptopenjdk.net/v2/binary/releases/openjdk${BOOT_JDK_VERSION}?os=mac&release=latest&arch=${ARCHITECTURE}&heap_size=normal&type=jdk&openjdk_impl=hotspot" | tar xpzf - --strip-components=1 -C "$(eval echo "\$$BOOT_JDK_VARIABLE")"
      fi
      export JDK_BOOT_DIR="$(eval echo "\$$BOOT_JDK_VARIABLE/Contents/Home")"
    else
      export JDK_BOOT_DIR="$(eval echo "\$$BOOT_JDK_VARIABLE")"
    fi
fi

if [ "${VARIANT}" == "${BUILD_VARIANT_OPENJ9}" ]; then
  # Needed for the later nasm
  export PATH=/usr/local/bin:$PATH
  # ccache causes too many errors (either the default version on 3.2.4) so disabling
  export CONFIGURE_ARGS_FOR_ANY_PLATFORM="--disable-ccache ${CONFIGURE_ARGS_FOR_ANY_PLATFORM}"
  export MACOSX_DEPLOYMENT_TARGET=10.9.0
  if [ "${JAVA_TO_BUILD}" == "${JDK8_VERSION}" ]
  then
    export SED=gsed
    export TAR=gtar
    export SDKPATH=/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX10.8.sdk
    export CONFIGURE_ARGS_FOR_ANY_PLATFORM="${CONFIGURE_ARGS_FOR_ANY_PLATFORM} --with-xcode-path=/Applications/Xcode.app --with-openj9-cc=/Applications/Xcode7/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang --with-openj9-cxx=/Applications/Xcode7/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang++ --with-openj9-developer-dir=/Applications/Xcode7/Xcode.app/Contents/Developer"
  fi
fi

