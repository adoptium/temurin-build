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
# Adoptium download and SBOM validation utility
# Takes a tagged build as a parameter and downloads it from the
# GitHub temurinXX-binaries and runs validation checks on it
#
# Exit codes:
#   1 - Something fundamentally wrong before we could check anything
#   2 - GPG signature verification failed
#   3 - SHA checksum failed
#   4 - detected GCC/GLIBC version not as expected
#   5 - CylconeDX validation checks failed
#   6 - SBOM contents did not meet expectations
# Note that if there are multiple failures the highest will be the exit code
# If there is a non-zero exit code check the output for "ERROR:"
# 
# For future enhancement ideas, see https://github.com/adoptium/temurin-build/issues/3506#issuecomment-1783237963
#

set -euo pipefail

WORKSPACE=${WORKSPACE:-"$PWD"}
KEEP_STAGING=false
SKIP_DOWNLOADING=false
USE_ANSI=false
VERBOSE=false
SKIP_BINARY_CHECKS=false
GPG_ONLY=false
SKIP_GPG=false
SBOM_ONLY=false
SKIP_SBOM=false
SOURCES_ONLY=false
OVERRIDE_ARCH=""
OVERRIDE_OS=""
ARCH_FILTER_LIST=""

MAJOR_VERSION=""

# Per-phase pass/fail tracking for the final summary (values: PASS | FAIL | SKIP | -)
_PHASE_DOWNLOAD="−"
_PHASE_GPG_IMPORT="−"
_PHASE_SIGNATURES="−"
_PHASE_ARCHIVES="−"
_PHASE_BINARIES="−"
_PHASE_SBOM="−"
_PHASE_SOURCES="−"

# Count of files downloaded in the most recent download_release_files() call.
_DOWNLOAD_COUNT=0

# Per-arch/os GPG result lines, accumulated by verify_gpg_signatures().
# Each entry is a newline-separated "arch/os PASS|FAIL" record.
_GPG_PER_ARCH=""

# Per-arch/os SBOM result lines, accumulated by verify_sboms().
# Each entry is a newline-separated "arch/os PASS|FAIL" record.
_SBOM_PER_ARCH=""

# Allow SCRIPT_DIR to be injected externally (e.g. when sourced in TEST_MODE).
# The script lives in tooling/release_download_test/ but common_logging.sh is one
# level up in tooling/ — use TOOLING_DIR for shared utilities.
SCRIPT_DIR="${SCRIPT_DIR:-"$( cd "$( dirname "${0}" )" && pwd )"}"
TOOLING_DIR="${TOOLING_DIR:-"$( cd "${SCRIPT_DIR}/.." && pwd )"}"

# shellcheck source=tooling/common_logging.sh
source "${TOOLING_DIR}/common_logging.sh"

usage() {
  local USAGE
  USAGE="
Usage: $(basename "${0}") [OPTIONS] [TAG]

This scripts downloads the specified release from the GitHub temurinXX-binaries and runs validation checks on it.

If no TAG is provided, it is expected that a \$TAG variable is present containing the tag to validate.
If no \$WORKSPACE variable is set, the current working directory will be used as base for the staging area, otherwise
the directory specified in the \$WORKSPACE variable will be used.

Options:
  -k       keep staging area (should only be used for debugging / testing)
  -s       skip downloading of release artifacts (should only be used for debugging / testing)
  -a       enables ansi coloring of output
  -v       enable verbose mode
  -b       skip binary string checks (GCC/GLIBC via 'strings'); run GPG/SHA/archive/SBOM checks only
  -g       GPG-only mode: download ALL files (or filtered subset if -F is set), import GPG key,
           verify all GPG/SHA256 sigs and archive integrity, then exit.
           Use this on a central node before arch stages run.
  -G       Skip-GPG mode: download only files matching -A arch / -O os, skip GPG import/verify
           and archive checks (already done centrally by -g), then run binary + SBOM checks.
           Requires -A and -O to be set. Use this on each arch-specific node.
  -c       SBOM-only mode: validate SBOMs for ALL arches from the central staging area, then
           exit. Requires staging to already be populated (run after -g stage). Use this on
           the central node as a dedicated SBOM validation stage.
  -C       Skip-SBOM mode: skip SBOM validation on arch nodes (already done centrally by -c).
           Use this on each arch-specific node alongside -G.
  -r       Sources-only mode: download the source tarball and its GPG/SHA256 sidecars,
           verify the GPG signature and SHA256 checksum, check archive integrity, assert
           file count (>=45000), and validate top-level directory structure. Then exit.
           Use this on the central node as a dedicated source tarball validation stage.
  -A arch  override arch used for tarball matching and binary checks (bypasses uname detection)
  -O os    override OS used for tarball matching and binary checks (bypasses uname detection)
  -F list  comma-separated list of arch_os tokens to download in GPG-only mode (-g), e.g.
           x64_linux,aarch64_linux. Arch-agnostic files (sources, release-notes, AQAvit) are
           always included. Leave unset to download the full release (default).
  -h       show this help
"
  echo "$USAGE"
  exit 1
}

parse_options() {
  local OPTIND opt

  while getopts ":hvksabgGcCrA:O:F:" opt; do
      case "${opt}" in
          h)   usage;;
          v)   VERBOSE=true;;
          k)   KEEP_STAGING=true;;
          s)   SKIP_DOWNLOADING=true;;
          a)   USE_ANSI=true;;
          b)   SKIP_BINARY_CHECKS=true;;
          g)   GPG_ONLY=true;;
          G)   SKIP_GPG=true;;
          c)   SBOM_ONLY=true;;
          C)   SKIP_SBOM=true;;
          r)   SOURCES_ONLY=true;;
          A)   OVERRIDE_ARCH="${OPTARG}";;
          O)   OVERRIDE_OS="${OPTARG}";;
          F)   ARCH_FILTER_LIST="${OPTARG}";;
          "?") echo "Unknown option '-$OPTARG'"
               usage;;
          ":") echo "No argument value for option '-$OPTARG'"
               usage;;
          *)   usage;;
      esac
  done

  shift $((OPTIND-1))

  [ "$VERBOSE" = "true" ] && set +x

  if [ $# -gt 1 ]; then
      usage
  fi

  # the tag should be the remaining argument, if no argument is available
  # anymore, check if the environment already has a TAG variable.
  TAG=${1:-$TAG}

  if [ -z "${TAG-}" ]; then
      usage
  fi
}

########################################################################################################################
#
# Return the [ARCH/OS] log prefix used to identify this stage's output when
# parallel stages are running concurrently in Jenkins.
# Central modes (GPG-only, SBOM-only) show [worker] rather than the worker's
# native arch/os, since they operate on all platforms rather than one specific one.
# Falls back to [-/-] before ARCH/OS have been determined.
#
########################################################################################################################
_log_prefix() {
  if [ "${GPG_ONLY}" = "true" ] || [ "${SBOM_ONLY}" = "true" ] || [ "${SOURCES_ONLY}" = "true" ]; then
    echo "[worker]"
    return
  fi
  local arch="${ARCH:-${OVERRIDE_ARCH:--}}"
  local os="${OS:-${OVERRIDE_OS:--}}"
  echo "[${arch}/${os}]"
}

########################################################################################################################
#
# Print a section banner marking the start of a major validation phase.
# Verbose-gated: only printed when -v is active, to keep normal Jenkins output minimal.
#
########################################################################################################################
print_section() {
  if [ "$VERBOSE" = "true" ]; then
    echo "${CYAN}${BOLD}$(_log_prefix) === $(date +%T) : $* ===${NORMAL}"
  fi
}

########################################################################################################################
#
# Print an informational line. Verbose-gated.
#
########################################################################################################################
print_info() {
  if [ "$VERBOSE" = "true" ]; then
    echo "$(_log_prefix) $(date +%T) : $*"
  fi
}

########################################################################################################################
#
# Print a per-item PASS confirmation. Verbose-gated.
#
########################################################################################################################
print_pass() {
  if [ "$VERBOSE" = "true" ]; then
    echo "${GREEN}$(_log_prefix) PASS:${NORMAL} $*"
  fi
}

########################################################################################################################
#
# A utility function to print verbose output.
#
########################################################################################################################
print_verbose() {
  if [ "$VERBOSE" = "true" ]; then
    echo "${BOLD}$(_log_prefix) $(date +%T) : $*${NORMAL}" 1>&2;
  fi
}

