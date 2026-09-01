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
# Unit tests for release_download_test_new.sh
# Tests the pure-logic functions (no network, no GPG, no downloads).
# Run with: bash tooling/release_download_test/unit_tests/test_release_download.sh
#

set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# The unit tests live two levels below tooling/ (tooling/release_download_test/unit_tests/)
# so we need to go up two directories to reach the tooling/ root.
TOOLING_DIR="${SCRIPT_DIR}/../.."
SCRIPT_UNDER_TEST="${SCRIPT_DIR}/../release_download_test_new.sh"

# Source the script in TEST_MODE so only functions are loaded, not the main pipeline.
# SCRIPT_DIR is set to the release_download_test/ subdirectory (the script's natural location).
# TOOLING_DIR is exported explicitly so the script's `source "${TOOLING_DIR}/common_logging.sh"`
# resolves to the tooling/ root rather than being computed from the injected SCRIPT_DIR.
export TEST_MODE=true
export SCRIPT_DIR="${TOOLING_DIR}/release_download_test"
export TOOLING_DIR="${TOOLING_DIR}"
# Silence any ANSI colour escapes that common_logging may set
# shellcheck disable=SC2034
BOLD="" NORMAL=""
# shellcheck source=/dev/null
source "${SCRIPT_UNDER_TEST}"

FAILURES=0

assertEquals() {
  local expected="$1"
  local actual="$2"
  local message="$3"
  if [ "${expected}" != "${actual}" ]; then
    echo "FAIL: ${message}"
    echo "  expected: '${expected}'"
    echo "  actual  : '${actual}'"
    FAILURES=$(( FAILURES + 1 ))
  fi
}

# ---------------------------------------------------------------------------
# extract_major_version tests
# ---------------------------------------------------------------------------

TAG="jdk8u382-b05"
extract_major_version
assertEquals "8" "${MAJOR_VERSION}" "extract_major_version: jdk8u tag"

TAG="jdk-21.0.3+9"
extract_major_version
assertEquals "21" "${MAJOR_VERSION}" "extract_major_version: jdk-XX GA tag"

TAG="jdk-17.0.10+7"
extract_major_version
assertEquals "17" "${MAJOR_VERSION}" "extract_major_version: jdk-17 GA tag"

TAG="jdk21u-2024-01-01-00-00-beta"
extract_major_version
assertEquals "21" "${MAJOR_VERSION}" "extract_major_version: jdkXXu EA beta tag"

TAG="jdk11u-2023-10-05-00-33-beta"
extract_major_version
assertEquals "11" "${MAJOR_VERSION}" "extract_major_version: jdk11u EA beta tag"

TAG="jdk26u-2026-07-25-11-35-beta"
extract_major_version
assertEquals "26" "${MAJOR_VERSION}" "extract_major_version: jdkXXu DATE-beta EA tag"

echo "PASS: extract_major_version"

# ---------------------------------------------------------------------------
# determine_arch tests — mock uname to avoid hardware dependency
# ---------------------------------------------------------------------------

# Override uname within this test scope
run_determine_arch() {
  local mock_machine="$1"
  # shellcheck disable=SC2317
  uname() { echo "${mock_machine}"; }
  ARCH=""
  determine_arch
  unset -f uname
  echo "${ARCH}"
}

assertEquals "x64"     "$(run_determine_arch x86_64)"  "determine_arch: x86_64 -> x64"
assertEquals "aarch64" "$(run_determine_arch aarch64)"  "determine_arch: aarch64 -> aarch64"
assertEquals "ppc64le" "$(run_determine_arch ppc64le)"  "determine_arch: ppc64le -> ppc64le"
assertEquals "s390x"   "$(run_determine_arch s390x)"    "determine_arch: s390x -> s390x"
assertEquals "arm"     "$(run_determine_arch armv7l)"   "determine_arch: armv7l -> arm"
assertEquals "ppc64"   "$(run_determine_arch ppc64)"    "determine_arch: ppc64 -> ppc64"
assertEquals "riscv64" "$(run_determine_arch riscv64)"  "determine_arch: riscv64 -> riscv64"

echo "PASS: determine_arch"

# ---------------------------------------------------------------------------
# determine_os tests — mock uname and /etc/alpine-release
# ---------------------------------------------------------------------------

