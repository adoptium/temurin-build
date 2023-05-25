#!/bin/bash
# shellcheck disable=SC2034,SC1091
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
###############################################################################

source repro_common.sh

BLD_TYPE1="$1"
JDK_DIR1="$2"
BLD_TYPE2="$3"
JDK_DIR2="$4"
SELF_CERT="$5"
SELF_CERT_PASS="$6"

if [ ! -d "${JDK_DIR1}" ]; then
  echo "$JDK_DIR1 does not exist"
  echo "mac_repro_compare.sh (temurin|openjdk) JDK_DIR1 (temurin|openjdk) JDK_DIR2 self_cert self_cert_passwd"
  exit 1
fi

if [ ! -d "${JDK_DIR2}" ]; then
  echo "$JDK_DIR2 does not exist"
  echo "mac_repro_compare.sh (temurin|openjdk) JDK_DIR1 (temurin|openjdk) JDK_DIR2 self_cert self_cert_passwd"
  exit 1
fi

echo "Pre-processing ${JDK_DIR1}"
if ! mac_repro_process.sh "${JDK_DIR1}" "${SELF_CERT}" "${SELF_CERT_PASS}"; then
  echo "Pre-process of ${JDK_DIR1} failed"
  exit 1
fi

echo "Pre-processing ${JDK_DIR2}"
if ! mac_repro_process.sh "${JDK_DIR2}" "${SELF_CERT}" "${SELF_CERT_PASS}"; then
  echo "Pre-process of ${JDK_DIR2} failed"
  exit 1
fi

# If comparing a plain openjdk build to a Temurin built one clean Temurin script specific content
if [ "$BLD_TYPE1" != "$BLD_TYPE2" ]; then
  cleanTemurinFiles "${JDK_DIR1}"
  cleanTemurinFiles "${JDK_DIR2}"
fi

# release file build machine OS level and builds-scripts SHA can/will be different
cleanTemurinBuildInfo "${JDK_DIR1}"
cleanTemurinBuildInfo "${JDK_DIR2}"

files1=$(find "${JDK_DIR1}" -type f | wc -l)

output="repro_diff.out"
echo "Comparing ${JDK_DIR1} with ${JDK_DIR2} ... output to file: ${output}"
diff -r "${JDK_DIR1}" "${JDK_DIR2}" > "${output}"
rc=$?
echo "diff rc=${rc}"

num_differences=$(wc -l < "${output}")
echo "Number of differences: ${num_differences}"
repro_pc100=$(( (files1-num_differences)*100*100/files1 ))
value_len=${#repro_pc100}
if [ "$repro_pc100" == "10000" ]; then
    repro_pc="100"
elif [ "$value_len" == "4" ]; then
    repro_pc=${repro_pc100:0:2}"."${repro_pc100:2:2}
elif [ "$value_len" == "3" ]; then
    repro_pc=${repro_pc100:0:1}"."${repro_pc100:1:2}
else
    repro_pc="0.${repro_pc100}"
fi
echo "ReproduciblePercent = ${repro_pc} %"

exit $rc