########################################################################################################################
#
# Extract JDK major version from a specified tag.
#
########################################################################################################################
extract_major_version() {
  if echo "${TAG}" | grep jdk8u > /dev/null; then
    MAJOR_VERSION=8
  elif echo "${TAG}" | grep ^jdk- > /dev/null; then
    MAJOR_VERSION=$(echo "${TAG}" | cut -d- -f2 | cut -d. -f1 | cut -d\+ -f1)
  else
    # Probably a beta with the tag starting jdkXXu
    MAJOR_VERSION=$(echo "${TAG}" | cut -d- -f1 | tr -d jdku)
  fi
}

########################################################################################################################
#
# Download release information from GitHub for the specified tag.
# Always fetches the specific release directly by tag name using the
# /releases/tags/<tag> endpoint. This is reliable for all tag formats
# (GA, CSPU, EA beta) and avoids pagination issues where CSPU or older
# releases may not appear within the first page of the list endpoint.
# return : file containing release information
#
########################################################################################################################
download_jdk_releases() {
  local output_file
  output_file="${WORKSPACE}/jdk${MAJOR_VERSION}.txt"

  print_verbose "IVT : Fetching release info for tag '${TAG}' directly from GitHub API"
  # The + character in GA tags (e.g. jdk-11.0.32.1+1) must be percent-encoded as %2B in URLs.
  local encoded_tag
  encoded_tag="$(echo "${TAG}" | sed 's/+/%2B/g')"
  if ! curl --path-as-is -sS "https://api.github.com/repos/adoptium/temurin${MAJOR_VERSION}-binaries/releases/tags/${encoded_tag}" > "${output_file}"; then
    print_error "GitHub API call failed for tag ${TAG} - aborting"
    exit 2
  fi

  # Wrap the single-release object in an array so download_release_files can use
  # the same grep/sed pipeline regardless of tag format.
  local tmp_file="${output_file}.tmp"
  echo "[" > "${tmp_file}"
  cat "${output_file}" >> "${tmp_file}"
  echo "]" >> "${tmp_file}"
  mv "${tmp_file}" "${output_file}"

  echo "${output_file}"
}

########################################################################################################################
#
# Download release files.
# param 1: jdk release info file
#
# When SKIP_GPG=true (arch-node mode) only files belonging to the target ARCH/OS pair are
# downloaded — the full release was already verified by the central GPG stage.  Both the
# arch-specific binaries (jdk/jre/debugimage/testimage/static-libs) and the arch-specific
# SBOM JSON files are included so that SBOM validation can run locally.
# All other modes download every file in the release.
#
########################################################################################################################
download_release_files() {
  local jdk_releases filter arch_filter url

  jdk_releases=$1

  cd "${WORKSPACE}/staging/${TAG}" || exit 1

  # Build the tag filter used to match browser_download_url values for this release.
  # EA beta tags use the full tag name in the URL path (e.g. jdk26u-2026-07-25-11-35-beta).
  # GA tags encode the + as %2B in the URL (e.g. /jdk-21.0.3%2B9/).
  if echo "${TAG}" | grep "^jdk${MAJOR_VERSION}u-.*-beta" > /dev/null; then
    filter="${TAG}"
  else
    # shellcheck disable=SC2001
    filter=$(echo "/${TAG}/" | sed 's/+/%2B/g')
  fi

  # Determine per-file arch filtering:
  #
  # -G mode (arch-node):        download only files for the single ARCH/OS pair.
  # -g mode + -F list (central): download files for each token in ARCH_FILTER_LIST, plus all
  #                              arch-agnostic files (sources, release-notes, AQAvit, sig/sha/json
  #                              metadata that belongs to no specific arch).
  # -g mode without -F (central): download everything (no filter).
  if [ "${SKIP_GPG}" = "true" ]; then
    # Arch-node: single arch/os
    arch_filter="${ARCH}_${OS}"
  elif [ -n "${ARCH_FILTER_LIST}" ]; then
    # Central with -F: comma-separated list, e.g. "x64_linux,aarch64_linux"
    arch_filter="${ARCH_FILTER_LIST}"
  else
    arch_filter=""
  fi

  print_info "Starting downloads for tag '${TAG}' (filter: ${filter}${arch_filter:+, archs: ${arch_filter}}) ..."
  _DOWNLOAD_COUNT=0
  while IFS= read -r url; do
    # Apply arch filtering when active.
    if [ -n "${arch_filter}" ]; then
      local _base _matched
      _base="$(basename "${url}")"
      _matched=false

      if [ "${SKIP_GPG}" = "true" ]; then
        # Arch-node mode: single token match (original behaviour).
        case "${_base}" in
          OpenJDK*_${arch_filter}_*|OpenJDK*-sbom_${arch_filter}_*) _matched=true;;
        esac
      else
        # Central -g + -F mode: iterate over comma-separated token list.
        # Arch-agnostic files (AQAvit, sources, release-notes) are always kept.
        case "${_base}" in
          AQAvitTapFiles*|OpenJDK*-jdk-sources_*|OpenJDK*-jdk-release-notes_*) _matched=true;;
          *)
            # Split on commas using IFS — save and restore around the for loop to avoid
            # disrupting the outer while loop's IFS= read.  A nested process substitution
            # inside the outer < <(...) feed does not work reliably in bash.
            local _tok _saved_IFS="${IFS}"
            IFS=","
            for _tok in ${arch_filter}; do
              IFS="${_saved_IFS}"
              case "${_base}" in
                OpenJDK*_${_tok}_*|OpenJDK*-sbom_${_tok}_*) _matched=true; break;;
              esac
            done
            IFS="${_saved_IFS}"
            ;;
        esac
      fi

      [ "${_matched}" = "false" ] && continue
    fi
    print_verbose "IVT : Downloading $(basename "$url")"
    curl --path-as-is -LORsS -C - "$url"
    _DOWNLOAD_COUNT=$(( _DOWNLOAD_COUNT + 1 ))
  done < <(grep "${filter}" "${jdk_releases}" | sed -n 's/.*"browser_download_url": *"\([^"]*\)".*/\1/p')
  print_info "Finished downloads — ${_DOWNLOAD_COUNT} files downloaded to staging"
  _PHASE_DOWNLOAD="PASS"
}

########################################################################################################################
#
# Import the Temurin GPG key.
#
########################################################################################################################
import_gpg_key() {
  local gpg_log
  print_verbose "IVT : Import Temurin GPG key"
  cd "${WORKSPACE}/staging/${TAG}" || exit 1
  umask 022
  export GPGID=3B04D753C9050D9A5D343F39843C48A565F8F04B
  # Use an arch/os-specific GNUPGHOME so parallel invocations do not clobber each other.
  export GNUPGHOME="${WORKSPACE}/.gpg-temp-${ARCH}-${OS}"
  rm -rf "${GNUPGHOME}"
  mkdir -p "${GNUPGHOME}" && chmod og-rwx "${GNUPGHOME}"
  gpg_log="${GNUPGHOME}/import.log"
  if ! gpg --keyserver keyserver.ubuntu.com --recv-keys "${GPGID}" > "${gpg_log}" 2>&1; then
    print_error "GPG key import failed"
    cat "${gpg_log}"
    exit 1
  fi
  # shellcheck disable=SC3037
  if ! /bin/echo -e "5\ny\nq\n" | gpg --batch --command-fd 0 --expert --edit-key "${GPGID}" trust >> "${gpg_log}" 2>&1; then
    print_error "GPG key trust setting failed"
    cat "${gpg_log}"
    exit 1
  fi
  print_info "GPG key imported and trusted (${GPGID:0:16}...)"
  _PHASE_GPG_IMPORT="PASS"
}

