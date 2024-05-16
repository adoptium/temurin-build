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
source repro_common.sh

BLD_TYPE1="$1"
JDK_DIR1="$2"
BLD_TYPE2="$3"
JDK_DIR2="$4"
OS="$5"

JDK_DIR_Arr=("${JDK_DIR1}" "${JDK_DIR2}")
for  JDK_DIR in "${JDK_DIR_Arr[@]}"
do
  if [[ ! -d "${JDK_DIR}" ]] || [[ ! -d "${JDK_DIR}/bin"  ]]; then
    echo "$JDK_DIR does not exist or does not point at a JDK"
    echo "repro_compare.sh (temurin|openjdk) JDK_DIR1 (temurin|openjdk) JDK_DIR2 OS"
    exit 1
  fi

  echo "Pre-processing ${JDK_DIR}"
  rc=0
  source ./repro_process.sh "${JDK_DIR}" "${OS}" || rc=$?
  if [ $rc != 0 ]; then
    echo "Pre-process of ${JDK_DIR} ${OS} failed"
    exit 1
  fi

  # If comparing a plain openjdk build to a Temurin built one clean Temurin script specific content
  if [ "$BLD_TYPE1" != "$BLD_TYPE2" ]; then
    cleanTemurinFiles "${JDK_DIR}"
  fi
  # release file build machine OS level and builds-scripts SHA can/will be different
  cleanTemurinBuildInfo "${JDK_DIR}"

  if [[ "$OS" =~ CYGWIN* ]] || [[ "$OS" =~ Darwin* ]]; then 
    removeSystemModulesHashBuilderParams
  fi
  processModuleInfo
done


files1=$(find "${JDK_DIR1}" -type f | wc -l)
echo "Number of files: ${files1}"
rc=0
output="reprotest.diff"
echo "Comparing ${JDK_DIR1} with ${JDK_DIR2} ... output to file: ${output}"
diff -r -q "${JDK_DIR1}" "${JDK_DIR2}" > "${output}" || rc=$?

cat "${output}"

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
