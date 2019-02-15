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

if [ "${ARCHITECTURE}" == "x86-32" ]
then
  export CONFIGURE_ARGS_FOR_ANY_PLATFORM="${CONFIGURE_ARGS_FOR_ANY_PLATFORM} --disable-ccache --with-target-bits=32 --target=x86"

  if [ "${VARIANT}" == "${BUILD_VARIANT_OPENJ9}" ]
  then
    export CONFIGURE_ARGS_FOR_ANY_PLATFORM="${CONFIGURE_ARGS_FOR_ANY_PLATFORM} --with-openssl=/cygdrive/c/progra~2/OpenSSL --enable-openssl-bundling"
    if [ "${JAVA_TO_BUILD}" == "${JDK8_VERSION}" ]
    then
      export CONFIGURE_ARGS_FOR_ANY_PLATFORM="${CONFIGURE_ARGS_FOR_ANY_PLATFORM}  --with-freetype-include=/cygdrive/c/openjdk/freetype-2.5.3/include --with-freetype-lib=/cygdrive/c/openjdk/freetype-2.5.3/lib --with-freemarker-jar=/cygdrive/c/openjdk/freemarker.jar"
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
      export PATH="/cygdrive/c/Program Files (x86)/Microsoft Visual Studio 10.0/VC/bin/amd64/:/cygdrive/C/Projects/OpenJDK/make-3.82/:$PATH"
      TOOLCHAIN_VERSION="2010"
      export CONFIGURE_ARGS_FOR_ANY_PLATFORM="${CONFIGURE_ARGS_FOR_ANY_PLATFORM} --with-freetype-include=/cygdrive/c/openjdk/freetype/include --with-freetype-lib=/cygdrive/c/openjdk/freetype/lib32"
    elif [ "${JAVA_TO_BUILD}" == "${JDK11_VERSION}" ]
    then
      export PATH="/usr/bin:/cygdrive/c/Program Files (x86)/Microsoft Visual Studio 10.0/VC/bin/amd64/:$PATH"
      # Unset the host VS120COMNTOOLS and VS110COMNTOOLS variables as Java picks them up by default and we don't want that.
      unset VS120COMNTOOLS
      unset VS110COMNTOOLS
      TOOLCHAIN_VERSION="2013"
      export CONFIGURE_ARGS_FOR_ANY_PLATFORM="${CONFIGURE_ARGS_FOR_ANY_PLATFORM} --disable-warnings-as-errors"
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
      export INCLUDE="C:\Program Files\Debugging Tools for Windows (x64)\sdk\inc;$INCLUDE"
      export PATH="$PATH:/c/cygwin64/bin"
      export CONFIGURE_ARGS_FOR_ANY_PLATFORM="${CONFIGURE_ARGS_FOR_ANY_PLATFORM} --with-freetype-include=/cygdrive/c/openjdk/freetype-2.5.3/include --with-freetype-lib=/cygdrive/c/openjdk/freetype-2.5.3/lib64 --with-freemarker-jar=/cygdrive/c/openjdk/freemarker.jar --disable-ccache  --with-openssl=/cygdrive/c/progra~1/OpenSSL --enable-openssl-bundling"
    elif [ "${JAVA_TO_BUILD}" == "${JDK9_VERSION}" ]
    then
      TOOLCHAIN_VERSION="2013"
      export CONFIGURE_ARGS_FOR_ANY_PLATFORM="${CONFIGURE_ARGS_FOR_ANY_PLATFORM} --with-freetype-src=/cygdrive/c/openjdk/freetype-2.5.3 --with-freemarker-jar=/cygdrive/c/openjdk/freemarker.jar"
    elif [ "${JAVA_TO_BUILD}" == "${JDK10_VERSION}" ]
    then
      export CONFIGURE_ARGS_FOR_ANY_PLATFORM="${CONFIGURE_ARGS_FOR_ANY_PLATFORM} --with-freetype-src=/cygdrive/c/openjdk/freetype-2.5.3 --with-freemarker-jar=/cygdrive/c/openjdk/freemarker.jar"
    elif [ "${JAVA_TO_BUILD}" == "${JDK11_VERSION}" ] || [ "${JAVA_TO_BUILD}" == "${JDKHEAD_VERSION}" ]
    then
      TOOLCHAIN_VERSION="2017"
      export CONFIGURE_ARGS_FOR_ANY_PLATFORM="${CONFIGURE_ARGS_FOR_ANY_PLATFORM} --with-freemarker-jar=/cygdrive/c/openjdk/freemarker.jar --with-openssl=/cygdrive/c/progra~1/OpenSSL --enable-openssl-bundling"
    fi
    # LLVM needs to be before cygwin as at least one machine has clang in cygwin #813
    # NASM required for OpenSSL support as per #604
    export PATH="/cygdrive/c/Program Files/LLVM/bin:/usr/bin:/cygdrive/c/openjdk/nasm-$OPENJ9_NASM_VERSION:$PATH"
  else
    TOOLCHAIN_VERSION="2013"
    # Unset the host VS120COMNTOOLS and VS110COMNTOOLS variables as Java picks them up by default and we don't want that.
    unset VS120COMNTOOLS
    unset VS110COMNTOOLS
    if [ "${JAVA_TO_BUILD}" == "${JDK8_VERSION}" ]
    then
      export PATH="/cygdrive/c/Program Files (x86)/Microsoft Visual Studio 10.0/VC/bin/amd64/:/cygdrive/c/openjdk/make-3.82/:$PATH"
      export CONFIGURE_ARGS_FOR_ANY_PLATFORM="${CONFIGURE_ARGS_FOR_ANY_PLATFORM} --with-freetype-include=/cygdrive/c/openjdk/freetype/include --with-freetype-lib=/cygdrive/c/openjdk/freetype/lib64 --disable-ccache"
    elif [ "${JAVA_TO_BUILD}" == "${JDK9_VERSION}" ]
    then
      export PATH="/usr/bin:/cygdrive/c/Program Files (x86)/Microsoft Visual Studio 10.0/VC/bin/amd64/:$PATH"
      export CONFIGURE_ARGS_FOR_ANY_PLATFORM="${CONFIGURE_ARGS_FOR_ANY_PLATFORM} --with-freetype=/cygdrive/C/openjdk/freetype --disable-ccache"
    elif [ "${JAVA_TO_BUILD}" == "${JDK10_VERSION}" ]
    then
      export PATH="/usr/bin:/cygdrive/c/Program Files (x86)/Microsoft Visual Studio 10.0/VC/bin/amd64/:$PATH"
      export CONFIGURE_ARGS_FOR_ANY_PLATFORM="${CONFIGURE_ARGS_FOR_ANY_PLATFORM} --with-freetype-src=/cygdrive/c/openjdk/freetype-2.5.3 --disable-ccache"
    elif [ "${JAVA_TO_BUILD}" == "${JDK11_VERSION}" ] || [ "${JAVA_TO_BUILD}" == "${JDKHEAD_VERSION}" ]
    then
      export PATH="/usr/bin:/cygdrive/c/Program Files (x86)/Microsoft Visual Studio 10.0/VC/bin/amd64/:$PATH"
      export CONFIGURE_ARGS_FOR_ANY_PLATFORM="${CONFIGURE_ARGS_FOR_ANY_PLATFORM} --disable-ccache"
    fi
  fi
fi

if [ ! -z "${TOOLCHAIN_VERSION}" ]; then
  HOTSPOT_BUILD="false";
  if [ "${VARIANT}" != "${BUILD_VARIANT_HOTSPOT}" ] && [ "${VARIANT}" != "${BUILD_VARIANT_CORRETTO}" ]; then
    HOTSPOT_BUILD="true";
  fi

  # At time of writing java 8, hotspot tags cannot handle --with-toolchain-version
  if [ "${JAVA_TO_BUILD}" != "${JDK8_VERSION}" ] || [ "${HOTSPOT_BUILD}" != "true" ] || [ -z "${TAG}" ]
  then
    export CONFIGURE_ARGS_FOR_ANY_PLATFORM="${CONFIGURE_ARGS_FOR_ANY_PLATFORM} --with-toolchain-version=${TOOLCHAIN_VERSION}"
  fi
fi