########################################################################################################################
#
# Verify GPG and SHA256 signatures of all archives / json files.
#
########################################################################################################################
verify_gpg_signatures() {
  local A sig_failures=0 sha_failures=0 checked=0

  print_section "GPG & SHA256 Signature Verification"

  cd "${WORKSPACE}/staging/${TAG}" || exit 1

  # Build the list of files to verify by probing each glob separately so that
  # file types absent from this release (e.g. no .msi, no SBOM JSON for EA beta)
  # do not produce "ls: cannot access" noise on stderr.
  local _gpg_files=""
  for _pat in "OpenJDK*.tar.gz" "OpenJDK*.zip" "./*.msi" "./*.pkg" "./*sbom*[0-9].json"; do
    # shellcheck disable=SC2086
    _hits="$(ls -1d ${_pat} 2>/dev/null)" || true
    [ -n "${_hits}" ] && _gpg_files="${_gpg_files}${_hits}"$'\n'
  done

  # shellcheck disable=SC2045
  for A in $(printf '%s' "${_gpg_files}"); do
    print_verbose "IVT : Verifying signature of file ${A}"

    local _file_ok=true
    if ! gpg -q --verify "${A}.sig" "${A}" 2> /dev/null; then
      print_error "GPG signature verification failed for ${A}"
      RC=2
      sig_failures=$(( sig_failures + 1 ))
      _file_ok=false
    else
      if ! grep sbom "${A}" > /dev/null; then # SBOMs don't have sha256.txt files
        if ! sha256sum -c --quiet "${A}.sha256.txt" 2>/dev/null; then
          print_error "SHA256 signature for ${A} is not valid"
          RC=3
          sha_failures=$(( sha_failures + 1 ))
          _file_ok=false
        else
          print_pass "GPG+SHA256: $(basename "${A}")"
        fi
      else
        print_pass "GPG sig:    $(basename "${A}")"
      fi
    fi

    # Extract arch/os from filenames of the form OpenJDK*-<type>_<arch>_<os>_*.
    # Files without that pattern (e.g. sources, release-notes) are skipped.
    local _base _arch_os
    _base="$(basename "${A}")"
    # Match GA: OpenJDK<n>U-<type>_<arch>_<os>_...
    #   e.g. OpenJDK21U-jdk_x64_linux_hotspot_... -> arch=x64 os=linux
    # Match EA: OpenJDK-<type>_<arch>_<os>_...
    #   e.g. OpenJDK-jdk_x64_linux_hotspot_27_9-ea.tar.gz -> arch=x64 os=linux
    # [0-9]*[A-Z]* matches "21U" (GA) or "" (EA) between "OpenJDK" and "-".
    if _arch_os="$(echo "${_base}" | sed -n 's/^OpenJDK[0-9]*[A-Z]*-[^_]*_\([^_]*\)_\([^_]*\)_.*/\1\/\2/p')"; then
      if [ -n "${_arch_os}" ]; then
        # Only mark FAIL if this file failed; never downgrade an existing PASS.
        if [ "${_file_ok}" = "false" ]; then
          # Remove any existing PASS record for this platform and write FAIL
          _GPG_PER_ARCH="$(echo "${_GPG_PER_ARCH}" | grep -v "^${_arch_os} " || true)"
          # Only add FAIL if not already recorded
          if ! echo "${_GPG_PER_ARCH}" | grep -q "^${_arch_os} FAIL"; then
            _GPG_PER_ARCH="${_GPG_PER_ARCH}
${_arch_os} FAIL"
          fi
        else
          # Add PASS only if no record yet for this platform
          if ! echo "${_GPG_PER_ARCH}" | grep -q "^${_arch_os} "; then
            _GPG_PER_ARCH="${_GPG_PER_ARCH}
${_arch_os} PASS"
          fi
        fi
      fi
    fi

    checked=$(( checked + 1 ))
  done

  # Strip leading blank line from accumulator
  _GPG_PER_ARCH="$(echo "${_GPG_PER_ARCH}" | sed '/^[[:space:]]*$/d' | sort)"

  if [ "${sig_failures}" -eq 0 ] && [ "${sha_failures}" -eq 0 ]; then
    print_info "Signature verification complete — ${checked} file(s) checked, all passed"
    _PHASE_SIGNATURES="PASS"
  else
    print_info "Signature verification complete — ${checked} file(s) checked, ${sig_failures} GPG failure(s), ${sha_failures} SHA256 failure(s)"
    _PHASE_SIGNATURES="FAIL"
  fi
}

########################################################################################################################
#
# Verify that all archives are valid and have a reasonable amount of files contained in them.
#
########################################################################################################################
verify_valid_archives() {
  local single_archive arc_failures=0 checked=0

  print_section "Archive Integrity Verification"

  cd "${WORKSPACE}/staging/${TAG}" || exit 1

  # Check to prevent script aborting if no such files exist
  if ls OpenJDK*.tar.gz > /dev/null 2>&1; then
    for single_archive in OpenJDK*.tar.gz; do
      print_verbose "IVT : Counting files in tarball ${single_archive}"
      if ! tar tfz "${single_archive}" > /dev/null; then
        print_error "Failed to verify that ${single_archive} can be extracted"
        RC=4
        arc_failures=$(( arc_failures + 1 ))
      else
        local file_count min_count
        file_count=$(tar tfz "${single_archive}" | wc -l)
        # static-libs archives are legitimately small (10s of files); all other
        # archives (jdk, jre, testimage, debugimage) contain hundreds of files.
        # Use a per-type minimum so a small-but-valid static-libs does not fail.
        case "${single_archive}" in
          *static-libs*) min_count=10 ;;
          *)             min_count=37 ;;
        esac
        if [ "${file_count}" -lt "${min_count}" ]; then
          print_error "Fewer than ${min_count} files in ${single_archive} (found ${file_count}) - that does not seem correct"
          RC=4
          arc_failures=$(( arc_failures + 1 ))
        else
          print_pass "Archive (${file_count} entries): $(basename "${single_archive}")"
        fi
      fi
      checked=$(( checked + 1 ))
    done
  fi

  if ls OpenJDK*.zip > /dev/null 2>&1; then
    for single_archive in OpenJDK*.zip; do
      print_verbose "IVT : Counting files in archive ${single_archive}"
      if ! unzip -t "${single_archive}" > /dev/null; then
        print_error "Failed to verify that ${single_archive} can be extracted"
        RC=4
        arc_failures=$(( arc_failures + 1 ))
      else
        local file_count
        file_count=$(unzip -l "${single_archive}" | wc -l)
        if [ "${file_count}" -lt 44 ]; then
          print_error "Less than 40 files in ${single_archive} (found ${file_count}) - that does not seem correct"
          RC=4
          arc_failures=$(( arc_failures + 1 ))
        else
          print_pass "Archive (${file_count} entries): $(basename "${single_archive}")"
        fi
      fi
      checked=$(( checked + 1 ))
    done
  fi

  if [ "${arc_failures}" -eq 0 ]; then
    print_info "Archive integrity complete — ${checked} archive(s) checked, all passed"
    _PHASE_ARCHIVES="PASS"
  else
    print_info "Archive integrity complete — ${checked} archive(s) checked, ${arc_failures} failure(s)"
    _PHASE_ARCHIVES="FAIL"
  fi
}