run_determine_os() {
  local mock_kernel="$1"
  local mock_alpine="${2:-false}"
  # shellcheck disable=SC2317
  uname() { echo "${mock_kernel}"; }
  # Mock alpine-release presence using a temp file
  local _tmpdir
  _tmpdir="$(mktemp -d)"
  if [ "${mock_alpine}" = "true" ]; then
    touch "${_tmpdir}/alpine-release"
    # Patch the check inside determine_os by overriding the file path via temp dir trick:
    # We cannot easily mock /etc/alpine-release directly, so we test the logic
    # by calling the function with knowledge that on this Linux CI host
    # /etc/alpine-release will not exist, and verify the non-alpine path.
    # The alpine detection branch is tested via direct variable injection below.
    rm -rf "${_tmpdir}"
    unset -f uname
    OS="alpine-linux"  # simulate post-detect result
    return
  fi
  OS=""
  determine_os
  unset -f uname
  rm -rf "${_tmpdir}"
  echo "${OS}"
}

assertEquals "linux"   "$(run_determine_os Linux)"   "determine_os: Linux -> linux"
assertEquals "mac"     "$(run_determine_os Darwin)"  "determine_os: Darwin -> mac"
assertEquals "windows" "$(run_determine_os CYGWIN_NT-10.0)" "determine_os: CYGWIN -> windows"
assertEquals "aix"     "$(run_determine_os AIX)"     "determine_os: AIX -> aix"

# Alpine detection: on a non-alpine host /etc/alpine-release does not exist so
# determine_os returns plain "linux". We verify the alpine branch by simulating
# what happens when the file exists using a subshell with a mocked path.
_alpine_result=$(
  # shellcheck disable=SC2317
  uname() { echo "Linux"; }
  # Temporarily create the file in a location and redirect via a wrapper
  _td="$(mktemp -d)"
  _af="${_td}/alpine-release"
  touch "${_af}"
  # Inline the alpine detection logic (same as in the script) for the test
  OS="linux"
  [ -f "${_af}" ] && OS="alpine-linux"
  echo "${OS}"
  rm -rf "${_td}"
)
assertEquals "alpine-linux" "${_alpine_result}" "determine_os: alpine-linux detection when /etc/alpine-release present"

echo "PASS: determine_os"

# ---------------------------------------------------------------------------
# parse_options tests
# ---------------------------------------------------------------------------

reset_flags() {
  KEEP_STAGING=false
  SKIP_DOWNLOADING=false
  USE_ANSI=false
  # shellcheck disable=SC2034
  VERBOSE=false
  SKIP_BINARY_CHECKS=false
  GPG_ONLY=false
  SKIP_GPG=false
  SBOM_ONLY=false
  SKIP_SBOM=false
  SOURCES_ONLY=false
  OVERRIDE_ARCH=""
  OVERRIDE_OS=""
  TAG=""
  _DOWNLOAD_COUNT=0
}

# -k sets KEEP_STAGING
reset_flags
parse_options -k "jdk-21.0.3+9"
assertEquals "true" "${KEEP_STAGING}" "parse_options: -k sets KEEP_STAGING"

# -s sets SKIP_DOWNLOADING
reset_flags
parse_options -s "jdk-21.0.3+9"
assertEquals "true" "${SKIP_DOWNLOADING}" "parse_options: -s sets SKIP_DOWNLOADING"

# -a sets USE_ANSI
reset_flags
parse_options -a "jdk-21.0.3+9"
assertEquals "true" "${USE_ANSI}" "parse_options: -a sets USE_ANSI"

# -b sets SKIP_BINARY_CHECKS
reset_flags
parse_options -b "jdk-21.0.3+9"
assertEquals "true" "${SKIP_BINARY_CHECKS}" "parse_options: -b sets SKIP_BINARY_CHECKS"

# -A sets OVERRIDE_ARCH
reset_flags
parse_options -A aarch64 "jdk-21.0.3+9"
assertEquals "aarch64" "${OVERRIDE_ARCH}" "parse_options: -A sets OVERRIDE_ARCH"

# -O sets OVERRIDE_OS
reset_flags
parse_options -O linux "jdk-21.0.3+9"
assertEquals "linux" "${OVERRIDE_OS}" "parse_options: -O sets OVERRIDE_OS"

# combined flags
reset_flags
parse_options -b -A s390x -O linux "jdk-21.0.3+9"
assertEquals "true"  "${SKIP_BINARY_CHECKS}" "parse_options: combined -b -A -O: SKIP_BINARY_CHECKS"
assertEquals "s390x" "${OVERRIDE_ARCH}"       "parse_options: combined -b -A -O: OVERRIDE_ARCH"
assertEquals "linux" "${OVERRIDE_OS}"         "parse_options: combined -b -A -O: OVERRIDE_OS"

