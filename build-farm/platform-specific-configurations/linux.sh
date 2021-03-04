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

# Bundling our own freetype can cause problems, so we skip that on linux.
export BUILD_ARGS="${BUILD_ARGS} --skip-freetype"

if [ "${ARCHITECTURE}" == "x64" ]
then
  export PATH=/opt/rh/devtoolset-2/root/usr/bin:$PATH
fi

if [ "${ARCHITECTURE}" == "s390x" ]
then
  export LANG=C

  if [ "${VARIANT}" == "${BUILD_VARIANT_OPENJ9}" ]
  then
    # Any version below 11
    if [ "$JAVA_FEATURE_VERSION" -lt 11 ]
    then
      if which g++-4.8; then
        export CC=gcc-4.8
        export CXX=g++-4.8
      fi
    fi
  fi
fi

if [ "${VARIANT}" == "${BUILD_VARIANT_OPENJ9}" ]
then
  # CentOS 6 has openssl 1.0.1 so we use a self-installed 1.0.2 from the playbooks
  if grep 'release 6' /etc/redhat-release >/dev/null 2>&1 || grep 'jessie' /etc/os-release >/dev/null 2>&1 || grep 'SUSE' /etc/os-release >/dev/null 2>&1; then
    if [ -r /usr/local/openssl-1.0.2/include/openssl/opensslconf.h ]; then
      export CONFIGURE_ARGS_FOR_ANY_PLATFORM="${CONFIGURE_ARGS_FOR_ANY_PLATFORM} --with-openssl=/usr/local/openssl-1.0.2"
    else
      export CONFIGURE_ARGS_FOR_ANY_PLATFORM="${CONFIGURE_ARGS_FOR_ANY_PLATFORM} --with-openssl=fetched"
    fi
  else
    export CONFIGURE_ARGS_FOR_ANY_PLATFORM="${CONFIGURE_ARGS_FOR_ANY_PLATFORM} --with-openssl=system"
  fi
fi

if [ "${VARIANT}" == "${BUILD_VARIANT_OPENJ9}" ]
then
  if [ "${ARCHITECTURE}" == "ppc64le" ] || [ "${ARCHITECTURE}" == "x64" ]
  then
    CUDA_VERSION=9.0
    CUDA_HOME=/usr/local/cuda-$CUDA_VERSION
    if [ -f $CUDA_HOME/include/cuda.h ]
    then
      export CONFIGURE_ARGS_FOR_ANY_PLATFORM="${CONFIGURE_ARGS_FOR_ANY_PLATFORM} --enable-cuda --with-cuda=$CUDA_HOME"
    fi
  fi
fi

if [ "${ARCHITECTURE}" == "ppc64le" ]
then
  export LANG=C
fi

if [ "${ARCHITECTURE}" == "arm" ]
then
  export CONFIGURE_ARGS_FOR_ANY_PLATFORM="${CONFIGURE_ARGS_FOR_ANY_PLATFORM} --with-jobs=4 --with-memory-size=2000"
  if [ "$JAVA_FEATURE_VERSION" -eq 8 ]; then
    export CONFIGURE_ARGS_FOR_ANY_PLATFORM="${CONFIGURE_ARGS_FOR_ANY_PLATFORM} --with-extra-ldflags=-latomic"
  fi
  if [ "$JAVA_FEATURE_VERSION" -ge 11 ]; then
    export CONFIGURE_ARGS_FOR_ANY_PLATFORM="${CONFIGURE_ARGS_FOR_ANY_PLATFORM} --disable-warnings-as-errors"
  fi
  if [ ! -z "${NUM_PROCESSORS}" ]
  then
    export BUILD_ARGS="${BUILD_ARGS} --processors $NUM_PROCESSORS"
  fi
fi

BOOT_JDK_VERSION="$((JAVA_FEATURE_VERSION-1))"
BOOT_JDK_VARIABLE="JDK$(echo $BOOT_JDK_VERSION)_BOOT_DIR"
if [ ! -d "$(eval echo "\$$BOOT_JDK_VARIABLE")" ]; then
  bootDir="$PWD/jdk-$BOOT_JDK_VERSION"
  # Note we export $BOOT_JDK_VARIABLE (i.e. JDKXX_BOOT_DIR) here
  # instead of BOOT_JDK_VARIABLE (no '$').
  export ${BOOT_JDK_VARIABLE}="$bootDir"
  if [ ! -x "$bootDir/bin/javac" ]; then
    # Set to a default location as linked in the ansible playbooks
    if [ -x /usr/lib/jvm/jdk-${BOOT_JDK_VERSION}/bin/javac ]; then
      echo Could not use ${BOOT_JDK_VARIABLE} - using /usr/lib/jvm/jdk-${BOOT_JDK_VERSION}
      export ${BOOT_JDK_VARIABLE}="/usr/lib/jvm/jdk-${BOOT_JDK_VERSION}"
    elif [ "$BOOT_JDK_VERSION" -ge 8 ]; then # Adopt has no build pre-8
      mkdir -p "$bootDir"
      releaseType="ga"
      apiUrlTemplate="https://api.adoptopenjdk.net/v3/binary/latest/\${BOOT_JDK_VERSION}/\${releaseType}/linux/\${ARCHITECTURE}/jdk/\${VARIANT}/normal/adoptopenjdk"
      apiURL=$(eval echo ${apiUrlTemplate})
      echo "Downloading GA release of boot JDK version ${BOOT_JDK_VERSION} from ${apiURL}"
      # make-adopt-build-farm.sh has 'set -e'. We need to disable that for
      # the fallback mechanism, as downloading of the GA binary might fail.
      set +e
      wget -q -O - "${apiURL}" | tar xpzf - --strip-components=1 -C "$bootDir"
      retVal=$?
      set -e
      if [ $retVal -ne 0 ]; then
        # We must be a JDK HEAD build for which no boot JDK exists other than
        # nightlies?
        echo "Downloading GA release of boot JDK version ${BOOT_JDK_VERSION} failed."
        # shellcheck disable=SC2034
        releaseType="ea"
        apiURL=$(eval echo ${apiUrlTemplate})
        echo "Attempting to download EA release of boot JDK version ${BOOT_JDK_VERSION} from ${apiURL}"
        wget -q -O - "${apiURL}" | tar xpzf - --strip-components=1 -C "$bootDir"
      fi
    fi
  fi
