#!/bin/sh
#
# Utility functions for logging.
#

set -eu

export NORMAL=""
export BOLD=""
export RED=""
export YELLOW=""

# check if stdout is a terminal...
if test -t 1; then
  # see if it supports colors...
  ncolors=$(tput colors)

  if test -n "$ncolors" && test "$ncolors" -ge 8; then
    export NORMAL="$(tput sgr0)"
    export BOLD="$(tput bold)"
    export RED="$(tput setaf 1)"
    export YELLOW="$(tput setaf 3)"
  fi
fi

print_error() {
  echo "${RED}ERROR:${NORMAL} $*" 1>&2;
}

print_warning() {
  echo "${YELLOW}WARN:${NORMAL} $*" 1>&2;
}
