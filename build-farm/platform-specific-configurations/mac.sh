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
  [ "${VARIANT}" == "${BUILD_VARIANT_SAP}" ] ||
  [ "${VARIANT}" == "${BUILD_VARIANT_CORRETTO}" ]
}

export MACOSX_DEPLOYMENT_TARGET=10.9
export BUILD_ARGS="${BUILD_ARGS}"

XCODE_SWITCH_PATH="/";

if [ "${JAVA_TO_BUILD}" == "${JDK8_VERSION}" ]
then
  XCODE_SWITCH_PATH="/Applications/Xcode.app"
  export CONFIGURE_ARGS_FOR_ANY_PLATFORM="${CONFIGURE_ARGS_FOR_ANY_PLATFORM} --with-toolchain-type=clang"
  # See https://github.com/AdoptOpenJDK/openjdk-build/issues/1202
  if isHotSpot; then
    export COMPILER_WARNINGS_FATAL=false
    echo "Compiler Warnings set to: $COMPILER_WARNINGS_FATAL"
  fi
  if [ "${VARIANT}" == "${BUILD_VARIANT_OPENJ9}" ]; then
    export CONFIGURE_ARGS_FOR_ANY_PLATFORM="${CONFIGURE_ARGS_FOR_ANY_PLATFORM} --with-openssl=fetched --enable-openssl-bundling"
  fi
else
  export PATH="/Users/jenkins/ccache-3.2.4:$PATH"
  if [ "${VARIANT}" == "${BUILD_VARIANT_OPENJ9}" ]; then
    export CONFIGURE_ARGS_FOR_ANY_PLATFORM="${CONFIGURE_ARGS_FOR_ANY_PLATFORM} --with-openssl=fetched --enable-openssl-bundling"
  else
    export CONFIGURE_ARGS_FOR_ANY_PLATFORM="${CONFIGURE_ARGS_FOR_ANY_PLATFORM} --with-extra-cxxflags=-mmacosx-version-min=10.9"
  fi
fi

# The configure option '--with-macosx-codesign-identity' is supported in JDK8 OpenJ9 and JDK11 and JDK14+
if [[ ( "$JAVA_FEATURE_VERSION" -eq 11 ) || ( "$JAVA_FEATURE_VERSION" -ge 14 ) || ( "$JAVA_FEATURE_VERSION" -eq 8 && "${VARIANT}" == "${BUILD_VARIANT_OPENJ9}" ) ]]
then
  export CONFIGURE_ARGS_FOR_ANY_PLATFORM="${CONFIGURE_ARGS_FOR_ANY_PLATFORM} --with-sysroot=/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/"
  # Login to KeyChain
  # shellcheck disable=SC2046
  # shellcheck disable=SC2006
  security unlock-keychain -p `cat ~/.password` login.keychain-db
  export BUILD_ARGS="${BUILD_ARGS} --codesign-identity 'Developer ID Application: London Jamocha Community CIC'"
fi

sudo xcode-select --switch "${XCODE_SWITCH_PATH}"

# Any version above 8 (11 for now due to openjdk-build#1409
if [ "$JAVA_FEATURE_VERSION" -gt 11 ]; then 
  BOOT_JDK_VERSION="$((JAVA_FEATURE_VERSION-1))"
  BOOT_JDK_VARIABLE="JDK$(echo $BOOT_JDK_VERSION)_BOOT_DIR"
  if [ ! -d "$(eval echo "\$$BOOT_JDK_VARIABLE")" ]; then
    bootDir="$PWD/jdk-$BOOT_JDK_VERSION"
    # Note we export $BOOT_JDK_VARIABLE (i.e. JDKXX_BOOT_DIR) here
    # instead of BOOT_JDK_VARIABLE (no '$').
    export ${BOOT_JDK_VARIABLE}="$bootDir/Contents/Home"
    if [ ! -x "$bootDir/Contents/Home/bin/javac" ]; then
      if [ -x /Library/Java/JavaVirtualMachines/adoptopenjdk-${BOOT_JDK_VERSION}/Contents/Home/bin/javac ]; then
        echo Could not use ${BOOT_JDK_VARIABLE} - using /Library/Java/JavaVirtualMachines/adoptopenjdk-${BOOT_JDK_VERSION}/Contents/Home
        export ${BOOT_JDK_VARIABLE}="/Library/Java/JavaVirtualMachines/adoptopenjdk-${BOOT_JDK_VERSION}/Contents/Home"
      else
        mkdir -p "$bootDir"
        echo "Downloading GA release of boot JDK version ${BOOT_JDK_VERSION}..."
        releaseType="ga"
        apiUrlTemplate="https://api.adoptopenjdk.net/v3/binary/latest/\${BOOT_JDK_VERSION}/\${releaseType}/mac/\${ARCHITECTURE}/jdk/\${VARIANT}/normal/adoptopenjdk"
        apiURL=$(eval echo ${apiUrlTemplate})
        # make-adopt-build-farm.sh has 'set -e'. We need to disable that
        # for the fallback mechanism, as downloading of the GA binary might
        # fail.
        set +e
        wget -q -O "${BOOT_JDK_VERSION}.tgz" "${apiURL}" && tar xpzf "${BOOT_JDK_VERSION}.tgz" --strip-components=1 -C "$bootDir" && rm "${BOOT_JDK_VERSION}.tgz"
        retVal=$?
        set -e
        if [ $retVal -ne 0 ]; then
          # We must be a JDK HEAD build for which no boot JDK exists other than
          # nightlies?
          echo "Downloading GA release of boot JDK version ${BOOT_JDK_VERSION} failed."
          echo "Attempting to download EA release of boot JDK version ${BOOT_JDK_VERSION} ..."
          # shellcheck disable=SC2034
          releaseType="ea"
          apiURL=$(eval echo ${apiUrlTemplate})
          wget -q -O - "${apiURL}" | tar xpzf - --strip-components=1 -C "$bootDir"
        fi
      fi
    fi
  fi
  export JDK_BOOT_DIR="$(eval echo "\$$BOOT_JDK_VARIABLE")"
  "$JDK_BOOT_DIR/bin/java" -version
  executedJavaVersion=$?
  if [ $executedJavaVersion -ne 0 ]; then
      echo "Failed to obtain or find a valid boot jdk"
      exit 1
  fi
  "$JDK_BOOT_DIR/bin/java" -version 2>&1 | sed 's/^/BOOT JDK: /'
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
    export SDKPATH=/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk
  fi
fi