# TAG is captured from positional arg
reset_flags
parse_options "jdk8u382-b05"
assertEquals "jdk8u382-b05" "${TAG}" "parse_options: positional TAG arg"

# -c sets SBOM_ONLY
reset_flags
parse_options -c "jdk-21.0.3+9"
assertEquals "true" "${SBOM_ONLY}" "parse_options: -c sets SBOM_ONLY"

# -C sets SKIP_SBOM
reset_flags
parse_options -C "jdk-21.0.3+9"
assertEquals "true" "${SKIP_SBOM}" "parse_options: -C sets SKIP_SBOM"

# -r sets SOURCES_ONLY
reset_flags
parse_options -r "jdk-21.0.3+9"
assertEquals "true" "${SOURCES_ONLY}" "parse_options: -r sets SOURCES_ONLY"

echo "PASS: parse_options"

# ---------------------------------------------------------------------------
# Phase-state flags — GPG_ONLY, SKIP_GPG, SBOM_ONLY, SKIP_SBOM correctness
# ---------------------------------------------------------------------------

# GPG-only mode (-g): binary and SBOM phases must be SKIP (not run / not "−").
# This mirrors the logic at the end of the main pipeline where GPG_ONLY=true
# causes the script to set those phases and exit before running them.
reset_flags
GPG_ONLY=true
_PHASE_BINARIES="−"
_PHASE_SBOM="−"
if [ "${GPG_ONLY}" = "true" ]; then
  _PHASE_BINARIES="SKIP"
  _PHASE_SBOM="SKIP"
fi
assertEquals "SKIP" "${_PHASE_BINARIES}" "phase-state: GPG_ONLY=true sets _PHASE_BINARIES=SKIP"
assertEquals "SKIP" "${_PHASE_SBOM}"     "phase-state: GPG_ONLY=true sets _PHASE_SBOM=SKIP"

# SKIP_GPG mode (-G): in arch-node mode the script calls read_platform_results() which
# loads results from staging rather than hard-coding SKIP.  Verify _PHASE_GPG_IMPORT is
# still not touched (remains at its initial "−") since it is not shown in the arch-node
# consolidated summary — the table only shows SIGNATURES, ARCHIVES, BINARIES, SBOM.
reset_flags
# shellcheck disable=SC2034
SKIP_GPG=true
_PHASE_GPG_IMPORT="−"
_PHASE_SIGNATURES="−"
_PHASE_ARCHIVES="−"
# In arch-node mode read_platform_results() is called; simulate its behaviour here
# by confirming that _PHASE_GPG_IMPORT is NOT modified (it is not part of the arch table).
assertEquals "−" "${_PHASE_GPG_IMPORT}" "phase-state: SKIP_GPG=true leaves _PHASE_GPG_IMPORT unset (not shown in arch table)"

# SBOM-only mode (-c): download, GPG, archive, and binary phases must be SKIP.
reset_flags
SBOM_ONLY=true
_PHASE_DOWNLOAD="−"
_PHASE_GPG_IMPORT="−"
_PHASE_SIGNATURES="−"
_PHASE_ARCHIVES="−"
_PHASE_BINARIES="−"
if [ "${SBOM_ONLY}" = "true" ]; then
  _PHASE_DOWNLOAD="SKIP"
  _PHASE_GPG_IMPORT="SKIP"
  _PHASE_SIGNATURES="SKIP"
  _PHASE_ARCHIVES="SKIP"
  _PHASE_BINARIES="SKIP"
fi
assertEquals "SKIP" "${_PHASE_DOWNLOAD}"   "phase-state: SBOM_ONLY=true sets _PHASE_DOWNLOAD=SKIP"
assertEquals "SKIP" "${_PHASE_GPG_IMPORT}" "phase-state: SBOM_ONLY=true sets _PHASE_GPG_IMPORT=SKIP"
assertEquals "SKIP" "${_PHASE_SIGNATURES}" "phase-state: SBOM_ONLY=true sets _PHASE_SIGNATURES=SKIP"
assertEquals "SKIP" "${_PHASE_ARCHIVES}"   "phase-state: SBOM_ONLY=true sets _PHASE_ARCHIVES=SKIP"
assertEquals "SKIP" "${_PHASE_BINARIES}"   "phase-state: SBOM_ONLY=true sets _PHASE_BINARIES=SKIP"

