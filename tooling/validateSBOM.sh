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

# This script executes the following SBOM validation mechanisms.
# - For all OpenJDK sboms: https://github.com/CycloneDX/cyclonedx-cli
# - For Eclipse Temurin SBOMs only: ./validateTemurinSBOM.sh

JDK_MAJOR_VERSION=""
SOURCE_TAG=""
SBOM_LOCATION=""
SCRIPT_DIR="$( cd "$( dirname "${0}" )" && pwd )"
WORKSPACE_DIR=""
CYCLONEDX_TOOL=""

########################################################################################################################
#
# Parses the three expected arguments passed into this script:
# - JDK_MAJOR_VERSION: The major version of the JDK whose SBOM this is.
#                      - E.g. For JDK17.0.1+35 the major version is 17.
# - SOURCE_TAG:        The tag of the source code build to make the aforementioned JDK.
# - SBOM_LOCATION:     The location of the SBOM to be verified.
#                      - This can be a file location or a web URL, but must be an absolute path.
#
########################################################################################################################
arg_parser() {
  if [ $# -ne 3 ]; then
    echo "ERROR: validateSBOM.sh did not receive 3 arguments."
    echo "Arguments should be: JDK_MAJOR_VERSION SOURCE_TAG SBOM_LOCATION"
    exit 1
  fi

  if [ -z $WORKSPACE ]; then
    WORKSPACE_DIR=~/workspace_temp
    echo "validateSBOM.sh: WORKSPACE environment variable not detected."
    if [ -d "${WORKSPACE_DIR}" ]; then
      echo "validateSBOM.sh: ERROR: New temporary workspace already exists in ${WORKSPACE_DIR}"
      echo "Aborting to avoid conflict."
      exit 1
    else
      mkdir "${WORKSPACE_DIR}"
      cd ${WORKSPACE_DIR}
      echo "validateSBOM.sh: Using this directory as the workspace instead: ${WORKSPACE_DIR}"
    fi
  else
    WORKSPACE_DIR="${WORKSPACE}"
    cd "${WORKSPACE}"
  fi

  JDK_MAJOR_VERSION="$1"
  SOURCE_TAG="$2"
  SBOM_LOCATION="$3"

  echo "$JDK_MAJOR_VERSION" | grep ^[1-9][0-9]*\$
  if [ $? -ne 0 ]; then
    echo "ERROR: validateSBOM.sh: first argument must be a positive integer greater than 0."
    exit 1
  fi

  if [ -z "$SOURCE_TAG" ]; then
    echo "ERROR: validateSBOM.sh: second argument must not be empty."
    exit 1
  fi

  if [ -z "$SBOM_LOCATION" ]; then
    echo "ERROR: validateSBOM.sh: third argument must not be empty."
    exit 1
  fi

  # Now we check that the third argument is a valid link.
  echo "$SBOM_LOCATION" | grep -q ^https.*
  if [ $? -eq 0 ]; then
    wget --spider --quiet "$SBOM_LOCATION"
    if [ $? -eq 0 ]; then
      wget --quiet -O "${WORKSPACE_DIR}/sbom_text.txt" "$SBOM_LOCATION"
      [ $? -ne 0 ] && echo "ERROR: SBOM_LOCATION exists but could not be downloaded." && exit 1
      SBOM_LOCATION="${WORKSPACE_DIR}/sbom_text.txt"
    else
      echo "ERROR: SBOM_LOCATION was identified as a URL but could not be found." 
      exit 1
    fi
  elif [ ! -r "$SBOM_LOCATION" ]; then
    echo "ERROR: SBOM_LOCATION could not be found/accessed." 
    exit 1
  fi
}

########################################################################################################################
#
# Downloads the cyclonedx tool for the current os/arch.
# return : cyclonedx cli tool command
#
########################################################################################################################
download_cyclonedx_tool() {
  local kernel machine
  local cyclonedx_os cyclonedx_arch cyclonedx_suffix
  local cyclonedx_checksum

  cyclonedx_suffix=""

  kernel="$(uname -s)"
  case "${kernel}" in
      Linux*)     cyclonedx_os=linux;;
      Darwin*)    cyclonedx_os=osx;;
      CYGWIN*)    cyclonedx_os=win
                  cyclonedx_suffix=".exe";;
      *)          cyclonedx_os="unknown";;
  esac

  machine="$(uname -m)"
  case "${machine}" in
      x86_64)     cyclonedx_arch=x64;;
      aarch64)    cyclonedx_arch=arm64;;
      *)          cyclonedx_arch="unknown";;
  esac

  case "${cyclonedx_os}-${cyclonedx_arch}" in
      linux-x64)   cyclonedx_checksum="5e1595542a6367378a3944bbd3008caab3de65d572345361d3b9597b1dbbaaa0";;
      linux-arm64) cyclonedx_checksum="5b4181f6fd4d8fbe54e55c1b3983d9af66ce2910a263814b290cbd5e351e68a4";;
      osx-x64)     cyclonedx_checksum="331c2245ef7dadf09fa3d2710a2aaab071ff6bea2ba3e5df8f95a4f3f6e825e9";;
      osx-arm64)   cyclonedx_checksum="2d24c331c2ccc5e4061722bd4780c8b295041b2569d130bbe80cf7da95b97171";;
      win-x64)     cyclonedx_checksum="bb26bb56293ebe6f08fa63d2bf50653fc6b180174fded975c81ac96ac192a7db";;
      win-arm64)   cyclonedx_checksum="35762d3e1979576f474ffc1c5b2273e19c33cdca44e5f1994c3de5d9cd0e9c1d";;
      *)           cyclonedx_checksum="";;
  esac

  if [ -n "${cyclonedx_checksum}" ]; then
    echo "validateSBOM.sh: Downloading CycloneDX CLI binary ..."

    CYCLONEDX_TOOL="cyclonedx-${cyclonedx_os}-${cyclonedx_arch}${cyclonedx_suffix}"

    cd "${WORKSPACE_DIR}"
    [ ! -r "${CYCLONEDX_TOOL}" ] && curl -LOsS https://github.com/CycloneDX/cyclonedx-cli/releases/download/v0.27.2/"${CYCLONEDX_TOOL}"
    if [ "$(sha256sum "${CYCLONEDX_TOOL}" | cut -d' ' -f1)" != "${cyclonedx_checksum}" ]; then
       echo "validateSBOM.sh: Error: Cannot verify checksum of CycloneDX CLI binary"
       exit 1
    else
       echo "validateSBOM.sh: Downloaded CycloneDX CLI binary to '${CYCLONEDX_TOOL}'"
    fi
    chmod 700 "${CYCLONEDX_TOOL}"
  else
    echo "validateSBOM.sh: Error: No CycloneDX tool available for '${kernel}-${machine}'"
    exit 1
  fi
}