########################################################################################################################
#
# Verify the source code tarball for this release.
#
# Downloads OpenJDK*-jdk-sources*.tar.gz and its .sig / .sha256.txt sidecars (unless
# SKIP_DOWNLOADING=true), then:
#   1. GPG signature verification
#   2. SHA256 checksum verification
#   3. Archive extractability check
#   4. File count assertion (>=45000)
#   5. Top-level directory structure check (version-configurable via case statement)
#
# Sets _PHASE_SOURCES to PASS or FAIL and writes source_global.result.
# arch-agnostic: one result covers the entire release.
#
########################################################################################################################
verify_source_tarball() {
  local src_failures=0

  print_section "Source Tarball Validation"

  mkdir -p "${WORKSPACE}/staging/${TAG}"
  cd "${WORKSPACE}/staging/${TAG}" || exit 1

  # ── Step 1: download source tarball + sidecars ──────────────────────────────
  if [ "${SKIP_DOWNLOADING}" = "false" ]; then
    local _src_filter _src_url
    # Build the same tag filter used by download_release_files()
    if echo "${TAG}" | grep "^jdk${MAJOR_VERSION}u-.*-beta" > /dev/null; then
      _src_filter="${TAG}"
    else
      # shellcheck disable=SC2001
      _src_filter=$(echo "/${TAG}/" | sed 's/+/%2B/g')
    fi
    print_verbose "IVT : Downloading source tarball and sidecars for tag '${TAG}'"
    while IFS= read -r _src_url; do
      case "$(basename "${_src_url}")" in
        OpenJDK*-jdk-sources*.tar.gz|OpenJDK*-jdk-sources*.tar.gz.sig|OpenJDK*-jdk-sources*.tar.gz.sha256.txt)
          print_verbose "IVT : Downloading $(basename "${_src_url}")"
          curl --path-as-is -LORsS -C - "${_src_url}"
          ;;
      esac
    done < <(grep "${_src_filter}" "${JDK_RELEASES}" | sed -n 's/.*"browser_download_url": *"\([^"]*\)".*/\1/p')
  fi

  # ── Presence check ───────────────────────────────────────────────────────────
  if ! ls OpenJDK*-jdk-sources*.tar.gz > /dev/null 2>&1; then
    print_error "Source tarball not found in staging for tag ${TAG}"
    _PHASE_SOURCES="FAIL"
    write_platform_results "source" "global" "FAIL"
    return
  fi

  local src_archive
  src_archive="$(ls OpenJDK*-jdk-sources*.tar.gz | head -1)"

  # ── Step 2: GPG signature ────────────────────────────────────────────────────
  print_verbose "IVT : GPG-verifying ${src_archive}"
  if ! gpg -q --verify "${src_archive}.sig" "${src_archive}" 2>/dev/null; then
    print_error "GPG signature verification failed for ${src_archive}"
    RC=2
    src_failures=$(( src_failures + 1 ))
  else
    print_pass "GPG sig: $(basename "${src_archive}")"
  fi

  # ── Step 3: SHA256 checksum ──────────────────────────────────────────────────
  if ! sha256sum -c --quiet "${src_archive}.sha256.txt" 2>/dev/null; then
    print_error "SHA256 checksum failed for ${src_archive}"
    RC=3
    src_failures=$(( src_failures + 1 ))
  else
    print_pass "SHA256:  $(basename "${src_archive}")"
  fi

  # ── Step 4: archive extractability ──────────────────────────────────────────
  print_verbose "IVT : Checking extractability of ${src_archive}"
  if ! tar tfz "${src_archive}" > /dev/null 2>&1; then
    print_error "Failed to verify that ${src_archive} can be extracted"
    RC=4
    src_failures=$(( src_failures + 1 ))
  else
    # ── Step 5: file count ───────────────────────────────────────────────────
    local file_count
    file_count=$(tar tfz "${src_archive}" | wc -l)
    if [ "${file_count}" -lt 45000 ]; then
      print_error "Fewer than 45000 files in source archive ${src_archive} (found ${file_count})"
      RC=4
      src_failures=$(( src_failures + 1 ))
    else
      print_pass "Source archive file count (${file_count} entries): $(basename "${src_archive}")"
    fi

    # ── Step 6: top-level directory structure ────────────────────────────────
    # Required directories vary by JDK major version.
    # Update this case statement when JDK layouts change.
    # JDK 8 uses the old "forest" layout: top-level subrepos (hotspot/, jdk/,
    # langtools/, etc.) with no top-level src/ directory.
    # JDK 11+ consolidated into a single repo with src/ make/ test/ at the top level.
    local _required_dirs
    case "${MAJOR_VERSION}" in
      8)    _required_dirs="hotspot/ jdk/ make/ test/" ;;
      *)    _required_dirs="src/ make/ test/" ;;
    esac

    # Write the listing to a temp file to avoid shell variable size limits
    # (the source tarball contains ~85k+ entries; loading into a variable
    # and echo-ing through a pipe silently truncates on some systems).
    local _listing_file _dir_failures=0
    _listing_file="$(mktemp)"
    tar tf "${src_archive}" > "${_listing_file}"
    for _req_dir in ${_required_dirs}; do
      if ! grep -q "^[^/]*/${_req_dir}" "${_listing_file}"; then
        print_error "Expected top-level directory '${_req_dir}' not found in ${src_archive}"
        RC=4
        _dir_failures=$(( _dir_failures + 1 ))
      else
        print_pass "Directory '${_req_dir}' present in $(basename "${src_archive}")"
      fi
    done
    rm -f "${_listing_file}"
    src_failures=$(( src_failures + _dir_failures ))
  fi

  # ── Result ───────────────────────────────────────────────────────────────────
  if [ "${src_failures}" -eq 0 ]; then
    print_info "Source tarball validation complete — all checks passed"
    _PHASE_SOURCES="PASS"
  else
    print_info "Source tarball validation complete — ${src_failures} failure(s)"
    _PHASE_SOURCES="FAIL"
  fi
  write_platform_results "source" "global" "${_PHASE_SOURCES}"
}



########################################################################################################################
#
# Determine the OS from the running kernel.
# Sets OS to one of: linux, alpine-linux, mac, windows, aix
#
########################################################################################################################
determine_os() {
  local kernel

  kernel="$(uname -s)"
  case "${kernel}" in
      Linux*)     OS=linux
                  # Alpine Linux uses musl libc and needs distinct handling
                  if [ -f /etc/alpine-release ]; then OS=alpine-linux; fi
                  ;;
      Darwin*)    OS=mac;;
      CYGWIN*|MINGW*|MSYS*) OS=windows;;
      AIX*)       OS=aix;;
      *)          echo "Unknown kernel '$kernel'" && exit 1
  esac
}

########################################################################################################################
#
# Determine the ARCH from the running machine.
# Sets ARCH to the Temurin tarball arch token for the current machine.
#
########################################################################################################################
determine_arch() {
  local machine

  machine="$(uname -m)"
  case "${machine}" in
      x86_64)     ARCH=x64;;
      aarch64|arm64) ARCH=aarch64;;   # arm64 is the macOS Apple Silicon spelling
      ppc64le)    ARCH=ppc64le;;
      s390x)      ARCH=s390x;;
      armv7l)     ARCH=arm;;
      riscv64)    ARCH=riscv64;;
      ppc64)      ARCH=ppc64;;
      *)
          # AIX: uname -m returns the machine serial/model (e.g. 00FB3A2C4C00).
          # Fall back to uname -p which returns the processor type (powerpc).
          local proc
          proc="$(uname -p 2>/dev/null || true)"
          case "${proc}" in
              powerpc) ARCH=ppc64;;
              *) echo "Unknown machine '${machine}' (uname -p: '${proc}')" && exit 1;;
          esac
          ;;
  esac
}

########################################################################################################################
#
# Return the Temurin arch token for the current machine's uname -m output.
# Used by verify_working_executables to check whether -A overrides the native arch.
#
########################################################################################################################
native_arch() {
  local machine proc
  machine="$(uname -m)"
  case "${machine}" in
      x86_64)        echo "x64";;
      aarch64|arm64) echo "aarch64";;
      ppc64le)       echo "ppc64le";;
      s390x)         echo "s390x";;
      armv7l)        echo "arm";;
      riscv64)       echo "riscv64";;
      ppc64)         echo "ppc64";;
      *)
          # AIX fallback: uname -m is a machine serial; use uname -p
          proc="$(uname -p 2>/dev/null || true)"
          case "${proc}" in
              powerpc) echo "ppc64";;
              *)       echo "unknown";;
          esac
          ;;
  esac
}

########################################################################################################################
#
# Return the Temurin OS token for the current machine's uname -s output.
# Used by verify_working_executables to check whether -O overrides the native OS.
#
########################################################################################################################
native_os() {
  local kernel
  kernel="$(uname -s)"
  case "${kernel}" in
      Linux*)                if [ -f /etc/alpine-release ]; then echo "alpine-linux"; else echo "linux"; fi;;
      Darwin*)               echo "mac";;
      CYGWIN*|MINGW*|MSYS*)  echo "windows";;
      AIX*)                  echo "aix";;
      *)                     echo "unknown";;
  esac
}

########################################################################################################################
#
# Verify that the release matching the OS/ARCH on which this script is running can execute 'java -version'.
# Skips the execution step when ARCH/OS overrides do not match the native machine (cross-arch invocation).
#
########################################################################################################################
verify_working_executables() {
  print_section "Binary Executable Checks (${ARCH}/${OS})"

  if [ "${OS}" = "windows" ]; then
    # Windows binaries are distributed as .zip archives (no .tar.gz JRE).
    # Verification is handled by verify_windows_compiler_version() instead.
    return
  fi

  if ! ls OpenJDK*-jre_"${ARCH}"_"${OS}"_hotspot_*.tar.gz > /dev/null 2>&1; then
    print_info "Release does not contain a JRE for ${OS}/${ARCH} — skipping local executable checks"
    return
  fi

  # macOS tarballs have an extra two directory levels inside the archive:
  #   Linux/AIX:  jdk-21.0.9+10/bin/java          -> strip 1 component
  #   macOS:      jdk-21.0.9+10/Contents/Home/bin/java -> strip 3 components
  local _strip_components=1
  [ "${OS}" = "mac" ] && _strip_components=3

  # Only execute java -version when running natively for the target arch/os.
  # When -A or -O overrides are in use and do not match the machine, skip execution.
  local _native_arch _native_os
  _native_arch="$(native_arch)"
  _native_os="$(native_os)"
  if [ "${ARCH}" != "${_native_arch}" ] || [ "${OS}" != "${_native_os}" ]; then
    print_info "Skipping java -version: target ${OS}/${ARCH} does not match native ${_native_os}/${_native_arch}"
    # Still extract JDK tarball so that verify_glibc_version / verify_gcc_version can
    # run strings against it (they depend on tarballtest/ being populated).
    cd "${WORKSPACE}/staging/${TAG}" || exit 1
    rm -rf tarballtest && mkdir tarballtest
    tar -C tarballtest --strip-components="${_strip_components}" -xzpf OpenJDK*-jdk_"${ARCH}"_"${OS}"_hotspot_*.tar.gz || exit 3
    return
  fi

  print_info "Running java -version on ${OS}/${ARCH} tarballs"

  cd "${WORKSPACE}/staging/${TAG}" || exit 1

  rm -rf tarballtest && mkdir tarballtest
  tar -C tarballtest --strip-components="${_strip_components}" -xzpf OpenJDK*-jre_"${ARCH}"_"${OS}"_hotspot_*.tar.gz
  print_info "JRE java -version output:"
  tarballtest/bin/java -version || exit 3
  print_pass "JRE java -version"

  rm -rf tarballtest && mkdir tarballtest
  tar -C tarballtest --strip-components="${_strip_components}" -xzpf OpenJDK*-jdk_"${ARCH}"_"${OS}"_hotspot_*.tar.gz
  print_info "JDK java -version output:"
  tarballtest/bin/java -version || exit 3
  print_pass "JDK java -version"
}

