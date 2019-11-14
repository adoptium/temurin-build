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
export PATH="/opt/freeware/bin:/usr/local/bin:/opt/IBM/xlC/13.1.3/bin:/opt/IBM/xlc/13.1.3/bin:$PATH"
# Without this, java adds /usr/lib to the LIBPATH of anything it forks which breaks linkage
export LIBPATH="/opt/freeware/lib:$LIBPATH"
export CONFIGURE_ARGS_FOR_ANY_PLATFORM="${CONFIGURE_ARGS_FOR_ANY_PLATFORM} --with-memory-size=10000 --with-cups-include=/opt/freeware/include"

# Any version below 11
if  [ "$JAVA_FEATURE_VERSION" -lt 11 ]
then
  export CONFIGURE_ARGS_FOR_ANY_PLATFORM="${CONFIGURE_ARGS_FOR_ANY_PLATFORM} --with-extra-ldflags=-lpthread --with-extra-cflags=-lpthread --with-extra-cxxflags=-lpthread"
fi

export BUILD_ARGS="${BUILD_ARGS} --skip-freetype"

if [ "${VARIANT}" == "${BUILD_VARIANT_OPENJ9}" ]; then
  export LDR_CNTRL=MAXDATA=0x80000000
fi
echo LDR_CNTRL=$LDR_CNTRL

# Any version above 8
if [ "$JAVA_FEATURE_VERSION" -gt 8 ]; then
    BOOT_JDK_VERSION="$((JAVA_FEATURE_VERSION-1))"
    BOOT_JDK_VARIABLE="JDK$(echo $BOOT_JDK_VERSION)_BOOT_DIR"
    if [ ! -d "$(eval echo "\$$BOOT_JDK_VARIABLE")" ]; then
      export $BOOT_JDK_VARIABLE="$PWD/jdk-$BOOT_JDK_VERSION"
      if [ ! -d "$(eval echo "\$$BOOT_JDK_VARIABLE/bin")" ]; then
        bootDir="$(eval echo "\$$BOOT_JDK_VARIABLE")"
        mkdir -p "${bootDir}"
        wget -q -O - "https://api.adoptopenjdk.net/v2/binary/releases/openjdk${BOOT_JDK_VERSION}?os=aix&release=latest&arch=${ARCHITECTURE}&heap_size=normal&type=jdk&openjdk_impl=openj9" | tar xpzf - --strip-components=1 -C "${bootDir}"
      fi
    fi
    export JDK_BOOT_DIR="$(eval echo "\$$BOOT_JDK_VARIABLE")"
fi

if [ "$JAVA_FEATURE_VERSION" -ge 11 ];
then
  if [ "${VARIANT}" == "${BUILD_VARIANT_OPENJ9}" ]; then
    export CONFIGURE_ARGS_FOR_ANY_PLATFORM="${CONFIGURE_ARGS_FOR_ANY_PLATFORM} --disable-warnings-as-errors --with-openssl=fetched"
  else
    export CONFIGURE_ARGS_FOR_ANY_PLATFORM="${CONFIGURE_ARGS_FOR_ANY_PLATFORM} DF=/usr/sysv/bin/df"
  fi

  export LANG=C
  if [ "$JAVA_FEATURE_VERSION" -ge 13 ]; then
    export PATH=/opt/freeware/bin:$JAVA_HOME/bin:/usr/local/bin:/opt/IBM/xlC/16.1.0/bin:/opt/IBM/xlc/16.1.0/bin:$PATH
    export CC=xlclang
    export CXX=xlclang++
  else
    export PATH=/opt/freeware/bin:$JAVA_HOME/bin:/usr/local/bin:/opt/IBM/xlC/13.1.3/bin:/opt/IBM/xlc/13.1.3/bin:$PATH
  fi
fi