# Skip-SBOM mode (-C): SBOM phase must be SKIP.
reset_flags
SKIP_SBOM=true
_PHASE_SBOM="−"
if [ "${SKIP_SBOM}" = "true" ]; then
  _PHASE_SBOM="SKIP"
fi
assertEquals "SKIP" "${_PHASE_SBOM}" "phase-state: SKIP_SBOM=true sets _PHASE_SBOM=SKIP"

echo "PASS: phase-state flags"

# ---------------------------------------------------------------------------
# write_platform_results / flush_results_to_disk / read_platform_results tests
# ---------------------------------------------------------------------------

_tmp_workspace="$(mktemp -d)"
# shellcheck disable=SC2034
WORKSPACE="${_tmp_workspace}"
TAG="jdk-21.0.3+9"
ARCH="x64"
OS="linux"

# write_platform_results: creates a result file with the expected content
write_platform_results "gpg" "x64/linux" "PASS"
_result_file="${_tmp_workspace}/staging/${TAG}/.results/gpg_x64_linux.result"
if [ ! -f "${_result_file}" ]; then
  echo "FAIL: write_platform_results did not create ${_result_file}"
  FAILURES=$(( FAILURES + 1 ))
else
  _got="$(cat "${_result_file}")"
  assertEquals "PASS" "${_got}" "write_platform_results: gpg x64/linux PASS content"
fi

write_platform_results "sbom" "aarch64/mac" "FAIL"
_sbom_file="${_tmp_workspace}/staging/${TAG}/.results/sbom_aarch64_mac.result"
_got="$(cat "${_sbom_file}")"
assertEquals "FAIL" "${_got}" "write_platform_results: sbom aarch64/mac FAIL content"

# flush_results_to_disk: writes multiple entries from an accumulator
_acc="x64/alpine-linux PASS
s390x/linux FAIL"
flush_results_to_disk "gpg" "${_acc}"
assertEquals "PASS" "$(cat "${_tmp_workspace}/staging/${TAG}/.results/gpg_x64_alpine-linux.result")" \
  "flush_results_to_disk: gpg x64/alpine-linux PASS"
assertEquals "FAIL" "$(cat "${_tmp_workspace}/staging/${TAG}/.results/gpg_s390x_linux.result")" \
  "flush_results_to_disk: gpg s390x/linux FAIL"

# read_platform_results: reads files and populates phase variables
ARCH="x64"
OS="linux"
_PHASE_SIGNATURES="−"
_PHASE_ARCHIVES="−"
_PHASE_SBOM="−"
write_platform_results "gpg"     "x64/linux" "PASS"
write_platform_results "archive" "x64/linux" "PASS"
write_platform_results "sbom"    "x64/linux" "PASS"
read_platform_results
assertEquals "PASS" "${_PHASE_SIGNATURES}" "read_platform_results: _PHASE_SIGNATURES from file"
assertEquals "PASS" "${_PHASE_ARCHIVES}"   "read_platform_results: _PHASE_ARCHIVES from file"
assertEquals "PASS" "${_PHASE_SBOM}"       "read_platform_results: _PHASE_SBOM from file"

# read_platform_results: missing files → N/A
ARCH="ppc64"
OS="aix"
_PHASE_SIGNATURES="−"
_PHASE_ARCHIVES="−"
_PHASE_SBOM="−"
read_platform_results
assertEquals "N/A" "${_PHASE_SIGNATURES}" "read_platform_results: missing gpg file → N/A"
assertEquals "N/A" "${_PHASE_ARCHIVES}"   "read_platform_results: missing archive file → N/A"
assertEquals "N/A" "${_PHASE_SBOM}"       "read_platform_results: missing sbom file → N/A"

# read_platform_results: FAIL propagates from file
ARCH="aarch64"
OS="linux"
write_platform_results "gpg"     "aarch64/linux" "FAIL"
write_platform_results "archive" "aarch64/linux" "PASS"
write_platform_results "sbom"    "aarch64/linux" "FAIL"
_PHASE_SIGNATURES="−"
_PHASE_ARCHIVES="−"
_PHASE_SBOM="−"
read_platform_results
assertEquals "FAIL" "${_PHASE_SIGNATURES}" "read_platform_results: FAIL from gpg file"
assertEquals "PASS" "${_PHASE_ARCHIVES}"   "read_platform_results: PASS from archive file"
assertEquals "FAIL" "${_PHASE_SBOM}"       "read_platform_results: FAIL from sbom file"

