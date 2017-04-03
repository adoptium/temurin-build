#!/usr/bin/env bash

# arg1 : the PR long hash
# arg2 : the SHA1 hash
#
# Returns String message

ghprbActualCommit="$1"
sha1="$2"

# check PR merge-ability
if [ "${sha1}" == "${ghprbActualCommit}" ]; then
  echo " * This patch **does not merge cleanly**."
else
  echo " * This patch merges cleanly."
fi

