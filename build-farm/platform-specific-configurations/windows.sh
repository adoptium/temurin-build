#!/bin/bash
# shellcheck disable=SC1091

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

export ANT_HOME=/cygdrive/C/Projects/OpenJDK/apache-ant-1.10.1
export DRAGONWELL8_BOOTSTRAP=/cygdrive/C/openjdk/dragonwell-bootstrap/jdk8u272-ga
export ALLOW_DOWNLOADS=true
export LANG=C
export OPENJ9_NASM_VERSION=2.13.03
export OPENSSL_VERSION=1.1.1l

TOOLCHAIN_VERSION=""

if [ "$ARCHITECTURE" == "aarch64" ]; then
  # Windows aarch64 cross compiles requires same version boot jdk
  echo "Cross compile of aarch64 on Windows uses same boot jdk as build version, using: ${JAVA_FEATURE_VERSION}"
  JDK_BOOT_VERSION="$((JAVA_FEATURE_VERSION))"
fi
BOOT_JDK_VARIABLE="JDK${JDK_BOOT_VERSION}_BOOT_DIR"
if [ ! -d "$(eval echo "\$$BOOT_JDK_VARIABLE")" ]; then
  bootDir="$PWD/jdk-$JDK_BOOT_VERSION"
  # Note we export $BOOT_JDK_VARIABLE (i.e. JDKXX_BOOT_DIR) here
  # instead of BOOT_JDK_VARIABLE (no '$').
  export "${BOOT_JDK_VARIABLE}"="$bootDir"
  if [ ! -x "$bootDir/bin/javac.exe" ]; then
    # Set to a default location as linked in the ansible playbooks
    if [ -x "/cygdrive/c/openjdk/jdk-${JDK_BOOT_VERSION}/bin/javac" ]; then
      echo "Could not use ${BOOT_JDK_VARIABLE} - using /cygdrive/c/openjdk/jdk-${JDK_BOOT_VERSION}"
      # shellcheck disable=SC2140
      export "${BOOT_JDK_VARIABLE}"="/cygdrive/c/openjdk/jdk-${JDK_BOOT_VERSION}"
    elif [ "$JDK_BOOT_VERSION" -ge 8 ]; then # Adopt has no build pre-8
      # This is needed to convert x86-32 to x32 which is what the API uses
      export downloadArch
      case "$ARCHITECTURE" in
         "x86-32") downloadArch="x32";;
        "aarch64") downloadArch="x64";;
                *) downloadArch="$ARCHITECTURE";;
      esac
      releaseType="ga"
      vendor="adoptium"
      apiUrlTemplate="https://api.\${vendor}.net/v3/binary/latest/\${JDK_BOOT_VERSION}/\${releaseType}/windows/\${downloadArch}/jdk/\${VARIANT}/normal/\${vendor}"
      apiURL=$(eval echo ${apiUrlTemplate})
      echo "Downloading GA release of boot JDK version ${JDK_BOOT_VERSION} from ${apiURL}"
      # make-adopt-build-farm.sh has 'set -e'. We need to disable that for
      # the fallback mechanism, as downloading of the GA binary might fail
      set +e
      wget -q "${apiURL}" -O openjdk.zip
      retVal=$?
      set -e
      if [ $retVal -ne 0 ]; then
        # We must be a JDK HEAD build for which no boot JDK exists other than
        # nightlies?
        echo "Downloading GA release of boot JDK version ${JDK_BOOT_VERSION} failed."
        # shellcheck disable=SC2034
        releaseType="ea"
        # shellcheck disable=SC2034
        vendor="adoptium"
        apiURL=$(eval echo ${apiUrlTemplate})
        echo "Attempting to download EA release of boot JDK version ${JDK_BOOT_VERSION} from ${apiURL}"
        set +e
        wget -q "${apiURL}" -O openjdk.zip
        retVal=$?
        set -e
        if [ $retVal -ne 0 ]; then
          # If no binaries are available then try from adoptopenjdk
          echo "Downloading Temurin release of boot JDK version ${JDK_BOOT_VERSION} failed."
          # shellcheck disable=SC2034
          releaseType="ga"
          # shellcheck disable=SC2034
          vendor="adoptopenjdk"
          apiURL=$(eval echo ${apiUrlTemplate})
          echo "Attempting to download GA release of boot JDK version ${JDK_BOOT_VERSION} from ${apiURL}"
          wget -q "${apiURL}" -O openjdk.zip
        fi
      fi
      unzip -q openjdk.zip
      mv "$(ls -d jdk-"${JDK_BOOT_VERSION}"*)" "$bootDir"
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
"$JDK_BOOT_DIR/bin/java" -version 2>&1 | sed 's/^/BOOT JDK: /'

