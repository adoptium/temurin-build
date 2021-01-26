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

export BUILD_ARGS="${BUILD_ARGS} --skip-freetype"

if [ "${ARCHITECTURE}" == "x64" ]; then
  export CUPS="--with-cups=/opt/sfw/cups"
  export MEMORY=4000
elif [ "${ARCHITECTURE}" == "sparcv9" ]; then
  export CUPS="--with-cups=/opt/csw/lib/ --with-cups-include=/usr/local/cups-1.5.4-src"
  export FREETYPE="--with-freetype=/usr/local/"
  export MEMORY=16000
fi

export CONFIGURE_ARGS_FOR_ANY_PLATFORM="${CONFIGURE_ARGS_FOR_ANY_PLATFORM} ${CUPS} ${FREETYPE} --with-memory-size=${MEMORY}"
# /usr/sfw/bin required for OpenSSL (build#2265)
export PATH=/opt/solarisstudio12.3/bin/:/opt/csw/bin/:/usr/ccs/bin:$PATH:/usr/sfw/bin

export LC_ALL=C
export HOTSPOT_DISABLE_DTRACE_PROBES=true
export ENFORCE_CC_COMPILER_REV=5.12
