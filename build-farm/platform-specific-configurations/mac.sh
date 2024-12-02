#!/bin/bash
# shellcheck disable=SC1091,SC2140
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

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# shellcheck source=sbin/common/constants.sh
source "$SCRIPT_DIR/../../sbin/common/constants.sh"

export MACOSX_DEPLOYMENT_TARGET=10.9
export BUILD_ARGS="${BUILD_ARGS}"

c_flags_bucket=""
cxx_flags_bucket=""

## JDK8 only: If, at this point in the build, the architecure of the machine is arm64 while the ARCHITECTURE variable
## is x64 then we need to add the cross compilation option --openjdk-target=x86_64-apple-darwin
MACHINEARCHITECTURE=$(uname -m)

if [[ "${MACHINEARCHITECTURE}" == "arm64" ]] && [[ "${ARCHITECTURE}" == "x64" ]]; then
  # Adds cross compilation arg if building x64 binary on arm64
  export CONFIGURE_ARGS_FOR_ANY_PLATFORM="${CONFIGURE_ARGS_FOR_ANY_PLATFORM} --openjdk-target=x86_64-apple-darwin"
fi

if [ "${JAVA_TO_BUILD}" == "${JDK8_VERSION}" ]
then
  export CONFIGURE_ARGS_FOR_ANY_PLATFORM="${CONFIGURE_ARGS_FOR_ANY_PLATFORM} --with-toolchain-type=clang"
  if [[ "${MACHINEARCHITECTURE}" == "arm64" ]] && [[ "${ARCHITECTURE}" == "x64" ]]; then
    # Cross compilation config needed only for jdk8
    export MAC_ROSETTA_PREFIX="arch -x86_64"
    export PATH=/opt/homebrew/bin:/usr/local/bin:$PATH
    XCODE_SWITCH_PATH="/Applications/Xcode-11.7.app"
  else
    XCODE_SWITCH_PATH="/Applications/Xcode.app"
  fi
  if [ "${VARIANT}" == "${BUILD_VARIANT_OPENJ9}" ]; then
    export CONFIGURE_ARGS_FOR_ANY_PLATFORM="${CONFIGURE_ARGS_FOR_ANY_PLATFORM} --with-openssl=fetched --enable-openssl-bundling"
    export BUILD_ARGS="${BUILD_ARGS} --skip-freetype"
  fi
else
  if [[ "$JAVA_FEATURE_VERSION" -ge 11 ]]; then
    # JDK17 requires metal (included in full xcode) as does JDK11 on aarch64
    # JDK11 on x64 is matched for consistency
    XCODE_SWITCH_PATH="/Applications/Xcode.app"
    # JDK11 (x86 and aarch) has excessive warnings.
    # This is due to a harfbuzz fix which is pending backport.
    # Suppressing the warnings for now to aid triage.
    if [[ "$JAVA_FEATURE_VERSION" -le 11 ]]; then
      export cxx_flags_bucket="${cxx_flags_bucket} -Wno-deprecated-builtins -Wno-deprecated-declarations -Wno-deprecated-non-prototype"
      export c_flags_bucket="${c_flags_bucket} -Wno-deprecated-builtins -Wno-deprecated-declarations -Wno-deprecated-non-prototype"
    fi
  else
    # Command line tools used from JDK9-JDK10
    XCODE_SWITCH_PATH="/";
  fi
  export PATH="/Users/jenkins/ccache-3.2.4:$PATH"
  if [ "${VARIANT}" == "${BUILD_VARIANT_OPENJ9}" ]; then
    export CONFIGURE_ARGS_FOR_ANY_PLATFORM="${CONFIGURE_ARGS_FOR_ANY_PLATFORM} --with-openssl=fetched --enable-openssl-bundling"
  else
    if [ "${ARCHITECTURE}" == "x64" ]; then
      # We can only target 10.9 on intel macs
      export cxx_flags_bucket="${cxx_flags_bucket} -mmacosx-version-min=10.9"
    elif [[ "${MACHINEARCHITECTURE}" == "x64" ]] && [[ "${ARCHITECTURE}" == "aarch64" ]]; then
      export CONFIGURE_ARGS_FOR_ANY_PLATFORM="${CONFIGURE_ARGS_FOR_ANY_PLATFORM} --openjdk-target=aarch64-apple-darwin"
    fi
  fi
fi

if [[ "$JAVA_FEATURE_VERSION" -ge 21 ]]; then
  # jdk-21+ uses "bundled" FreeType
  export BUILD_ARGS="${BUILD_ARGS} --freetype-dir bundled"
fi

# The configure option '--with-macosx-codesign-identity' is supported in JDK8 OpenJ9 and JDK11 and JDK14+
if [[ ( "$JAVA_FEATURE_VERSION" -eq 11 ) || ( "$JAVA_FEATURE_VERSION" -ge 14 ) ]]
then
  export CONFIGURE_ARGS_FOR_ANY_PLATFORM="${CONFIGURE_ARGS_FOR_ANY_PLATFORM} --with-sysroot=/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/"
  ## Login to KeyChain
  ## shellcheck disable=SC2046
  ## shellcheck disable=SC2006
  #security unlock-keychain -p `cat ~/.password` login.keychain-db
  #rm -rf codesign-test && touch codesign-test
  #codesign --sign "Developer ID Application: London Jamocha Community CIC" codesign-test
  #codesign -dvvv codesign-test
  #export BUILD_ARGS="${BUILD_ARGS} --codesign-identity 'Developer ID Application: London Jamocha Community CIC'"