if [ "${ARCHITECTURE}" == "x86-32" ]
then
  export CONFIGURE_ARGS_FOR_ANY_PLATFORM="${CONFIGURE_ARGS_FOR_ANY_PLATFORM} --disable-ccache --with-target-bits=32 --target=x86"

  if [ "${VARIANT}" == "${BUILD_VARIANT_OPENJ9}" ]
  then
    export CONFIGURE_ARGS_FOR_ANY_PLATFORM="${CONFIGURE_ARGS_FOR_ANY_PLATFORM} --with-openssl=/cygdrive/c/openjdk/OpenSSL-${OPENSSL_VERSION}-x86_32-VS2013 --enable-openssl-bundling"
    if [ "${JAVA_TO_BUILD}" == "${JDK8_VERSION}" ]
    then
      export BUILD_ARGS="${BUILD_ARGS} --freetype-version 2.5.3"
      export CONFIGURE_ARGS_FOR_ANY_PLATFORM="${CONFIGURE_ARGS_FOR_ANY_PLATFORM} --with-freemarker-jar=/cygdrive/c/openjdk/freemarker.jar"
      # https://github.com/adoptium/temurin-build/issues/243
      export INCLUDE="C:\Program Files\Debugging Tools for Windows (x64)\sdk\inc;$INCLUDE"
      export PATH="/c/cygwin64/bin:/usr/bin:$PATH"
      TOOLCHAIN_VERSION="2013"
    elif [ "${JAVA_TO_BUILD}" == "${JDK11_VERSION}" ]
    then
      export CONFIGURE_ARGS_FOR_ANY_PLATFORM="${CONFIGURE_ARGS_FOR_ANY_PLATFORM} --with-freemarker-jar=/cygdrive/c/openjdk/freemarker.jar"

      # Next line a potentially tactical fix for https://github.com/adoptium/temurin-build/issues/267
      export PATH="/usr/bin:$PATH"
    fi
    # LLVM needs to be before cygwin as at least one machine has 64-bit clang in cygwin #813
    # NASM required for OpenSSL support as per #604
    export PATH="/cygdrive/c/Program Files (x86)/LLVM/bin:/cygdrive/c/openjdk/nasm-$OPENJ9_NASM_VERSION:$PATH"
  else
    if [ "${JAVA_TO_BUILD}" == "${JDK8_VERSION}" ]
    then
      TOOLCHAIN_VERSION="2013"
      export BUILD_ARGS="${BUILD_ARGS} --freetype-version 2.5.3"
      export PATH="/cygdrive/c/openjdk/make-3.82/:$PATH"
    elif [ "${JAVA_TO_BUILD}" == "${JDK11_VERSION}" ]
    then
      TOOLCHAIN_VERSION="2017"
      export CONFIGURE_ARGS_FOR_ANY_PLATFORM="${CONFIGURE_ARGS_FOR_ANY_PLATFORM} --disable-ccache"
    elif [ "$JAVA_FEATURE_VERSION" -gt 11 ]
    then
      TOOLCHAIN_VERSION="2019"
      export CONFIGURE_ARGS_FOR_ANY_PLATFORM="${CONFIGURE_ARGS_FOR_ANY_PLATFORM} --disable-ccache"
    fi
  fi
