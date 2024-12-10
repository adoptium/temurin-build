#!/bin/bash
# ********************************************************************************
# Copyright (c) 2018 Contributors to the Eclipse Foundation
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

set -eu

BUILD_ARGS=${BUILD_ARGS:-""}
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

export SIGN_TOOL
export OPERATING_SYSTEM
export VERSION

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
    *sbom*) echo "Skipping ${file} because it's an sbom archive" ;; 
    *)
      echo "signing ${file}"

      # shellcheck disable=SC2086
      bash "${SCRIPT_DIR}/../sign.sh" ${CERTIFICATE} "${file}"
    ;;
  esac
done
