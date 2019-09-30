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
  if grep 'release 6' /etc/redhat-release >/dev/null; then
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
  export CONFIGURE_ARGS_FOR_ANY_PLATFORM="--with-jobs=4 --with-memory-size=2000"
  if [ "$JAVA_FEATURE_VERSION" -ge 11 ]; then
    export CONFIGURE_ARGS_FOR_ANY_PLATFORM="$CONFIGURE_ARGS_FOR_ANY_PLATFORM --disable-warnings-as-errors"
  fi
  if [ ! -z "${NUM_PROCESSORS}" ]
  then
    export BUILD_ARGS="${BUILD_ARGS} --processors $NUM_PROCESSORS"
  fi
fi

# Any version above 8
if [ "$JAVA_FEATURE_VERSION" -gt 8 ]; then
    BOOT_JDK_VERSION="$((JAVA_FEATURE_VERSION-1))"
    BOOT_JDK_VARIABLE="JDK$(echo $BOOT_JDK_VERSION)_BOOT_DIR"
    if [ ! -d "$(eval echo "\$$BOOT_JDK_VARIABLE")" ]; then
      export $BOOT_JDK_VARIABLE="$PWD/jdk-$BOOT_JDK_VERSION"
      if [ ! -d "$(eval echo "\$$BOOT_JDK_VARIABLE/bin")" ]; then
        mkdir -p "$(eval echo "\$$BOOT_JDK_VARIABLE")"
        wget -q -O - "https://api.adoptopenjdk.net/v2/binary/releases/openjdk${BOOT_JDK_VERSION}?os=linux&release=latest&arch=${ARCHITECTURE}&heap_size=normal&type=jdk&openjdk_impl=hotspot" | tar xpzf - --strip-components=1 -C "$(eval echo "\$$BOOT_JDK_VARIABLE")"
      fi
    fi
    export JDK_BOOT_DIR="$(eval echo "\$$BOOT_JDK_VARIABLE")"
fi

# Any version above 10
if [ "$JAVA_FEATURE_VERSION" -gt 10 ] || [ "${VARIANT}" == "${BUILD_VARIANT_OPENJ9}" ]; then
    # If we have the RedHat devtoolset 7 installed, use gcc 7 from there, else /usr/local/gcc/bin
    if [ -r /opt/rh/devtoolset-7/root/usr/bin ]; then
      export PATH=/opt/rh/devtoolset-7/root/usr/bin:$PATH
      [ -r /opt/rh/devtoolset-7/root/usr/bin/gcc ] && export CC=/opt/rh/devtoolset-7/root/usr/bin/gcc
      [ -r /opt/rh/devtoolset-7/root/usr/bin/g++ ] && export CXX=/opt/rh/devtoolset-7/root/usr/bin/g++
    elif [ -r /usr/local/gcc/bin/gcc-7.3 ]; then
      export PATH=/usr/local/gcc/bin:$PATH
      [ -r /usr/local/gcc/bin/gcc-7.3 ] && export CC=/usr/local/gcc/bin/gcc-7.3
      [ -r /usr/local/gcc/bin/g++-7.3 ] && export CXX=/usr/local/gcc/bin/g++-7.3
      export LD_LIBRARY_PATH=/usr/local/gcc/lib64:/usr/local/gcc/lib
    elif [ -r /usr/local/gcc/bin/gcc-7.4 ]; then
      export PATH=/usr/local/gcc/bin:$PATH
      [ -r /usr/local/gcc/bin/gcc-7.4 ] && export CC=/usr/local/gcc/bin/gcc-7.4
      [ -r /usr/local/gcc/bin/g++-7.4 ] && export CXX=/usr/local/gcc/bin/g++-7.4
      export LD_LIBRARY_PATH=/usr/local/gcc/lib64:/usr/local/gcc/lib
    fi
fi

if [ "${ARCHITECTURE}" == "aarch64" ] && [ "${JAVA_TO_BUILD}" == "${JDK8_VERSION}" ]
then
  export BUILD_ARGS="${BUILD_ARGS} -r https://github.com/AdoptOpenJDK/openjdk-aarch64-jdk8u"
fi

if [ "${VARIANT}" == "${BUILD_VARIANT_HOTSPOT_JFR}" ] && [ "${JAVA_TO_BUILD}" == "${JDK8_VERSION}" ]
then
  export BUILD_ARGS="${BUILD_ARGS} -r https://github.com/AdoptOpenJDK/openjdk-jdk8u-jfr-incubator"
  export BOOT_JDK_VERSION="8"
  export BOOT_JDK_VARIABLE="JDK$(echo $BOOT_JDK_VERSION)_BOOT_DIR"
  export JDK_BOOT_DIR="$(eval echo "\$$BOOT_JDK_VARIABLE")"
fi