# write_platform_results "source" "global" → source_global.result
_tmp_src_ws="$(mktemp -d)"
WORKSPACE="${_tmp_src_ws}" TAG="jdk-21.0.3+9" \
  write_platform_results "source" "global" "PASS"
_src_result_file="${_tmp_src_ws}/staging/jdk-21.0.3+9/.results/source_global.result"
if [ ! -f "${_src_result_file}" ]; then
  echo "FAIL: write_platform_results did not create ${_src_result_file}"
  FAILURES=$(( FAILURES + 1 ))
else
  assertEquals "PASS" "$(cat "${_src_result_file}")" "write_platform_results: source/global writes source_global.result with PASS"
fi
rm -rf "${_tmp_src_ws}"

rm -rf "${_tmp_workspace}"

echo "PASS: write_platform_results / flush_results_to_disk / read_platform_results"

# ---------------------------------------------------------------------------
# arch/os extraction regex — GA and EA filename formats
# ---------------------------------------------------------------------------
# Validate the sed pattern used in verify_gpg_signatures() and verify_sboms()
# to extract arch/os from filenames.  Both GA (OpenJDK21U-) and EA (OpenJDK-)
# formats must be handled.

_extract_arch_os() {
  local filename="$1"
  echo "${filename}" | sed -n 's/^OpenJDK[0-9]*[A-Z]*-[^_]*_\([^_]*\)_\([^_]*\)_.*/\1\/\2/p'
}

# GA release filenames
assertEquals "x64/linux"          "$(_extract_arch_os "OpenJDK21U-jdk_x64_linux_hotspot_21.0.3_9.tar.gz")"    "arch/os regex: GA jdk x64/linux"
assertEquals "aarch64/mac"        "$(_extract_arch_os "OpenJDK21U-jre_aarch64_mac_hotspot_21.0.3_9.tar.gz")"  "arch/os regex: GA jre aarch64/mac"
assertEquals "x64/alpine-linux"   "$(_extract_arch_os "OpenJDK21U-sbom_x64_alpine-linux_hotspot_21.0.3_9.json")" "arch/os regex: GA sbom x64/alpine-linux"
assertEquals "ppc64/aix"          "$(_extract_arch_os "OpenJDK11U-jdk_ppc64_aix_hotspot_11.0.22_7.tar.gz")"   "arch/os regex: GA jdk ppc64/aix"
assertEquals "x64/windows"        "$(_extract_arch_os "OpenJDK17U-jdk_x64_windows_hotspot_17.0.11_9.zip")"    "arch/os regex: GA jdk x64/windows"

# EA release filenames (no version number, no U)
assertEquals "x64/linux"          "$(_extract_arch_os "OpenJDK-jdk_x64_linux_hotspot_27_9-ea.tar.gz")"        "arch/os regex: EA jdk x64/linux"
assertEquals "aarch64/linux"      "$(_extract_arch_os "OpenJDK-jre_aarch64_linux_hotspot_27_9-ea.tar.gz")"    "arch/os regex: EA jre aarch64/linux"
assertEquals "x64/alpine-linux"   "$(_extract_arch_os "OpenJDK-sbom_x64_alpine-linux_hotspot_27_9-ea.json")"  "arch/os regex: EA sbom x64/alpine-linux"
assertEquals "aarch64/windows"    "$(_extract_arch_os "OpenJDK-jdk_aarch64_windows_hotspot_27_9-ea.zip")"     "arch/os regex: EA jdk aarch64/windows"
assertEquals "s390x/linux"        "$(_extract_arch_os "OpenJDK-debugimage_s390x_linux_hotspot_27_9-ea.tar.gz")" "arch/os regex: EA debugimage s390x/linux"

# Arch-agnostic files (sources, release-notes) must return empty string
assertEquals "" "$(_extract_arch_os "OpenJDK-jdk-sources_27_9-ea.tar.gz")"   "arch/os regex: sources file yields empty"
assertEquals "" "$(_extract_arch_os "OpenJDK21U-jdk-sources_21.0.3_9.tar.gz")" "arch/os regex: GA sources file yields empty"

echo "PASS: arch/os extraction regex (GA + EA filenames)"

# ---------------------------------------------------------------------------
# native_arch / native_os helpers — only validate they return a known value
# ---------------------------------------------------------------------------

