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


BUILD_ARGS=${BUILD_ARGS:-""}
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

export SIGN_TOOL
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

find workspace/target/ -name "OpenJDK*.${EXTENSION}" | while read -r file;
do
  case "${file}" in
    *debugimage*) echo "Skipping ${file} because it's a debug image" ;;
    *testimage*) echo "Skipping ${file} because it's a test image" ;;
    *)
      echo "signing ${file}"

      # shellcheck disable=SC2086
      bash "${SCRIPT_DIR}/../sign.sh" ${CERTIFICATE} "${file}"
    ;;
  esac
done