########################################################################################################################
#
# Verify that the java binary is glibc-linked by checking for the presence of any
# GLIBC_* versioned symbol in the binary's ELF symbol table.
#
# The GLIBC_2.2.5 sentinel that was previously used only exists in x86-64 glibc builds;
# other architectures (aarch64, ppc64le, s390x, riscv64) use a higher minimum GLIBC
# version (2.17, 2.17, 2.2, 2.27 respectively) and do not carry GLIBC_2.2.5 at all.
# Any GLIBC_* symbol appearing in the binary is sufficient to confirm it is glibc-linked.
#
# The per-arch devkit GLIBC version is recorded in SBOM metadata and validated separately
# by validateSBOMcontent.sh — it does not appear as a readable string in the binary.
#
# Only applicable for glibc Linux. Alpine (musl), macOS, Windows, and AIX are skipped.
#
########################################################################################################################
verify_glibc_version() {
  if ! ls OpenJDK*-jre_"${ARCH}"_"${OS}"_hotspot_*.tar.gz > /dev/null 2>&1; then
    print_verbose "IVT: No .tar.gz JRE found for $OS/$ARCH — skipping GLIBC version check (expected for non-Linux platforms)"
    return
  fi

  # Only glibc Linux uses GLIBC versioned symbols; skip all other platforms
  if [ "${OS}" != "linux" ]; then
    print_verbose "IVT: Skipping GLIBC version check for OS=${OS} (not a glibc Linux build)"
    return
  fi

  # Check for the presence of any GLIBC_* symbol — this confirms glibc linkage
  # regardless of architecture (avoids the x86-64-only GLIBC_2.2.5 assumption).
  local detected_glibc
  detected_glibc=$(strings tarballtest/bin/java | grep "^GLIBC_" | sort -V | head -1)
  print_verbose "IVT: Detected minimum GLIBC symbol: '${detected_glibc}'"
  if [ -z "${detected_glibc}" ]; then
    print_error "No GLIBC_* symbols found in JDK binary — binary may not be glibc-linked (${ARCH}/${OS}/JDK${MAJOR_VERSION})"
    RC=4
  else
    print_pass "GLIBC linked: ${detected_glibc} (${ARCH}/${OS}/JDK${MAJOR_VERSION})"
  fi
}

########################################################################################################################
#
# Verify the compiler toolchain version embedded in the binary.
#
# Covers all supported platforms — mirrors validateSBOMcontent.sh:
#   glibc Linux (all arches):
#     GCC version varies by JDK major (7.5.0 / 10.3.0 / 11.3.0 / 14.2.0),
#     riscv64 always uses GCC 14.2.0.
#   alpine-linux:
#     GCC 10.3.1 from the musl devkit (fixed, regardless of JDK version).
#   aix:
#     XCOFF binaries do not reliably emit compiler version strings via POSIX strings(1);
#     skipped — compiler is validated authoritatively via SBOM content checks.
#   mac:
#     Mach-O binaries store compiler info in sections that macOS BSD strings(1) does not
#     scan by default; skipped — validated via SBOM content checks.
#   windows:
#     MSVC PE binaries do not embed compiler version strings extractable by POSIX
#     strings(1); the Windows compiler version is verified separately by
#     verify_windows_compiler_version() using java.exe -Xinternalversion.
#
########################################################################################################################
verify_compiler_version() {
  if ! ls OpenJDK*-jre_"${ARCH}"_"${OS}"_hotspot_*.tar.gz > /dev/null 2>&1; then
    print_verbose "IVT: No .tar.gz JRE found for $OS/$ARCH — skipping compiler version check (expected for non-Linux platforms)"
    return
  fi

  # Windows PE binaries: POSIX strings(1) cannot reliably extract MSVC version strings
  if [ "${OS}" = "windows" ]; then
    print_verbose "IVT: Skipping compiler version check for OS=${OS} (MSVC strings not extractable by POSIX strings)"
    return
  fi

  # AIX: XCOFF binaries do not reliably yield compiler version strings via POSIX strings(1).
  # Compiler toolchain is validated authoritatively by the central SBOM content checks.
  if [ "${OS}" = "aix" ]; then
    print_info "IVT: Skipping compiler string check for OS=${OS} (XCOFF not reliably scanned by POSIX strings)"
    return
  fi

  # macOS: Mach-O binaries store compiler info in sections that BSD strings(1) does not
  # scan by default.  Compiler is validated via the central SBOM content checks.
  if [ "${OS}" = "mac" ]; then
    print_info "IVT: Skipping compiler string check for OS=${OS} (Mach-O sections not fully scanned by BSD strings)"
    return
  fi

  # GCC-compiled platforms: glibc Linux and Alpine Linux
  local expected_gcc
  if [ "${OS}" = "alpine-linux" ]; then
    # Alpine always uses GCC 10.3.1 from the musl devkit regardless of JDK version
    expected_gcc="10.3.1"
  elif [ "${ARCH}" = "riscv64" ]; then
    # riscv64 always uses GCC 14.2.0 from the Fedora 28 devkit
    expected_gcc="14.2.0"
  else
    # glibc Linux: version varies by JDK major (mirrors validateSBOMcontent.sh lines 62-66)
    # shellcheck disable=SC2166
    [ "${MAJOR_VERSION}" = "8"  -o "${MAJOR_VERSION}" = "11" ] && expected_gcc="7.5.0"
    [ "${MAJOR_VERSION}" = "17" ] && expected_gcc="10.3.0"
    [ "${MAJOR_VERSION}" -ge 20 ] && expected_gcc="11.3.0"
    [ "${MAJOR_VERSION}" -ge 25 ] && expected_gcc="14.2.0"
  fi

  local detected_gcc
  detected_gcc=$(strings tarballtest/bin/java | grep "^GCC:" | head -1)
  print_verbose "IVT: Detected GCC version string: '${detected_gcc}' (expected GCC: (GNU) ${expected_gcc})"
  if ! strings tarballtest/bin/java | grep "^GCC:.*${expected_gcc}" > /dev/null; then
    print_error "GCC version not as expected ${expected_gcc} in JDK binary (${OS}/${ARCH}/JDK${MAJOR_VERSION})"
    RC=4
  else
    print_pass "Compiler: GCC ${expected_gcc} (${OS}/${ARCH}/JDK${MAJOR_VERSION})"
  fi
}