fi

echo "[WARNING] You may be asked for your su user password, attempting to switch Xcode version to ${XCODE_SWITCH_PATH}"
sudo xcode-select --switch "${XCODE_SWITCH_PATH}"

# No MacOS builds available of OpenJDK 7, OpenJDK 8 can boot itself just fine.
if [ "${JDK_BOOT_VERSION}" == "7" ]; then
  echo "No jdk7 boot JDK available on MacOS using jdk8"
  JDK_BOOT_VERSION="8"
fi
BOOT_JDK_VARIABLE="JDK${JDK_BOOT_VERSION}_BOOT_DIR"
if [ ! -d "$(eval echo "\$$BOOT_JDK_VARIABLE")" ]; then
  bootDir="$PWD/jdk$JDK_BOOT_VERSION"
  # Note we export $BOOT_JDK_VARIABLE (i.e. JDKXX_BOOT_DIR) here
  # instead of BOOT_JDK_VARIABLE (no '$').
  export "${BOOT_JDK_VARIABLE}"="$bootDir/Contents/Home"
  if [ ! -x "$bootDir/Contents/Home/bin/javac" ]; then
    # To support multiple vendor names we set a jdk* symlink pointing to the actual boot JDK
    if [ -x "/Library/Java/JavaVirtualMachines/jdk${JDK_BOOT_VERSION}/Contents/Home/bin/javac" ]; then
      echo "Could not use ${BOOT_JDK_VARIABLE} - using /Library/Java/JavaVirtualMachines/jdk${JDK_BOOT_VERSION}/Contents/Home"
      export "${BOOT_JDK_VARIABLE}"="/Library/Java/JavaVirtualMachines/jdk${JDK_BOOT_VERSION}/Contents/Home"
    elif [ -x "/Library/Java/JavaVirtualMachines/jdk-${JDK_BOOT_VERSION}/Contents/Home/bin/javac" ]; then
      # TODO: This temporary ELIF allows us to accomodate undesired dashes that may be present
      # in boot directory names (e.g. jdk-10) on Orka node images (fix pending).
      echo "Could not use ${BOOT_JDK_VARIABLE} - using /Library/Java/JavaVirtualMachines/jdk-${JDK_BOOT_VERSION}/Contents/Home"
      export "${BOOT_JDK_VARIABLE}"="/Library/Java/JavaVirtualMachines/jdk-${JDK_BOOT_VERSION}/Contents/Home"
    elif [ "$JDK_BOOT_VERSION" -ge 8 ]; then # Adoptium has no build pre-8
      mkdir -p "$bootDir"
      for releaseType in "ga" "ea"
      do
        # shellcheck disable=SC2034
        for vendor1 in "adoptium" "adoptopenjdk"
        do
          # shellcheck disable=SC2034
          for vendor2 in "eclipse" "adoptium" "adoptopenjdk"
          do
            apiUrlTemplate="https://api.\${vendor1}.net/v3/binary/latest/\${JDK_BOOT_VERSION}/\${releaseType}/mac/\${ARCHITECTURE}/jdk/hotspot/normal/\${vendor2}"
            apiURL=$(eval echo ${apiUrlTemplate})
            echo "Downloading ${releaseType} release of boot JDK version ${JDK_BOOT_VERSION} from ${apiURL}"
            set +e
            wget -q -O "${JDK_BOOT_VERSION}.tgz" "${apiURL}" && tar xpzf "${JDK_BOOT_VERSION}.tgz" --strip-components=1 -C "$bootDir" && rm "${JDK_BOOT_VERSION}.tgz"
            retVal=$?
            set -e
            if [ $retVal -eq 0 ]; then
              break 3
            fi
          done
        done
      done
    fi
  fi
fi

# shellcheck disable=SC2155
export JDK_BOOT_DIR="$(eval echo "\$$BOOT_JDK_VARIABLE")"
"$JDK_BOOT_DIR/bin/java" -version 2>&1 | sed 's/^/BOOT JDK: /'
"$JDK_BOOT_DIR/bin/java" -version > /dev/null 2>&1
executedJavaVersion=$?
if [ $executedJavaVersion -ne 0 ]; then
  echo "Failed to obtain or find a valid boot jdk"
  exit 1
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

if [ ! "${c_flags_bucket}" = "" ]; then
  export CONFIGURE_ARGS_FOR_ANY_PLATFORM="${CONFIGURE_ARGS_FOR_ANY_PLATFORM} --with-extra-cflags='${c_flags_bucket}'"
fi

if [ ! "${cxx_flags_bucket}" = "" ]; then
  export CONFIGURE_ARGS_FOR_ANY_PLATFORM="${CONFIGURE_ARGS_FOR_ANY_PLATFORM} --with-extra-cxxflags='${cxx_flags_bucket}'"
fi