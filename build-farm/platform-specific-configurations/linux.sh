#!/bin/bash

################################################################################
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
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

  if [ "${VARIANT}" == "openj9" ]
  then
    export PATH="/usr/bin:$PATH"

    if [ "${JAVA_TO_BUILD}" == "${JDK8_VERSION}" ] || [ "${JAVA_TO_BUILD}" == "${JDK9_VERSION}" ] || [ "${JAVA_TO_BUILD}" == "${JDK10_VERSION}" ]
    then
      if which g++-4.8; then
        export CC=gcc-4.8
        export CXX=g++-4.8
      fi
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
fi

# Skip Building Freetype for certain platforms
if [ "${ARCHITECTURE}" == "aarch64" ] || [ "${ARCHITECTURE}" == "ppc64le" ]
then
  export BUILD_ARGS="${BUILD_ARGS} --skip-freetype"
fi

if [ "${ARCHITECTURE}" == "s390x" ] || [ "${ARCHITECTURE}" == "ppc64le" ]
then
    if [ "${JAVA_TO_BUILD}" == "${JDK10_VERSION}" ] && [ "${VARIANT}" == "openj9" ]
    then
      if [ -z "$JDK9_BOOT_DIR" ]; then
        export JDK9_BOOT_DIR="$PWD/jdk-9+181"
        if [ ! -r "$JDK9_BOOT_DIR" ]; then
          wget -O -  https://github.com/AdoptOpenJDK/openjdk9-releases/releases/download/jdk-9%2B181/OpenJDK9_s390x_Linux_jdk-9.181.tar.gz | tar xpfz -
        fi
      fi

      export JDK_BOOT_DIR=$JDK9_BOOT_DIR
    fi
fi

if [ "${JAVA_TO_BUILD}" == "${JDK11_VERSION}" ] || [ "${JAVA_TO_BUILD}" == "${JDKHEAD_VERSION}" ]
then
    export JDK10_BOOT_DIR="$PWD/jdk-10"
    if [ ! -d "$JDK10_BOOT_DIR/bin" ]; then
      downloadArch="${ARCHITECTURE}"
      [ "$downloadArch" == "arm" ] && downloadArch="arm32"

      mkdir -p "$JDK10_BOOT_DIR"
      wget -q -O - "https://api.adoptopenjdk.net/v2/binary/releases/openjdk10?os=linux&release=latest&arch=${downloadArch}" | tar xpzf - --strip-components=2 -C "$JDK10_BOOT_DIR"
    fi
    export JDK_BOOT_DIR=$JDK10_BOOT_DIR
fi
if [ "${JAVA_TO_BUILD}" == "${JDK11_VERSION}" ] || [ "${JAVA_TO_BUILD}" == "${JDKHEAD_VERSION}" ] || [ "${VARIANT}" == "openj9" ]
    # If we have the RedHat devtoolset 7 installed, use gcc 7 from there, else /usr/local/gcc/bin
    if [ -r /opt/rh/devtoolset-7/root/usr/bin ]; then
      export PATH=/opt/rh/devtoolset-7/root/usr/bin:$PATH
      [ -r /opt/rh/devtoolset-7/root/usr/bin/gcc ] && export CC=/opt/rh/devtoolset-7/root/usr/bin/gcc
      [ -r /opt/rh/devtoolset-7/root/usr/bin/g++ ] && export CC=/opt/rh/devtoolset-7/root/usr/bin/g++
    elif [ -r /usr/local/gcc/bin ]; then
      export PATH=/usr/local/gcc/bin:$PATH
      [ -r /usr/local/gcc/bin/gcc-7.3 ] && export CC=/usr/local/gcc/bin/gcc-7.3
      [ -r /usr/local/gcc/bin/g++-7.3 ] && export CXX=/usr/local/gcc/bin/g++-7.3
      export LD_LIBRARY_PATH=/usr/local/gcc/lib64:/usr/local/gcc/lib
    fi
fi
