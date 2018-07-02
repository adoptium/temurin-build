#!/bin/bash

BUILD_ARGS=${BUILD_ARGS:-""}
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

export OPERATING_SYSTEM

if [ "${OPERATING_SYSTEM}" == "mac" ] ; then
  EXTENSION="tar.gz"
elif [ "${OPERATING_SYSTEM}" == "windows" ] ; then
  EXTENSION="zip"
else
  echo "OS does not need signing ${OPERATING_SYSTEM}"
  exit 0
fi

echo "files:"
ls -alh workspace/target/

echo "OpenJDK*.${EXTENSION}"

for file in $(find workspace/target/ -name "OpenJDK*.${EXTENSION}");
do
  echo "signing ${file}"
  sha256sum "$file" > "$file.sha256.txt"

  # shellcheck disable=SC2086
  bash "${SCRIPT_DIR}/../sign.sh" ${BUILD_ARGS} "${file}"
done