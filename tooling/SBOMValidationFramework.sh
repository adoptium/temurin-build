#!/bin/sh
# ********************************************************************************
# Copyright (c) 2023 Contributors to the Eclipse Foundation
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

# This script executes the following SBOM validation mechanisms
# - ./validateSBOMcontent.sh
# - https://github.com/CycloneDX/cyclonedx-cli



function arg_parser() {
  if [[ $# != 3 ]]; then
    echo "ERROR: SBOMValidationFramework.sh did not receive three arguments."
    echo "This script requires three arguments: JDK_MAJOR_VERSION SOURCE_TAG SBOM_LOCATION"
    echo "Note that the SBOM_LOCATION can be a local file or a web address, but must be an absolute path."
    exit 1
  fi

  if [[ ! $1 =~ ^[1-9][0-9]*\$ ]]; then
    echo "ERROR: SBOMValidationFramework.sh: first argument must be a positive integer greater than 0."
    exit 1
  fi

  if [[ -z "$2" ]]; then
    echo "ERROR: SBOMValidationFramework.sh: second argument must not be empty."
    exit 1
  fi

  if [[ -z "$3" ]]; then
    echo "ERROR: SBOMValidationFramework.sh: third argument must not be empty."
    exit 1
  fi

  # Now we check that the third argument is a valid link.
  if [[ "" ]]

}

echo "SBOM validation start."
echo "Stage 1"
if bash "${SCRIPT_DIR}/../tooling/validateSBOMcontent.sh" "${sbomJson}" "${BUILD_CONFIG[OPENJDK_FEATURE_NUMBER]}" "${BUILD_CONFIG[BRANCH]}"; then
  echo "SBOM validation has passed."
else
  echo "ERROR: SBOM validation has failed."
  exit 1
fi

# Script start
arg_parser "$@"



exit 0 # Success