########################################################################################################################
#
# Verify the MSVC compiler version embedded in Windows JDK/JRE binaries by running
# java.exe -Xinternalversion and parsing the MS VC++ field from its output.
#
# Two output formats exist depending on JDK version:
#
#   New format (JDK 17+): colon-separated 4-digit toolset number
#     built on 2024-01-16T00:00:00Z by "admin" with unknown MS VC++:1937
#
#   Old format (JDK 8/11): space-separated X.Y version with VS label
#     built on 2020-10-15T00:00:00Z by "admin" with unknown MS VC++ 16.7 (VS2019)
#     built on 2022-05-05T00:00:00Z by "admin" with unknown MS VC++ 17.7 (VS2022)
#
# The 4-digit toolset number maps to Visual Studio versions:
#   1900–1919 = VS 2015/2017
#   1920–1929 = VS 2019
#   1930+     = VS 2022
#
# The X.Y major version maps to Visual Studio:
#   14.x = VS 2015/2017
#   16.x = VS 2019
#   17.x = VS 2022
#
# All current Temurin Windows releases are expected to be built with VS 2022.
# Both x64 and aarch64 Windows targets are checked.
#
# Only applicable when running natively on Windows (OS=windows).
#
########################################################################################################################
verify_windows_compiler_version() {
  if [ "${OS}" != "windows" ]; then
    return
  fi

  if ! ls OpenJDK*-jre_"${ARCH}"_windows_hotspot_*.zip > /dev/null 2>&1; then
    print_verbose "IVT: Release does not contain a Windows JRE zip for ${ARCH} — skipping Windows compiler check"
    return
  fi

  cd "${WORKSPACE}/staging/${TAG}" || exit 1

  # Extract the JRE zip into a temporary directory.
  # Windows zip layout: jdk-21.0.9+10/bin/java.exe -> strip 1 path component.
  rm -rf tarballtest && mkdir tarballtest
  # unzip does not have a --strip-components equivalent; extract then move bin/ up.
  if ! unzip -q OpenJDK*-jre_"${ARCH}"_windows_hotspot_*.zip -d tarballtest_raw; then
    print_error "Failed to extract Windows JRE zip for ${ARCH} — cannot run compiler check"
    RC=4
    return
  fi
  # Move the nested bin/ directory to a predictable location.
  local _jre_dir
  _jre_dir="$(ls -d tarballtest_raw/*/)" || true
  mv "${_jre_dir}"/* tarballtest/ 2>/dev/null || mv tarballtest_raw/*/* tarballtest/ 2>/dev/null || true
  rm -rf tarballtest_raw

  if [ ! -x tarballtest/bin/java.exe ]; then
    print_error "java.exe not found after extracting Windows JRE zip for ${ARCH}"
    RC=4
    rm -rf tarballtest
    return
  fi

  print_info "Running java.exe -Xinternalversion on Windows/${ARCH} JRE"
  local _internalversion
  # -Xinternalversion output goes to stderr
  _internalversion="$(tarballtest/bin/java.exe -Xinternalversion 2>&1 || true)"
  print_verbose "IVT: java.exe -Xinternalversion output: ${_internalversion}"

  local _msvc_line
  _msvc_line="$(echo "${_internalversion}" | grep 'MS VC++')"

  # New format (JDK 17+): "MS VC++:NNNN" — colon-separated 4-digit toolset number.
  if echo "${_msvc_line}" | grep -q 'MS VC++:[0-9]'; then
    local _msvc_num
    _msvc_num="${_msvc_line##*MS VC++:}"
    _msvc_num="${_msvc_num%%[^0-9]*}"
    print_verbose "IVT: Detected MS VC++ toolset number (new format): ${_msvc_num}"
    if [ "${_msvc_num}" -lt 1930 ]; then
      print_error "Windows binary built with MS VC++:${_msvc_num} — expected Visual Studio 2022 (toolset >= 1930) (${ARCH}/windows/JDK${MAJOR_VERSION})"
      RC=4
    else
      print_pass "Windows compiler: MS VC++:${_msvc_num} (Visual Studio 2022) (${ARCH}/windows/JDK${MAJOR_VERSION})"
    fi

  # Old format (JDK 8/11): "MS VC++ X.Y (VSLabel)" — space-separated X.Y version.
  elif echo "${_msvc_line}" | grep -q 'MS VC++ [0-9]'; then
    local _msvc_major
    _msvc_major="${_msvc_line##*MS VC++ }"
    _msvc_major="${_msvc_major%%.*}"
    print_verbose "IVT: Detected MS VC++ major version (old format): ${_msvc_major}"
    # Major version 17 = VS 2022, 16 = VS 2019, 14 = VS 2015/2017
    if [ "${_msvc_major}" -lt 17 ]; then
      print_error "Windows binary built with MS VC++ ${_msvc_major}.x — expected Visual Studio 2022 (major version >= 17) (${ARCH}/windows/JDK${MAJOR_VERSION})"
      RC=4
    else
      print_pass "Windows compiler: MS VC++ ${_msvc_major}.x (Visual Studio 2022) (${ARCH}/windows/JDK${MAJOR_VERSION})"
    fi

  else
    print_error "MS VC++ version not found in java.exe -Xinternalversion output (${ARCH}/windows/JDK${MAJOR_VERSION})"
    RC=4
  fi

  rm -rf tarballtest
}

##########################################################################################################################
#
# Verify SBOM content using validateSBOM.sh (which uses validateSBOMcontent.sh and the cyclonedx cli tool).
#
# The third argument to validateSBOM.sh is the expected SCM ref used to verify the
# temurin-build and OpenJDK source SHAs embedded in the SBOM. For GA releases this is
# the tag with _adopt suffix (e.g. jdk-21.0.3+9_adopt). For EA beta builds there is no
# such tag, so an empty string is passed to skip the SCM ref check in validateSBOMcontent.sh.
#
##########################################################################################################################
verify_sboms() {
  local sbom scm_ref sbom_count=0 sbom_failures=0 sbom_log

  print_section "SBOM Validation"

  cd "${WORKSPACE}/staging/${TAG}" || exit 1

  # EA beta tags (jdkXXu-DATE-beta) do not have a corresponding _adopt tag in temurin-build;
  # pass an empty SCM ref so validateSBOMcontent.sh skips the SHA verification step.
  if echo "${TAG}" | grep "^jdk${MAJOR_VERSION}u-.*-beta" > /dev/null; then
    scm_ref=""
  else
    scm_ref="${TAG}_adopt"
  fi

  sbom_log="${WORKSPACE}/staging/${TAG}/.sbom_validate.log"

  # shellcheck disable=SC2010
  for sbom in $(ls -1 OpenJDK*-sbom*json | grep -v metadata); do
    print_info "Validating SBOM: $(basename "${sbom}")"
    local _sbom_ok=true
    # Invoke validateSBOM.sh under bash rather than the system sh.  On exotic nodes
    # (s390x, AIX) the login sh resets PATH to /usr/bin:/bin and loses /usr/local/bin
    # where jq is installed.  bash inherits the full login PATH and passes it through
    # to the validateSBOMcontent.sh subprocess spawned by validateSBOM.sh via `sh`.
    if bash "${TOOLING_DIR}/validateSBOM.sh" "${MAJOR_VERSION}" "${scm_ref}" "${WORKSPACE}/staging/${TAG}/${sbom}" \
        > "${sbom_log}" 2>&1; then
      print_pass "SBOM: $(basename "${sbom}")"
    else
      print_error "SBOM validation failed for $(basename "${sbom}")"
      # Emit the validator's output so the failure is diagnosable in Jenkins
      cat "${sbom_log}"
      sbom_failures=$(( sbom_failures + 1 ))
      RC=6
      _sbom_ok=false
    fi
    sbom_count=$(( sbom_count + 1 ))

    # Extract arch/os from the SBOM filename using the same pattern as GPG tracking.
    local _sbom_base _sbom_arch_os
    _sbom_base="$(basename "${sbom}")"
    if _sbom_arch_os="$(echo "${_sbom_base}" | sed -n 's/^OpenJDK[0-9]*[A-Z]*-[^_]*_\([^_]*\)_\([^_]*\)_.*/\1\/\2/p')"; then
      if [ -n "${_sbom_arch_os}" ]; then
        if [ "${_sbom_ok}" = "false" ]; then
          _SBOM_PER_ARCH="$(echo "${_SBOM_PER_ARCH}" | grep -v "^${_sbom_arch_os} " || true)"
          if ! echo "${_SBOM_PER_ARCH}" | grep -q "^${_sbom_arch_os} FAIL"; then
            _SBOM_PER_ARCH="${_SBOM_PER_ARCH}
${_sbom_arch_os} FAIL"
          fi
        else
          if ! echo "${_SBOM_PER_ARCH}" | grep -q "^${_sbom_arch_os} "; then
            _SBOM_PER_ARCH="${_SBOM_PER_ARCH}
${_sbom_arch_os} PASS"
          fi
        fi
      fi
    fi
  done
  rm -f "${sbom_log}"

  _SBOM_PER_ARCH="$(echo "${_SBOM_PER_ARCH}" | sed '/^[[:space:]]*$/d' | sort)"

  if [ "${sbom_failures}" -eq 0 ]; then
    print_info "SBOM validation complete — ${sbom_count} SBOM(s) checked, all passed"
    _PHASE_SBOM="PASS"
  else
    print_info "SBOM validation complete — ${sbom_count} SBOM(s) checked, ${sbom_failures} failure(s)"
    _PHASE_SBOM="FAIL"
  fi
}

