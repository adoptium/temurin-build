#!/bin/bash

BUILD_ARGS=${BUILD_ARGS:-""}
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

if [ "${OPERATING_SYSTEM}" == "mac" ] ; then
  EXTENSION="tar.gz"
elif [ "${OPERATING_SYSTEM}" == "windows" ] ; then
  EXTENSION="zip"
else
  exit 0
fi

for file in $(ls "./target/*/*/*/*.${EXTENSION}");
do
  sha256sum "$file" > $file.sha256.txt;
  $SCRIPT_DIR/../sign.sh ${BUILD_ARGS} "$file"
done