########################################################################################################################
#
# Verifies the SBOM using cyclonedx-cli and validateTemurinSBOM.sh
#
########################################################################################################################
validate_sbom() {
  echo "validateSBOM.sh: SBOM validation start."
  echo "validateSBOM.sh: Running general SBOM validation from https://github.com/CycloneDX/cyclonedx-cli"

  # shellcheck disable=SC2010
  echo "validateSBOM.sh: Running ${CYCLONEDX_TOOL} ..."

  echo "Command: \"${WORKSPACE_DIR}/${CYCLONEDX_TOOL}\" validate --input-file \"${SBOM_LOCATION} --input-format json"
  if ! "${WORKSPACE_DIR}/${CYCLONEDX_TOOL}" validate --input-file "${SBOM_LOCATION}" --input-format json; then
    echo "validateSBOM.sh: Error: Failed CycloneDX validation check."
    exit 5
  else
    echo "validateSBOM.sh: Passed CycloneDX validation check."
  fi

  # shellcheck disable=SC2086
  echo "validateSBOM.sh: Running validateTemurinSBOM.sh"
  if bash "${WORKSPACE_DIR}/tooling/validateTemurinSBOM.sh" "$SBOM_LOCATION" "$JDK_MAJOR_VERSION" "$SOURCE_TAG"; then
    echo "validateTemurinSBOM.sh: PASSED"
  else
    echo "validateTemurinSBOM.sh: ERROR: FAILED"
    exit 1
  fi

  echo "SBOM validation complete."
}

# Script start
arg_parser "$@"

download_cyclonedx_tool

validate_sbom

exit 0 # Success
