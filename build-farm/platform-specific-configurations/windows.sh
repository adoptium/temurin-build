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

export ANT_HOME=/cygdrive/C/Projects/OpenJDK/apache-ant-1.10.1
export ALLOW_DOWNLOADS=true
export LANG=C
export JAVA_HOME=$JDK_BOOT_DIR
export BUILD_ARGS="--tmp-space-build ${BUILD_ARGS}"
export OPENJ9_NASM_VERSION=2.13.03

TOOLCHAIN_VERSION=""

# Any version above 8
if [ "$JAVA_FEATURE_VERSION" -gt 8 ]; then
    BOOT_JDK_VERSION="$((JAVA_FEATURE_VERSION-1))"
    BOOT_JDK_VARIABLE="JDK$(echo $BOOT_JDK_VERSION)_BOOT_DIR"
    if [ ! -d "$(eval echo "\$$BOOT_JDK_VARIABLE")" ]; then
      export $BOOT_JDK_VARIABLE="$PWD/jdk-$BOOT_JDK_VERSION"
      if [ ! -d "$(eval echo "\$$BOOT_JDK_VARIABLE/bin")" ]; then
        wget -q "https://api.adoptopenjdk.net/v2/binary/releases/openjdk${BOOT_JDK_VERSION}?os=windows&release=latest&arch=x64&heap_size=normal&type=jdk&openjdk_impl=hotspot" -O openjdk.zip
        unzip -q openjdk.zip
        mv $(ls -d jdk-$BOOT_JDK_VERSION*) jdk-$BOOT_JDK_VERSION
      fi
    fi
    export JDK_BOOT_DIR="$(eval echo "\$$BOOT_JDK_VARIABLE")"
fi

if [ "${ARCHITECTURE}" == "x86-32" ]
then
  export CONFIGURE_ARGS_FOR_ANY_PLATFORM="${CONFIGURE_ARGS_FOR_ANY_PLATFORM} --disable-ccache --with-target-bits=32 --target=x86"

  if [ "${VARIANT}" == "${BUILD_VARIANT_OPENJ9}" ]
  then
    export CONFIGURE_ARGS_FOR_ANY_PLATFORM="${CONFIGURE_ARGS_FOR_ANY_PLATFORM} --with-openssl=/cygdrive/c/openjdk/OpenSSL-1.1.1d-x86_32 --enable-openssl-bundling"
    if [ "${JAVA_TO_BUILD}" == "${JDK8_VERSION}" ]
    then
      export BUILD_ARGS="${BUILD_ARGS} --freetype-version 2.5.3"
      export CONFIGURE_ARGS_FOR_ANY_PLATFORM="${CONFIGURE_ARGS_FOR_ANY_PLATFORM} --with-freemarker-jar=/cygdrive/c/openjdk/freemarker.jar"
      # https://github.com/AdoptOpenJDK/openjdk-build/issues/243
      export INCLUDE="C:\Program Files\Debugging Tools for Windows (x64)\sdk\inc;$INCLUDE"
      export PATH="/c/cygwin64/bin:/usr/bin:$PATH"
    elif [ "${JAVA_TO_BUILD}" == "${JDK11_VERSION}" ]
    then
      export CONFIGURE_ARGS_FOR_ANY_PLATFORM="${CONFIGURE_ARGS_FOR_ANY_PLATFORM} --with-freemarker-jar=/cygdrive/c/openjdk/freemarker.jar"

      # Next line a potentially tactical fix for https://github.com/AdoptOpenJDK/openjdk-build/issues/267
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
      TOOLCHAIN_VERSION="2013"
      export CONFIGURE_ARGS_FOR_ANY_PLATFORM="${CONFIGURE_ARGS_FOR_ANY_PLATFORM} --disable-ccache"
    elif [ "$JAVA_FEATURE_VERSION" -gt 11 ]
    then
      TOOLCHAIN_VERSION="2017"
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
      export CONFIGURE_ARGS_FOR_ANY_PLATFORM="${CONFIGURE_ARGS_FOR_ANY_PLATFORM} --with-freemarker-jar=/cygdrive/c/openjdk/freemarker.jar --disable-ccache  --with-openssl=/cygdrive/c/openjdk/OpenSSL-1.1.1d-x86_64 --enable-openssl-bundling"
    elif [ "${JAVA_TO_BUILD}" == "${JDK9_VERSION}" ]
    then
      TOOLCHAIN_VERSION="2013"
      export BUILD_ARGS="${BUILD_ARGS} --freetype-version 2.5.3"
      export CONFIGURE_ARGS_FOR_ANY_PLATFORM="${CONFIGURE_ARGS_FOR_ANY_PLATFORM} --with-freemarker-jar=/cygdrive/c/openjdk/freemarker.jar"
    elif [ "${JAVA_TO_BUILD}" == "${JDK10_VERSION}" ]
    then
      export BUILD_ARGS="${BUILD_ARGS} --freetype-version 2.5.3"
      export CONFIGURE_ARGS_FOR_ANY_PLATFORM="${CONFIGURE_ARGS_FOR_ANY_PLATFORM} --with-freemarker-jar=/cygdrive/c/openjdk/freemarker.jar"
    elif [ "$JAVA_FEATURE_VERSION" -ge 11 ]
    then
      TOOLCHAIN_VERSION="2017"
      export CONFIGURE_ARGS_FOR_ANY_PLATFORM="${CONFIGURE_ARGS_FOR_ANY_PLATFORM} --with-freemarker-jar=/cygdrive/c/openjdk/freemarker.jar --with-openssl=/cygdrive/c/openjdk/OpenSSL-1.1.1d-x86_64 --enable-openssl-bundling"
    fi

    CUDA_VERSION=9.0
    CUDA_HOME="C:/Program Files/NVIDIA GPU Computing Toolkit/CUDA/v$CUDA_VERSION"
    # use cygpath to map to 'short' names (without spaces)
    CUDA_HOME=$(cygpath -ms "$CUDA_HOME")
    if [ -f "$(cygpath -u $CUDA_HOME/include/cuda.h)" ]
    then
      export CONFIGURE_ARGS_FOR_ANY_PLATFORM="${CONFIGURE_ARGS_FOR_ANY_PLATFORM} --enable-cuda --with-cuda=$CUDA_HOME"
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
    elif [ "$JAVA_FEATURE_VERSION" -ge 11 ]
    then
      TOOLCHAIN_VERSION="2017"
      export CONFIGURE_ARGS_FOR_ANY_PLATFORM="${CONFIGURE_ARGS_FOR_ANY_PLATFORM} --disable-ccache"
    fi
  fi
fi

if [ ! -z "${TOOLCHAIN_VERSION}" ]; then
    export CONFIGURE_ARGS_FOR_ANY_PLATFORM="${CONFIGURE_ARGS_FOR_ANY_PLATFORM} --with-toolchain-version=${TOOLCHAIN_VERSION}"
fi