fi

if [ "${ARCHITECTURE}" == "x64" ]
then
  if [ "${VARIANT}" == "${BUILD_VARIANT_OPENJ9}" ]
  then
    export HAS_AUTOCONF=1
    export BUILD_ARGS="${BUILD_ARGS} --freetype-version 2.5.3"

    if [ "${JAVA_TO_BUILD}" == "${JDK8_VERSION}" ]
    then
      export BUILD_ARGS="${BUILD_ARGS} --freetype-version 2.5.3"
      export INCLUDE="C:\Program Files\Debugging Tools for Windows (x64)\sdk\inc;$INCLUDE"
      export PATH="$PATH:/c/cygwin64/bin"
      export CONFIGURE_ARGS_FOR_ANY_PLATFORM="${CONFIGURE_ARGS_FOR_ANY_PLATFORM} --with-freemarker-jar=/cygdrive/c/openjdk/freemarker.jar --disable-ccache"
      export CONFIGURE_ARGS_FOR_ANY_PLATFORM="${CONFIGURE_ARGS_FOR_ANY_PLATFORM} --with-openssl=/cygdrive/c/openjdk/OpenSSL-${OPENSSL_VERSION}-x86_64-VS2013 --enable-openssl-bundling"
      TOOLCHAIN_VERSION="2013"
    elif [ "${JAVA_TO_BUILD}" == "${JDK9_VERSION}" ]
    then
      TOOLCHAIN_VERSION="2013"
      export BUILD_ARGS="${BUILD_ARGS} --freetype-version 2.5.3"
      export CONFIGURE_ARGS_FOR_ANY_PLATFORM="${CONFIGURE_ARGS_FOR_ANY_PLATFORM} --with-freemarker-jar=/cygdrive/c/openjdk/freemarker.jar"
    elif [ "${JAVA_TO_BUILD}" == "${JDK10_VERSION}" ]
    then
      export BUILD_ARGS="${BUILD_ARGS} --freetype-version 2.5.3"
      export CONFIGURE_ARGS_FOR_ANY_PLATFORM="${CONFIGURE_ARGS_FOR_ANY_PLATFORM} --with-freemarker-jar=/cygdrive/c/openjdk/freemarker.jar"
    elif [ "${JAVA_TO_BUILD}" == "${JDK11_VERSION}" ]
    then
      TOOLCHAIN_VERSION="2017"
      export CONFIGURE_ARGS_FOR_ANY_PLATFORM="${CONFIGURE_ARGS_FOR_ANY_PLATFORM} --with-freemarker-jar=/cygdrive/c/openjdk/freemarker.jar --with-openssl=/cygdrive/c/openjdk/OpenSSL-${OPENSSL_VERSION}-x86_64-VS2017 --enable-openssl-bundling"
    elif [ "$JAVA_FEATURE_VERSION" -gt 11 ]
    then
      TOOLCHAIN_VERSION="2019"
      export CONFIGURE_ARGS_FOR_ANY_PLATFORM="${CONFIGURE_ARGS_FOR_ANY_PLATFORM} --with-freemarker-jar=/cygdrive/c/openjdk/freemarker.jar --with-openssl=/cygdrive/c/openjdk/OpenSSL-${OPENSSL_VERSION}-x86_64-VS2019 --enable-openssl-bundling"
    fi

    CUDA_VERSION=9.0
    CUDA_HOME_FULL="C:/Program Files/NVIDIA GPU Computing Toolkit/CUDA/v$CUDA_VERSION"
    # use cygpath to map to 'short' names (without spaces)
    CUDA_HOME=$(cygpath -ms "$CUDA_HOME_FULL")
    if [[ $CUDA_HOME == *" "* ]]; then
      echo "[ERROR] All CUDA_HOME path folders must have either (a) no spaces, or (b) a shortened version configured in the environment."
      echo "CUDA_HOME unshortened: ${CUDA_HOME_FULL}"
      echo "CUDA_HOME shortened: ${CUDA_HOME}"
      exit 1
    fi
    if [ -f "$(cygpath -u "$CUDA_HOME"/include/cuda.h)" ]
    then
      export CONFIGURE_ARGS_FOR_ANY_PLATFORM="${CONFIGURE_ARGS_FOR_ANY_PLATFORM} --enable-cuda --with-cuda=$CUDA_HOME"
    else
      echo "[ERROR] The following file could not be found: $CUDA_HOME/include/cuda.h"
      echo "Please check that CUDA is correctly installed."
      exit 1
    fi

    # LLVM needs to be before cygwin as at least one machine has clang in cygwin #813
    # NASM required for OpenSSL support as per #604
    export PATH="/cygdrive/c/Program Files/LLVM/bin:/usr/bin:/cygdrive/c/openjdk/nasm-$OPENJ9_NASM_VERSION:$PATH"
  else
    TOOLCHAIN_VERSION="2013"
    if [ "${JAVA_TO_BUILD}" == "${JDK8_VERSION}" ]
    then
      export BUILD_ARGS="${BUILD_ARGS} --freetype-version 2.5.3"
      export PATH="/cygdrive/c/openjdk/make-3.82/:$PATH"
      export CONFIGURE_ARGS_FOR_ANY_PLATFORM="${CONFIGURE_ARGS_FOR_ANY_PLATFORM} --disable-ccache"
    elif [ "${JAVA_TO_BUILD}" == "${JDK9_VERSION}" ]
    then
      export BUILD_ARGS="${BUILD_ARGS} --freetype-version 2.5.3"
      export CONFIGURE_ARGS_FOR_ANY_PLATFORM="${CONFIGURE_ARGS_FOR_ANY_PLATFORM} --disable-ccache"
    elif [ "${JAVA_TO_BUILD}" == "${JDK10_VERSION}" ]
    then
      export BUILD_ARGS="${BUILD_ARGS} --freetype-version 2.5.3"
      export CONFIGURE_ARGS_FOR_ANY_PLATFORM="${CONFIGURE_ARGS_FOR_ANY_PLATFORM} --disable-ccache"
    elif [ "${JAVA_TO_BUILD}" == "${JDK11_VERSION}" ]
    then
      TOOLCHAIN_VERSION="2017"
      export CONFIGURE_ARGS_FOR_ANY_PLATFORM="${CONFIGURE_ARGS_FOR_ANY_PLATFORM} --disable-ccache"
    elif [ "$JAVA_FEATURE_VERSION" -gt 11 ]
    then
      TOOLCHAIN_VERSION="2019"
      export CONFIGURE_ARGS_FOR_ANY_PLATFORM="${CONFIGURE_ARGS_FOR_ANY_PLATFORM} --disable-ccache"
    fi
  fi

  if [ "${VARIANT}" == "${BUILD_VARIANT_DRAGONWELL}" ] && [ "${JAVA_TO_BUILD}" == "${JDK8_VERSION}" ]
  then
    if [[ -d "${DRAGONWELL8_BOOTSTRAP}" ]]; then
      export JDK_BOOT_DIR="${DRAGONWELL8_BOOTSTRAP}"
    fi
  fi
fi

if [ "${ARCHITECTURE}" == "aarch64" ]; then
  export CONFIGURE_ARGS_FOR_ANY_PLATFORM="${CONFIGURE_ARGS_FOR_ANY_PLATFORM} --disable-ccache --openjdk-target=aarch64-unknown-cygwin --with-build-jdk=$JDK_BOOT_DIR"
fi


if [ -n "${TOOLCHAIN_VERSION}" ]; then
    export CONFIGURE_ARGS_FOR_ANY_PLATFORM="${CONFIGURE_ARGS_FOR_ANY_PLATFORM} --with-toolchain-version=${TOOLCHAIN_VERSION}"
fi
