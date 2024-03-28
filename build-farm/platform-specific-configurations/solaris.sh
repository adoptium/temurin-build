#!/bin/bash
# shellcheck disable=SC1091
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

export BUILD_ARGS="${BUILD_ARGS} --skip-freetype --make-args SHELL=/bin/bash"

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
