#!/bin/bash
# ********************************************************************************
# Copyright (c) 2024 Contributors to the Eclipse Foundation
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

# shellcheck disable=SC1091
source "$(dirname "$0")"/repro_common.sh

BLD_TYPE1="$1"
JDK_DIR1="$2"
BLD_TYPE2="$3"
JDK_DIR2="$4"
OS="$5"

checkJdkDir() {
  JDK_DIR="${1}"
  if [[ ! -d "${JDK_DIR}" ]] || [[ ! -d "${JDK_DIR}/bin"  ]]; then
    echo "$JDK_DIR does not exist or does not point at a JDK"
    echo "repro_compare.sh (temurin|openjdk) JDK_DIR1 (temurin|openjdk) JDK_DIR2 OS"
    exit 1
  fi
}

checkJdkDir "${JDK_DIR1}"
checkJdkDir "${JDK_DIR2}"

# if PREPROCESS flag is set to 'no', then preprocessing is not run
# this is usefull, if yo want to compare two identical copies of JDK
#  or if you want to run repro_compare.sh only as result generator after you
#  run comparable_patch.sh. This helps to keep diff in unified output
if [ -z "${PREPROCESS:-}" ] ; then
  PREPROCESS="yes"
fi

mkdir "${JDK_DIR}_BK"
cp -R "${JDK_DIR1}"/* "${JDK_DIR}"_BK
BK_JDK_DIR=$(realpath "${JDK_DIR}"_BK/)

JDK_DIR_Arr=("${JDK_DIR1}" "${JDK_DIR2}")
if [ "$PREPROCESS" != "no" ] ; then
for  JDK_DIR in "${JDK_DIR_Arr[@]}"
do
  echo "$(date +%T) : Pre-processing ${JDK_DIR}"
  rc=0
  source "$(dirname "$0")"/repro_process.sh "${JDK_DIR}" "${OS}" || rc=$?
  if [ $rc != 0 ]; then
    echo "$(date +%T): Pre-processing of ${JDK_DIR} ${OS} failed"
    exit 1
  fi

  # If comparing a plain openjdk build to a Temurin built one clean Temurin script specific content
  if [ "$BLD_TYPE1" != "$BLD_TYPE2" ]; then
    cleanTemurinFiles "${JDK_DIR}"
  fi
  # release file build machine OS level and builds-scripts SHA can/will be different
  cleanTemurinBuildInfo "${JDK_DIR}"

  removeJlinkRuntimelinkHashes "${JDK_DIR}" "${OS}"

  if [[ "$OS" =~ CYGWIN* ]] || [[ "$OS" =~ Darwin* ]]; then
    removeSystemModulesHashBuilderParams "${JDK_DIR}" "${OS}" "${BK_JDK_DIR}"
    processModuleInfo "${JDK_DIR}" "${OS}" "${BK_JDK_DIR}"
  fi
done
else
  echo "Preprocessing skipped on user request. Generating just diff."
fi

files1=$(find "${JDK_DIR1}" -type f | wc -l)
echo "Number of files: ${files1}"
rc=0
output="reprotest.diff"
echo "$(date +%T) : Comparing expanded JDKs from ${JDK_DIR1} with ${JDK_DIR2} ..."
diff -r -q "${JDK_DIR1}" "${JDK_DIR2}" > "${output}" || rc=$?
echo "$(date +%T) : diff complete - rc=$rc. Output written to file: ${output}"

cat "${output}"

# Restricting detailed output to classlist files only.
# This is because grepping every file overloads the test
# job with too much output, but the class list contents
# are especially useful when debugging a failure.
grep "Files .*/classlist" "${output}" | while read -r line; do
  FILE1=$(echo "$line" | awk '{print $2}')
  FILE2=$(echo "$line" | awk '{print $4}')
  echo "diff -c on $FILE1 and $FILE2"
  diff -c "$FILE1" "$FILE2"
done

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
