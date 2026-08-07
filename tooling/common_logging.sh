#!/bin/sh
# ********************************************************************************
# Copyright (c) 2023 Contributors to the Eclipse Foundation
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

#
# Utility functions for logging.
#

set -eu

NORMAL=""
BOLD=""
RED=""
YELLOW=""
GREEN=""
CYAN=""


########################################################################################################################
#
# Initializes logging with ansi coloring.
# The caller has explicitly opted in with -a, so no TTY check is performed —
# this ensures colours work correctly in Jenkins where stdout is not a TTY.
#
########################################################################################################################
init_ansi_logging() {
  ncolors=$(tput colors 2>/dev/null || echo 0)

  if test -n "$ncolors" && test "$ncolors" -ge 8; then
    NORMAL="$(tput sgr0)"
    BOLD="$(tput bold)"
    RED="$(tput setaf 1)"
    YELLOW="$(tput setaf 3)"
    GREEN="$(tput setaf 2)"
    CYAN="$(tput setaf 6)"
  fi

  export NORMAL
  export BOLD
  export RED
  export YELLOW
  export GREEN
  export CYAN
}


print_error() {
  echo "${RED}ERROR:${NORMAL} $*" 1>&2;
}

print_warning() {
  echo "${YELLOW}WARN:${NORMAL} $*" 1>&2;
}
