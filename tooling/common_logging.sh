#!/bin/sh
#
# Utility functions for logging.
#

set -eu

NORMAL=""
BOLD=""
RED=""
YELLOW=""

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

print_verbose() {
  [ "$VERBOSE" = "true" ] && echo "${BOLD}$(date +%T) : $*${NORMAL}" 1>&2;
}

print_error() {
  echo "${RED}ERROR:${NORMAL} $*" 1>&2;
}

print_warning() {
  echo "${YELLOW}WARN:${NORMAL} $*" 1>&2;
}
