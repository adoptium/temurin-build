#!/bin/bash
# ********************************************************************************
# Copyright (c) 2026 Contributors to the Eclipse Foundation
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
#
# Run release_download_test_new.sh for every supported arch/os combination in
# parallel, reusing an already-downloaded staging directory (-s flag).
#
# Usage:
#   validate_all_archs.sh [OPTIONS] TAG
#
# Options:
#   -j N     max parallel jobs (default: number of arch/os pairs, i.e. unbounded)
#   -a       pass -a (ANSI colour) to the validation script
#   -k       pass -k (keep staging) to the validation script
#   -h       show this help
#
# The staging directory must already exist at $WORKSPACE/staging/$TAG.
# Run release_download_test_new.sh without -s first to download it, then use
# this script to validate all arches without re-downloading.
#
# Exit code: number of failed arch/os combinations (0 = all passed).
#

set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${0}" )" && pwd )"
VALIDATION_SCRIPT="${SCRIPT_DIR}/release_download_test_new.sh"
WORKSPACE="${WORKSPACE:-"$PWD"}"

ANSI_FLAG=""
KEEP_FLAG=""
MAX_JOBS=0   # 0 = unlimited (one job per arch)

usage() {
  echo "Usage: $(basename "${0}") [-j N] [-a] [-k] [-h] TAG"
  echo ""
  echo "  -j N   max parallel jobs (default: one per arch/os, all at once)"
  echo "  -a     enable ANSI colour output"
  echo "  -k     keep staging area after validation"
  echo "  -h     show this help"
  exit 1
}

while getopts ":j:akh" opt; do
  case "${opt}" in
    j) MAX_JOBS="${OPTARG}";;
    a) ANSI_FLAG="-a";;
    k) KEEP_FLAG="-k";;
    h) usage;;
    "?") echo "Unknown option '-${OPTARG}'"; usage;;
    ":") echo "No value for option '-${OPTARG}'"; usage;;
  esac
done
shift $((OPTIND-1))

[ $# -ne 1 ] && usage
TAG="$1"

STAGING="${WORKSPACE}/staging/${TAG}"
if [ ! -d "${STAGING}" ]; then
  echo "ERROR: staging directory not found: ${STAGING}"
  echo "       Run release_download_test_new.sh without -s first to download."
  exit 1
fi

# All supported arch/os combinations.
# Format: "ARCH OS binary_checks"
#   binary_checks=native  → run java -version + strings checks (native arch/os)
#   binary_checks=strings → run strings checks only (-A/-O override, no java -version)
#   binary_checks=skip    → skip all binary checks (-b flag; non-GCC platforms)
COMBOS=(
  "x64       linux         native"
  "aarch64   linux         native"
  "x64       alpine-linux  strings"
  "aarch64   alpine-linux  strings"
  "x64       mac           skip"
  "aarch64   mac           skip"
  "s390x     linux         strings"
  "ppc64le   linux         strings"
  "ppc64     aix           skip"
  "riscv64   linux         strings"
  "arm       linux         strings"
  "x64       windows       skip"
  "aarch64   windows       skip"
)

LOGDIR="${WORKSPACE}/staging/${TAG}/validation-logs"
mkdir -p "${LOGDIR}"

# Determine native arch/os of this machine for the 'native' combos
NATIVE_ARCH=""
case "$(uname -m)" in
  x86_64)  NATIVE_ARCH=x64;;
  aarch64) NATIVE_ARCH=aarch64;;
  ppc64le) NATIVE_ARCH=ppc64le;;
  s390x)   NATIVE_ARCH=s390x;;
  *)       NATIVE_ARCH=unknown;;
esac
NATIVE_OS="linux"
if [ -f /etc/alpine-release ]; then NATIVE_OS="alpine-linux"; fi

echo "========================================================================"
echo " Multi-arch validation: ${TAG}"
echo " Native machine: ${NATIVE_ARCH}/${NATIVE_OS}"
echo " Logs: ${LOGDIR}/"
echo "========================================================================"
echo ""

PIDS=()
COMBO_NAMES=()
COMBO_LOGS=()
ACTIVE=0

run_validation() {
  local arch="$1" os="$2" checks="$3"
  local label="${arch}/${os}"
  local logfile="${LOGDIR}/${arch}_${os}.log"

  local flags="-s ${ANSI_FLAG} ${KEEP_FLAG} -A ${arch} -O ${os}"

  case "${checks}" in
    native)
      # Only attempt java -version if we're actually on this native machine.
      # If arch/os doesn't match this native machine, -A/-O mismatch will auto-skip java -version.
      ;;
    strings)
      ;;  # -A/-O set but no -b: strings checks run, java -version auto-skipped
    skip)
      flags="${flags} -b"  # skip all binary checks
      ;;
  esac

  # shellcheck disable=SC2086
  WORKSPACE="${WORKSPACE}" bash "${VALIDATION_SCRIPT}" ${flags} "${TAG}" \
    > "${logfile}" 2>&1
}

# Launch jobs, respecting MAX_JOBS
for combo in "${COMBOS[@]}"; do
  read -r arch os checks <<< "${combo}"
  label="${arch}/${os}"
  logfile="${LOGDIR}/${arch}_${os}.log"

  # Throttle if MAX_JOBS set
  if [ "${MAX_JOBS}" -gt 0 ]; then
    while [ "${ACTIVE}" -ge "${MAX_JOBS}" ]; do
      wait -n 2>/dev/null || true
      ACTIVE=$(( ACTIVE - 1 ))
    done
  fi

  echo "  Starting  [${label}]"
  run_validation "${arch}" "${os}" "${checks}" &
  PIDS+=($!)
  COMBO_NAMES+=("${label}")
  COMBO_LOGS+=("${logfile}")
  ACTIVE=$(( ACTIVE + 1 ))
done

echo ""
echo "  All ${#PIDS[@]} jobs launched — waiting for completion ..."
echo ""

# Collect results
FAILURES=0
for i in "${!PIDS[@]}"; do
  pid="${PIDS[$i]}"
  label="${COMBO_NAMES[$i]}"
  logfile="${COMBO_LOGS[$i]}"

  if wait "${pid}"; then
    result="PASS"
  else
    result="FAIL"
    FAILURES=$(( FAILURES + 1 ))
  fi

  # Extract the summary line from the log for a one-liner result
  rc_line=$(grep "Overall:" "${logfile}" 2>/dev/null | tail -1 | sed 's/\x1b\[[0-9;]*m//g' || echo "Overall: ${result}")
  printf "  %-25s  %s  (log: %s)\n" "[${label}]" "${rc_line}" "$(basename "${logfile}")"
done

echo ""
echo "========================================================================"
if [ "${FAILURES}" -eq 0 ]; then
  echo " ALL PASSED (${#PIDS[@]} arch/os combinations)"
else
  echo " ${FAILURES} FAILED of ${#PIDS[@]} arch/os combinations"
  echo " Review logs in: ${LOGDIR}/"
fi
echo "========================================================================"

# Clean up per-arch GNUPGHOME directories left by the validation script
for combo in "${COMBOS[@]}"; do
  read -r arch os _ <<< "${combo}"
  rm -rf "${WORKSPACE}/.gpg-temp-${arch}-${os}"
done

exit "${FAILURES}"
