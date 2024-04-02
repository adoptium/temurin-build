#!/bin/bash
# shellcheck disable=SC1091
# ********************************************************************************
# Copyright (c) 2019 Contributors to the Eclipse Foundation
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

export BUILD_ARGS="${BUILD_ARGS} -r https://github.com/FreeBSD/openjdk-${JAVA_TO_BUILD}"

export CONFIGURE_ARGS_FOR_ANY_PLATFORM="${CONFIGURE_ARGS_FOR_ANY_PLATFORM} --with-toolchain-type=clang --with-fontconfig=/usr/local --with-alsa=/usr/local --x-includes=/usr/local/include --x-libraries=/usr/local/lib --with-cups=/usr/local"