##########################################################################################################################
#
# Write per-platform result files into the staging results directory.
# Called by the central GPG-only stage (for GPG+archive results) and the central
# SBOM-only stage (for SBOM results).  Each file contains a single token: PASS or FAIL.
# The arch-node stages read these files to populate their consolidated summary tables.
#
# param 1: phase — "gpg" | "archive" | "sbom"
# param 2: arch/os string (as used in _GPG_PER_ARCH / _SBOM_PER_ARCH, e.g. "x64/linux")
# param 3: result — "PASS" | "FAIL"
#
##########################################################################################################################
write_platform_results() {
  local phase="$1" arch_os="$2" result="$3"
  local results_dir="${WORKSPACE}/staging/${TAG}/.results"
  mkdir -p "${results_dir}"
  # Convert "arch/os" -> "arch_os" for a safe filename
  local safe_key
  safe_key="$(echo "${arch_os}" | tr '/' '_')"
  printf '%s\n' "${result}" > "${results_dir}/${phase}_${safe_key}.result"
}

##########################################################################################################################
#
# Flush per-arch result entries in _GPG_PER_ARCH and _SBOM_PER_ARCH to result files.
# Called once, after the accumulator has been fully populated.
#
# param 1: phase — "gpg" | "archive" | "sbom"
# param 2: accumulator variable name (passed by value, newline-separated "arch/os PASS|FAIL" lines)
#
##########################################################################################################################
flush_results_to_disk() {
  local phase="$1" accumulator="$2"
  local _line _plat _result
  while IFS= read -r _line; do
    [ -z "${_line}" ] && continue
    _plat="${_line% *}"
    _result="${_line##* }"
    write_platform_results "${phase}" "${_plat}" "${_result}"
  done <<< "${accumulator}"
}

##########################################################################################################################
#
# Read per-platform result files written by the central stages and populate the
# _PHASE_SIGNATURES, _PHASE_ARCHIVES, and _PHASE_SBOM variables for the current ARCH/OS.
# Called in arch-node mode (-G / -C) before print_summary so the final summary table
# contains results from all three stages for this platform.
#
##########################################################################################################################
read_platform_results() {
  local results_dir="${WORKSPACE}/staging/${TAG}/.results"
  local safe_key gpg_file arc_file sbom_file

  safe_key="$(echo "${ARCH}/${OS}" | tr '/' '_')"
  gpg_file="${results_dir}/gpg_${safe_key}.result"
  arc_file="${results_dir}/archive_${safe_key}.result"
  sbom_file="${results_dir}/sbom_${safe_key}.result"

  if [ -f "${gpg_file}" ]; then
    _PHASE_SIGNATURES="$(cat "${gpg_file}")"
    print_info "Loaded GPG result for ${ARCH}/${OS} from central stage: ${_PHASE_SIGNATURES}"
  else
    print_info "No central GPG result file found for ${ARCH}/${OS} — marking as unavailable"
    _PHASE_SIGNATURES="N/A"
  fi

  if [ -f "${arc_file}" ]; then
    _PHASE_ARCHIVES="$(cat "${arc_file}")"
    print_info "Loaded archive result for ${ARCH}/${OS} from central stage: ${_PHASE_ARCHIVES}"
  else
    print_info "No central archive result file found for ${ARCH}/${OS} — marking as unavailable"
    _PHASE_ARCHIVES="N/A"
  fi

  if [ -f "${sbom_file}" ]; then
    _PHASE_SBOM="$(cat "${sbom_file}")"
    print_info "Loaded SBOM result for ${ARCH}/${OS} from central stage: ${_PHASE_SBOM}"
  else
    print_info "No central SBOM result file found for ${ARCH}/${OS} — marking as unavailable"
    _PHASE_SBOM="N/A"
  fi
}

##########################################################################################################################
#
# Print a final summary table of all validation phases.
# Always printed (not verbose-gated) so Jenkins operators can confirm result at a glance.
#
# In arch-node mode (-G -C) the table consolidates results from all three stages:
#   GPG/archive results loaded from staging (written by the central GPG stage)
#   SBOM result loaded from staging (written by the central SBOM stage)
#   Binary checks performed locally on this node
#
##########################################################################################################################
print_summary() {
  local label
  if [ "${GPG_ONLY}" = "true" ]; then
    label="${TAG}"
  elif [ "${SBOM_ONLY}" = "true" ]; then
    label="${TAG}"
  elif [ "${SOURCES_ONLY}" = "true" ]; then
    label="${TAG}"
  else
    label="${TAG} (${ARCH:-?}/${OS:-?})"
  fi
  local overall

  if [ "${RC}" -eq 0 ]; then
    overall="${GREEN}${BOLD}PASS${NORMAL}"
  else
    overall="${RED}${BOLD}FAIL${NORMAL}"
  fi

  _phase_line() {
    local name="$1" result="$2"
    case "${result}" in
      PASS) printf "  %-22s: ${GREEN}%s${NORMAL}\n" "${name}" "${result}";;
      FAIL) printf "  %-22s: ${RED}%s${NORMAL}\n"   "${name}" "${result}";;
      SKIP) printf "  %-22s: ${YELLOW}%s${NORMAL}\n" "${name}" "${result}";;
      N/A)  printf "  %-22s: %s\n"                   "${name}" "N/A (central result unavailable)";;
      *)    printf "  %-22s: %s\n"                   "${name}" "${result}";;
    esac
  }

  echo ""
  echo "${CYAN}${BOLD}$(_log_prefix) ============================================================${NORMAL}"
  echo "${CYAN}${BOLD}$(_log_prefix)  Validation Summary: ${label}${NORMAL}"
  echo "${CYAN}${BOLD}$(_log_prefix) ============================================================${NORMAL}"

  if [ "${SKIP_GPG}" = "true" ]; then
    # Arch-node mode: show only what this node actually ran (binary checks).
    # GPG/archive/SBOM results are surfaced in Stage 1 summaries and the
    # Stage 3 cross-platform table — no need to repeat them here.
    if [ "${SKIP_BINARY_CHECKS}" = "true" ]; then
      _phase_line "Binary checks"    "SKIP (-b)"
    else
      _phase_line "Binary checks"    "${_PHASE_BINARIES}"
    fi
  elif [ "${GPG_ONLY}" = "true" ]; then
    # Central GPG stage: only show what this stage actually ran
    _phase_line "Download"           "${_PHASE_DOWNLOAD}"
    _phase_line "GPG key import"     "${_PHASE_GPG_IMPORT}"
    _phase_line "GPG & SHA256 sigs"  "${_PHASE_SIGNATURES}"
    # Per-arch GPG breakdown
    if [ -n "${_GPG_PER_ARCH}" ]; then
      while IFS= read -r _gpg_line; do
        [ -z "${_gpg_line}" ] && continue
        local _gpg_plat _gpg_result
        _gpg_plat="${_gpg_line% *}"
        _gpg_result="${_gpg_line##* }"
        _phase_line "  GPG ${_gpg_plat}" "${_gpg_result}"
      done <<< "${_GPG_PER_ARCH}"
    fi
    _phase_line "Archive integrity"  "${_PHASE_ARCHIVES}"
  elif [ "${SBOM_ONLY}" = "true" ]; then
    # Central SBOM stage: only show what this stage actually ran
    _phase_line "SBOM validation"    "${_PHASE_SBOM}"
    # Per-arch SBOM breakdown
    if [ -n "${_SBOM_PER_ARCH}" ]; then
      while IFS= read -r _sbom_line; do
        [ -z "${_sbom_line}" ] && continue
        local _sbom_plat _sbom_result
        _sbom_plat="${_sbom_line% *}"
        _sbom_result="${_sbom_line##* }"
        _phase_line "  SBOM ${_sbom_plat}" "${_sbom_result}"
      done <<< "${_SBOM_PER_ARCH}"
    fi
  elif [ "${SOURCES_ONLY}" = "true" ]; then
    # Central sources stage: only show what this stage actually ran
    _phase_line "Source validation"  "${_PHASE_SOURCES}"
  else
    # Default full-run (no mode flag): show all phases
    _phase_line "Download"           "${_PHASE_DOWNLOAD}"
    _phase_line "GPG key import"     "${_PHASE_GPG_IMPORT}"
    _phase_line "GPG & SHA256 sigs"  "${_PHASE_SIGNATURES}"
    _phase_line "Archive integrity"  "${_PHASE_ARCHIVES}"
    _phase_line "Source tarball"     "${_PHASE_SOURCES}"
    _phase_line "SBOM validation"    "${_PHASE_SBOM}"
    _phase_line "Binary checks"      "${_PHASE_BINARIES}"
  fi

  echo "${CYAN}${BOLD}$(_log_prefix) ------------------------------------------------------------${NORMAL}"
  echo "$(_log_prefix) Overall: ${overall} (RC=${RC})"
  echo "${CYAN}${BOLD}$(_log_prefix) ============================================================${NORMAL}"
  echo ""
}