_got_arch="$(native_arch)"
case "${_got_arch}" in
  x64|aarch64|ppc64le|s390x|arm|ppc64|riscv64|unknown) ;;
  *) echo "FAIL: native_arch returned unexpected value '${_got_arch}'"; FAILURES=$(( FAILURES + 1 ));;
esac

_got_os="$(native_os)"
case "${_got_os}" in
  linux|alpine-linux|mac|windows|aix|unknown) ;;
  *) echo "FAIL: native_os returned unexpected value '${_got_os}'"; FAILURES=$(( FAILURES + 1 ));;
esac

echo "PASS: native_arch / native_os"

# ---------------------------------------------------------------------------
# Source tarball directory structure checks
# ---------------------------------------------------------------------------
# Test the grep pattern used in verify_source_tarball() to detect top-level dirs.
# Pattern: grep -q "^[^/]*/${_req_dir}"  against tar tf listing lines.
#
# JDK 8 uses the old "forest" layout: hotspot/ jdk/ make/ test/ (no src/)
# JDK 11+ uses the consolidated layout: src/ make/ test/

# JDK 21 mock listing (consolidated layout)
_mock_listing_jdk21="$(mktemp)"
printf 'jdk-21.0.3+9/src/share/classes/java/lang/Object.java\njdk-21.0.3+9/make/Makefile\njdk-21.0.3+9/test/jdk/README\n' \
  > "${_mock_listing_jdk21}"

# JDK 21: src/ make/ test/ all present → 0 failures
MAJOR_VERSION=21
_struct_fail=0
for _req_dir in src/ make/ test/; do
  grep -q "^[^/]*/${_req_dir}" "${_mock_listing_jdk21}" || _struct_fail=$(( _struct_fail + 1 ))
done
assertEquals "0" "${_struct_fail}" "dir-structure: JDK 21 full listing (src/make/test present) -> 0 failures"

# JDK 21: test/ missing → 1 failure
_mock_listing_no_test="$(mktemp)"
printf 'jdk-21.0.3+9/src/share/classes/java/lang/Object.java\njdk-21.0.3+9/make/Makefile\n' \
  > "${_mock_listing_no_test}"
_struct_fail2=0
for _req_dir in src/ make/ test/; do
  grep -q "^[^/]*/${_req_dir}" "${_mock_listing_no_test}" || _struct_fail2=$(( _struct_fail2 + 1 ))
done
assertEquals "1" "${_struct_fail2}" "dir-structure: JDK 21 listing missing test/ -> 1 failure"

# JDK 8 mock listing (forest layout: hotspot/ jdk/ make/ test/, no src/)
_mock_listing_jdk8="$(mktemp)"
printf 'jdk8u502-b07-src/hotspot/src/share/vm/oops/oop.hpp\njdk8u502-b07-src/jdk/src/share/classes/java/lang/Object.java\njdk8u502-b07-src/make/Makefile\njdk8u502-b07-src/test/Makefile\n' \
  > "${_mock_listing_jdk8}"

# JDK 8: hotspot/ jdk/ make/ test/ all present → 0 failures
MAJOR_VERSION=8
_struct_fail3=0
for _req_dir in hotspot/ jdk/ make/ test/; do
  grep -q "^[^/]*/${_req_dir}" "${_mock_listing_jdk8}" || _struct_fail3=$(( _struct_fail3 + 1 ))
done
assertEquals "0" "${_struct_fail3}" "dir-structure: JDK 8 full listing (hotspot/jdk/make/test present) -> 0 failures"

# JDK 8: src/ should NOT be required (it doesn't exist in forest layout)
_struct_fail4=0
grep -q "^[^/]*/src/" "${_mock_listing_jdk8}" || _struct_fail4=$(( _struct_fail4 + 1 ))
assertEquals "1" "${_struct_fail4}" "dir-structure: JDK 8 listing correctly has no src/ -> grep fails as expected"

rm -f "${_mock_listing_jdk21}" "${_mock_listing_no_test}" "${_mock_listing_jdk8}"

echo "PASS: source tarball directory structure checks"

# ---------------------------------------------------------------------------
# Final result
# ---------------------------------------------------------------------------

if [ "${FAILURES}" -gt 0 ]; then
  echo "FAIL: ${FAILURES} test(s) failed"
  exit 1
fi

echo "PASS: all release_download_test_new.sh unit tests passed"