fi

export JDK_BOOT_DIR="$(eval echo "\$$BOOT_JDK_VARIABLE")"
"$JDK_BOOT_DIR/bin/java" -version 2>&1 | sed 's/^/BOOT JDK: /'
"$JDK_BOOT_DIR/bin/java" -version >/dev/null 2>&1
executedJavaVersion=$?
if [ $executedJavaVersion -ne 0 ]; then
    echo "Failed to obtain or find a valid boot jdk"
    exit 1
fi

if [ "${VARIANT}" == "${BUILD_VARIANT_DRAGONWELL}" ] && [ "$JAVA_FEATURE_VERSION" -eq 11 ] && [ -r /usr/local/gcc9/ ] && [ "${ARCHITECTURE}" == "aarch64" ]; then
  export PATH=/usr/local/gcc9/bin:$PATH
  export CC=/usr/local/gcc9/bin/gcc-9.3
  export CXX=/usr/local/gcc9/bin/g++-9.3
elif [ -r /usr/local/gcc/bin/gcc-7.5 ]; then
  export PATH=/usr/local/gcc/bin:$PATH
  [ -r /usr/local/gcc/bin/gcc-7.5 ] && export CC=/usr/local/gcc/bin/gcc-7.5
  [ -r /usr/local/gcc/bin/g++-7.5 ] && export CXX=/usr/local/gcc/bin/g++-7.5
  export LD_LIBRARY_PATH=/usr/local/gcc/lib64:/usr/local/gcc/lib
elif [ -r /usr/bin/gcc-7 ]; then
  [ -r /usr/bin/gcc-7 ] && export CC=/usr/bin/gcc-7
  [ -r /usr/bin/g++-7 ] && export CXX=/usr/bin/g++-7
fi

if which ccache 2> /dev/null; then
  export CONFIGURE_ARGS_FOR_ANY_PLATFORM="${CONFIGURE_ARGS_FOR_ANY_PLATFORM} --enable-ccache"
fi

# If we are in a cross compilation environment for RISC-V
if [ "${ARCHITECTURE}" == "riscv64" -a "`uname -m`" == "x86_64" ]; then
  if [ "${VARIANT}" == "${BUILD_VARIANT_OPENJ9}" ]; then
    echo RISCV cross-compilation ... Downloading latest nightly OpenJ9/x64 as build JDK
    export BUILDJDK=$WORKSPACE/buildjdk
    rm -rf "$BUILDJDK"
    mkdir "$BUILDJDK"
    wget -O - "https://api.adoptopenjdk.net/v3/binary/latest/${JAVA_FEATURE_VERSION}/ea/linux/x64/jdk/openj9/normal/adoptopenjdk" | tar xpzf - --strip-components=1 -C "$BUILDJDK"
    "$BUILDJDK/bin/java" -version 2>&1 | sed 's/^/CROSSBUILD JDK > /g'
  fi
  echo RISC-V cross-compilation ... 
  export RISCV64=/opt/riscv_toolchain_linux
  export LD_LIBRARY_PATH=$RISCV64/lib64
  export PATH="$RISCV64/bin:$PATH"
  # riscv has to use a cross compiler
  export CC=$RISCV64/bin/riscv64-unknown-linux-gnu-gcc
  export CXX=$RISCV64/bin/riscv64-unknown-linux-gnu-g++
  CONFIGURE_ARGS_FOR_ANY_PLATFORM="${CONFIGURE_ARGS_FOR_ANY_PLATFORM} --openjdk-target=riscv64-unknown-linux-gnu --with-sysroot=/opt/fedora28_riscv_root --with-boot-jdk=$JDK_BOOT_DIR"
  BUILD_ARGS="${BUILD_ARGS} -F"
  [ ! -x "$CXX" ] && echo "RISC-V cross compiler $CXX does not exist on this system - cannot continue" && exit 1
fi

