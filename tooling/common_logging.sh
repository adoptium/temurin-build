#!/bin/sh
#
# Utility functions for logging.
#

set -eu

NORMAL=""
BOLD=""
RED=""
YELLOW=""


########################################################################################################################
#
# Initializes logging with ansi coloring.
#
########################################################################################################################
init_ansi_logging() {
  # check if stdout is a terminal...
  if test -t 1; then
    # see if it supports colors...
    ncolors=$(tput colors)

    if test -n "$ncolors" && test "$ncolors" -ge 8; then
      NORMAL="$(tput sgr0)"
      BOLD="$(tput bold)"
      RED="$(tput setaf 1)"
      YELLOW="$(tput setaf 3)"
    fi
  fi

  export NORMAL
  export BOLD
  export RED
  export YELLOW
}


print_error() {
  echo "${RED}ERROR:${NORMAL} $*" 1>&2;
}

print_warning() {
  echo "${YELLOW}WARN:${NORMAL} $*" 1>&2;
}