##########################################################################################################################
#
# Main function.
#
##########################################################################################################################

if [ "${TEST_MODE:-false}" != "true" ]; then

parse_options "$@"

# enable ansi logging if enabled
[ "${USE_ANSI}" = "true" ] && init_ansi_logging

if [ -z "${TAG}" ]; then
   print_error "TAG undefined - aborting"
   exit 1
fi

extract_major_version

if [ -z "${MAJOR_VERSION}" ]; then
   print_error "MAJOR_VERSION undefined - aborting"
   exit 1
fi

# Apply any arch/os overrides supplied via -A / -O flags before the startup banner
# so the prefix and context line reflect the intended target.
determine_os
determine_arch
[ -n "${OVERRIDE_ARCH}" ] && ARCH="${OVERRIDE_ARCH}"
[ -n "${OVERRIDE_OS}" ]   && OS="${OVERRIDE_OS}"

# Print structured context in verbose mode so each parallel stage is identifiable
print_verbose "IVT: Release Download Validation starting"
print_verbose "IVT: tag=${TAG}  version=${MAJOR_VERSION}  arch=${ARCH}  os=${OS}"
print_verbose "IVT: Checking https://github.com/adoptium/temurin${MAJOR_VERSION}-binaries/releases/tag/${TAG}"

JDK_RELEASES=$(download_jdk_releases)

if [ "${SKIP_DOWNLOADING}" = "false" ] && [ "${SBOM_ONLY}" = "false" ] && [ "${SOURCES_ONLY}" = "false" ]; then
  print_section "Downloading Release Artifacts"

  if [ "${KEEP_STAGING}" = "false" ] && [ "${SKIP_GPG}" = "false" ]; then
    # Central-node mode: wipe the full staging area before a fresh download.
    # In arch-node mode (SKIP_GPG=true) the workspace is already clean (prior
    # run's deleteDir()) and the Jenkinsfile has just unstashed per-platform
    # result files into staging/${TAG}/.results/ — we must not delete them.
    rm -rf "${WORKSPACE}/staging"
  fi
  mkdir -p "${WORKSPACE}/staging/${TAG}"

  download_release_files "${JDK_RELEASES}"
else
  if [ "${SBOM_ONLY}" = "true" ]; then
    print_info "Skipping download (-c flag set: using staging area from GPG stage)"
  elif [ "${SOURCES_ONLY}" = "true" ]; then
    print_info "Skipping full download (-r flag set: source tarball download handled by verify_source_tarball)"
  else
    print_info "Skipping download (-s flag set)"
  fi
  _PHASE_DOWNLOAD="SKIP"
fi

if [ "$VERBOSE" = "true" ]; then
  ls -l "${WORKSPACE}"/staging/"${TAG}"/OpenJDK* 2>/dev/null || true
fi

# In arch-node mode, a download count of zero means the release has no files for this
# arch/os (platform not in this release) or the agent failed to reach the download URL.
# Either way there is nothing to check — fail immediately rather than silently reporting
# PASS on checks that never ran.
RC=0
if [ "${SKIP_DOWNLOADING}" = "false" ] && [ "${SKIP_GPG}" = "true" ] && [ "${_DOWNLOAD_COUNT}" -eq 0 ]; then
  print_error "No files downloaded for ${ARCH}/${OS} — this is likely a transient download or network failure on the agent."
  print_error "GPG/SBOM were verified centrally (files exist on GitHub); the stage will be retried automatically."
  _PHASE_DOWNLOAD="FAIL"
  _PHASE_BINARIES="FAIL"
  RC=1
  # Write the result file now so the Summary stage sees FAIL for this platform
  # even though we exit before the normal write_platform_results call at the end.
  write_platform_results "binary" "${ARCH}/${OS}" "${_PHASE_BINARIES}"
  print_summary
  exit ${RC}
fi

# -G (SKIP_GPG): arch-node mode — GPG/archive already verified by the central node.
# -c (SBOM_ONLY): central SBOM-only mode — GPG/archive already done in the -g step.
# Both skip GPG import, signature verification, and archive integrity.
if [ "${SKIP_GPG}" = "true" ]; then
  # Arch-node mode: load per-platform GPG/archive/SBOM results written by central stages
  # so the final summary table is consolidated across all three pipeline stages.
  read_platform_results
elif [ "${SBOM_ONLY}" = "false" ]; then
  print_section "GPG Key Import"
  import_gpg_key

  verify_gpg_signatures
  verify_valid_archives

  # -g: GPG-only mode — download ALL files, verify GPG/SHA/archives, then exit.
  # Flush per-platform result files so arch-node stages can read them for their summaries.
  # Used by the central node; the SBOM stage (-c) and arch nodes (-G) run separately.
  if [ "${GPG_ONLY}" = "true" ]; then
    _PHASE_BINARIES="SKIP"
    _PHASE_SBOM="SKIP"
    # Flush per-platform GPG results (values come from the accumulator).
    flush_results_to_disk "gpg" "${_GPG_PER_ARCH}"
    # Flush archive integrity result: same global value for every platform in the release.
    _arc_line="" _arc_plat=""
    while IFS= read -r _arc_line; do
      [ -z "${_arc_line}" ] && continue
      _arc_plat="${_arc_line% *}"
      write_platform_results "archive" "${_arc_plat}" "${_PHASE_ARCHIVES}"
    done <<< "${_GPG_PER_ARCH}"
    print_summary
    exit ${RC}
  fi
fi

# -c: SBOM-only mode — validate all SBOMs from the central staging area, then exit.
# Flush per-platform SBOM result files so arch-node stages can read them for their summaries.
# Runs on the central node after the GPG stage; arch nodes run with -C to skip SBOM.
if [ "${SBOM_ONLY}" = "true" ]; then
  _PHASE_DOWNLOAD="SKIP"
  _PHASE_GPG_IMPORT="SKIP"
  _PHASE_SIGNATURES="SKIP"
  _PHASE_ARCHIVES="SKIP"
  _PHASE_BINARIES="SKIP"
  verify_sboms
  flush_results_to_disk "sbom" "${_SBOM_PER_ARCH}"
  print_summary
  exit ${RC}
fi

# -r: Sources-only mode — download source tarball + sidecars, run all source checks, then exit.
# Runs on the central node as a dedicated source validation stage after -g and -c.
if [ "${SOURCES_ONLY}" = "true" ]; then
  _PHASE_GPG_IMPORT="SKIP"
  _PHASE_SIGNATURES="SKIP"
  _PHASE_ARCHIVES="SKIP"
  _PHASE_BINARIES="SKIP"
  _PHASE_SBOM="SKIP"
  verify_source_tarball
  print_summary
  exit ${RC}
fi

if [ "${SKIP_BINARY_CHECKS}" = "false" ]; then
  verify_working_executables
  verify_glibc_version
  verify_compiler_version
  verify_windows_compiler_version
  rm -rf tarballtest
  # Only record PASS/FAIL if the binary checks had something to run against.
  # When no JRE exists for this arch/os all three functions return early without
  # touching RC — leave _PHASE_BINARIES as "−" to show nothing was checked.
  # Windows distributes JREs as .zip files; check for those too.
  # Use relative paths (cd first) to avoid WORKSPACE backslash issues on Windows.
  ( cd "${WORKSPACE}/staging/${TAG}" 2>/dev/null && \
    { ls OpenJDK*-jre_"${ARCH}"_"${OS}"_hotspot_*.tar.gz > /dev/null 2>&1 || \
      ls OpenJDK*-jre_"${ARCH}"_"${OS}"_hotspot_*.zip > /dev/null 2>&1; } \
  ) && _jre_present=true || _jre_present=false
  if [ "${_jre_present}" = "true" ]; then
    [ "${RC}" -ne 4 ] && _PHASE_BINARIES="PASS" || _PHASE_BINARIES="FAIL"
  else
    _PHASE_BINARIES="−"
  fi
else
  print_verbose "IVT: Skipping binary string checks (-b flag set)"
  _PHASE_BINARIES="SKIP"
fi

# -C: Skip-SBOM mode — SBOM validation already done centrally by -c stage.
if [ "${SKIP_SBOM}" = "true" ]; then
  _PHASE_SBOM="SKIP"
else
  verify_sboms
fi

# In arch-node mode, write the binary result to disk so the central Summary stage
# can aggregate it into the cross-platform table.
if [ "${SKIP_GPG}" = "true" ]; then
  write_platform_results "binary" "${ARCH}/${OS}" "${_PHASE_BINARIES}"
fi

print_summary

exit ${RC}

fi # end TEST_MODE guard
