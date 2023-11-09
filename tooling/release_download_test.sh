#!/bin/bash
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
VERBOSE=false
KEEP_STAGING=false
SKIP_DOWNLOADING=false
USE_ANSI=false

MAJOR_VERSION=""

SCRIPT_DIR="$( cd "$( dirname "${0}" )" && pwd )"

# shellcheck source=tooling/common_logging.sh
source "$SCRIPT_DIR/common_logging.sh"

usage() {
  local USAGE
  USAGE="
Usage: $(basename "${0}") [OPTIONS] [TAG]

This scripts downloads the specified release from the GitHub temurinXX-binaries and runs validation checks on it.

If no TAG is provided, it is expected that a \$TAG variable is present containing the tag to validate.
If no \$WORKSPACE variable is set, the current working directory will be used as base for the staging area, otherwise
the directory specified in the \$WORKSPACE variable will be used.

Options:
  -k       keep staging area (should only be used for debugging / testing);
  -s       skip downloading of release artifacts (should only be used for debugging / testing)
  -a       enables ansi coloring of output
  -v       enable verbose mode
  -h       show this help
"
  echo "$USAGE"
  exit 1
}

parse_options() {
  local OPTIND opt

  while getopts ":hvksa" opt; do
      case "${opt}" in
          h)   usage;;
          v)   VERBOSE=true;;
          k)   KEEP_STAGING=true;;
          s)   SKIP_DOWNLOADING=true;;
          a)   USE_ANSI=true;;
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
# A utility function to print verbose output.
#
########################################################################################################################
print_verbose() {
  if [ "$VERBOSE" = "true" ]; then
    echo "${BOLD}$(date +%T) : $*${NORMAL}" 1>&2;
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
# Download release information from GitHub for the specified major version.
# return : file containing release information
#
########################################################################################################################
download_jdk_releases() {
  local output_file
  output_file="${WORKSPACE}/jdk${MAJOR_VERSION}.txt"

  if ! curl -sS "https://api.github.com/repos/adoptium/temurin${MAJOR_VERSION}-binaries/releases" > "${output_file}"; then
     print_error "GitHub API call failed - aborting"
     exit 2
  fi

  echo "${output_file}"
}

########################################################################################################################
#
# Download all files of the specified release if required.
# param 1: jdk release info file
#
########################################################################################################################
download_release_files() {
  local jdk_releases filter url

  jdk_releases=$1

  cd "${WORKSPACE}/staging/${TAG}" || exit 1

  # Early access versions are currently in a different format
  if echo "${TAG}" | grep ea-beta; then
    filter="ea_${MAJOR_VERSION}"
  else
    # shellcheck disable=SC2001
    filter=$(echo "/${TAG}/" | sed 's/+/%2B/g')
  fi

  # Parse the releases list for the one we want and download everything in it
  # shellcheck disable=SC2013
  for url in $(grep "${filter}" "${jdk_releases}" | awk -F'"' '/browser_download_url/{print$4}'); do
    # shellcheck disable=SC2046
    print_verbose "IVT : Downloading $(basename "$url")"
    curl -LORsS -C - "$url"
  done
}

########################################################################################################################
#
# Import the Temurin GPG key.
#
########################################################################################################################
import_gpg_key() {
  print_verbose "IVT : Import Temurin GPG key"
  cd "${WORKSPACE}/staging/${TAG}" || exit 1
  umask 022
  export GPGID=3B04D753C9050D9A5D343F39843C48A565F8F04B
  export GNUPGHOME="${WORKSPACE}/.gpg-temp"
  rm -rf "${GNUPGHOME}"
  mkdir -p "${GNUPGHOME}" && chmod og-rwx "${GNUPGHOME}"
  gpg -q --keyserver keyserver.ubuntu.com --recv-keys "${GPGID}" || exit 1
  # shellcheck disable=SC3037
  /bin/echo -e "5\ny\nq\n" | gpg -q --batch --command-fd 0 --expert --edit-key "${GPGID}" trust || exit 1
}

########################################################################################################################
#
# Verify GPG and SHA256 signatures of all archives / json files.
#
########################################################################################################################
verify_gpg_signatures() {
  local A

  print_verbose "IVT : Testing GPG and sha256 signatures of all tar.gz/json files"

  cd "${WORKSPACE}/staging/${TAG}" || exit 1

  # Note: This will run into problems if there are no tar.gz files
  #       e.g. if only windows has been uploaded to the release
  for A in OpenJDK*.tar.gz OpenJDK*.zip *.msi *.pkg *sbom*[0-9].json; do
    print_verbose "IVT : Verifying signature of file ${A}"

    if ! gpg -q --verify "${A}.sig" "${A}"; then
      print_error "GPG signature verification failed for ${A}"
      RC=2
    fi
    if ! grep sbom "${A}" > /dev/null; then # SBOMs don't have sha256.txt files
      if ! sha256sum -c "${A}.sha256.txt"; then
        print_error "SHA256 signature for ${A} is not valid"
        RC=3
      fi
    fi
  done
}

########################################################################################################################
#
# Verify that all archives are valid and have a reasonable amount of files contained in them.
#
########################################################################################################################
verify_valid_archives() {
  local A

  print_verbose "IVT : Verifying that all tarballs/zip files are valid and counting files within them"

  cd "${WORKSPACE}/staging/${TAG}" || exit 1

  for A in OpenJDK*.tar.gz; do
    print_verbose "IVT : Counting files in tarball ${A}"

    if ! tar tfz "${A}" > /dev/null; then
      print_error "Failed to verify that ${A} can be extracted"
      RC=4
    fi
    # NOTE: 40 chosen because the static-libs is in the 40s - maybe switch for different tarballs in the future?
    if [ "$(tar tfz "${A}" | wc -l)" -lt 40 ]; then
      print_error "Less than 40 files in ${A} - that does not seem correct"
      RC=4
    fi
  done

  for A in OpenJDK*.zip; do
    print_verbose "IVT : Counting files in archive ${A}"
    if ! unzip -t "${A}" > /dev/null; then
      print_error "Failed to verify that ${A} can be extracted"
      RC=4
    fi
    if [ "$(unzip -l "${A}" | wc -l)" -lt 44 ]; then
      print_error "Less than 40 files in ${A} - that does not seem correct"
      RC=4
    fi
  done
}

########################################################################################################################
#
# Determine the OS from the running kernel.
#
########################################################################################################################
determine_os() {
  local kernel

  kernel="$(uname -s)"
  case "${kernel}" in
      Linux*)     OS=linux;;
      Darwin*)    OS=mac;;
      CYGWIN*)    OS=windows;;
      *)          echo "Unknown kernel '$kernel'" && exit 1
  esac
}

########################################################################################################################
#
# Determine the ARCH.
#
########################################################################################################################
determine_arch() {
  local machine

  machine="$(uname -m)"
  case "${machine}" in
      x86_64)     ARCH=x64;;
      aarch64)    ARCH=aarch64;;
      ppc64le)    ARCH=ppc64le;;
      *)          echo "Unknown machine '$machine'" && exit 1
  esac
}

########################################################################################################################
#
# Verify that the release matching the OS/ARCH on which this script is running can execute 'java -version'.
#
########################################################################################################################
verify_working_executables() {
  print_verbose "IVT : Running java -version and checking glibc version on ${OS}/${ARCH} tarballs"

  cd "${WORKSPACE}/staging/${TAG}" || exit 1

  rm -rf tarballtest && mkdir tarballtest
  tar -C tarballtest --strip-components=1 -xzpf OpenJDK*-jre_"${ARCH}"_"${OS}"_hotspot_*.tar.gz && tarballtest/bin/java -version || exit 3
  rm -rf tarballtest && mkdir tarballtest
  tar -C tarballtest --strip-components=1 -xzpf OpenJDK*-jdk_"${ARCH}"_"${OS}"_hotspot_*.tar.gz && tarballtest/bin/java -version || exit 3
}

########################################################################################################################
#
# Verify GLIBC version of the binary matching the OS/ARCH on which this script is running.
#
# FIXME: this verification checks whether the binary is linked to a specific GCC version,
#        however, the binaries will contain the minimum required GCC version it needs to be linked
#        to at runtime to work properly.
#        e.g. for OpenJDK21U-jdk_x64_linux_hotspot_21.0.1_12.tar.gz binary GLIBC version
#        will return GLIBC_2.2.5
#
########################################################################################################################
verify_glibc_version() {
  print_verbose "IVT : Detected GLIBC version '$(strings tarballtest/bin/java | grep ^GLIBC)'"
  if ! strings tarballtest/bin/java | grep ^GLIBC_2.17 > /dev/null; then
    print_error "GLIBC version detected in the JDK java executable is not the expected 2.17"
    RC=4
  fi
}

########################################################################################################################
#
# Verify GCC version of the binary matching the OS/ARCH on which this script is running.
#
########################################################################################################################
verify_gcc_version() {
  local expected_gcc

  # shellcheck disable=SC2166
  [ "${MAJOR_VERSION}" = "8" -o "${MAJOR_VERSION}" = "11" ] && expected_gcc=7.5.0
  [ "${MAJOR_VERSION}" = "17" ] && expected_gcc=10.3.0
  [ "${MAJOR_VERSION}" -ge 20 ] && expected_gcc=11.2.0

  if ! strings tarballtest/bin/java | grep "^GCC:.*${expected_gcc}"; then
    print_error "GCC version detected in the JDK java executable is not the expected ${expected_gcc}"
    RC=4
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
  local cyclonedx_checksum cyclonedx_tool

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
      linux-x64)   cyclonedx_checksum="bd26ccba454cc9f12b6860136e1b14117b829a5f27e993607ff526262c5a7ff0";;
      linux-arm64) cyclonedx_checksum="eaac307ca4d7f3ee2a10e5fe898d7ff16c4b8054b10cc210abe6f6d703d17852";;
      osx-x64)     cyclonedx_checksum="83ba4871298db3123dbea23f425cf23316827abcdaded16824b925f1bc69446d";;
      osx-arm64)   cyclonedx_checksum="826c21a2ad146e0542c22fa3bf31f4a744890d89052d597c4461ec6e2302ff2d";;
      win-x64)     cyclonedx_checksum="52d2f00545a5b380b7268ab917ba5eb31a99bcc43dbe25763e4042a9bb44a2b8";;
      win-arm64)   cyclonedx_checksum="0a506f9e734ae3096ad41bbfd5afc0f11583db33b6f1db6dd1f6db7660d2e44e";;
      *)           cyclonedx_checksum="";;
  esac

  cd "${WORKSPACE}/staging/${TAG}" || exit 1

  cyclonedx_tool=""
  if [ -n "${cyclonedx_checksum}" ]; then
    print_verbose "IVT : Downloading CycloneDX CLI binary ..."

    cyclonedx_tool="cyclonedx-${cyclonedx_os}-${cyclonedx_arch}${cyclonedx_suffix}"

    [ ! -r "${cyclonedx_tool}" ] && curl -LOsS https://github.com/CycloneDX/cyclonedx-cli/releases/download/v0.25.0/"${cyclonedx_tool}"
    if [ "$(sha256sum "${cyclonedx_tool}" | cut -d' ' -f1)" != "${cyclonedx_checksum}" ]; then
       print_error "IVT : Cannot verify checksum of CycloneDX CLI binary"
       exit 1
    else
       print_verbose "IVT : Downloaded CycloneDX CLI binary to '${cyclonedx_tool}'"
    fi
    chmod 700 "${cyclonedx_tool}"
  else
    print_warning "No CycloneDX tool available for '${kernel}-${machine}', skipping sbom validation with cyclonedx tool"
  fi

  echo "${cyclonedx_tool}"
}

##########################################################################################################################
#
# Verify SBOM content using cyclonedx cli tool / validateSBOMcontent.sh script.
#
##########################################################################################################################
verify_sboms() {
  local cyclonedx_tool
  local sbom

  cyclonedx_tool=$(download_cyclonedx_tool)

  cd "${WORKSPACE}/staging/${TAG}" || exit 1

  # shellcheck disable=SC2010
  for sbom in $(ls -1 OpenJDK*-sbom*json | grep -v metadata); do
    print_verbose "IVT : Validating ${sbom} ..."

    if [ -n "${cyclonedx_tool}" ]; then
      if ! ./"${cyclonedx_tool}" validate --input-file "${sbom}"; then
        print_error "Failed CycloneDX validation check"
        RC=5
      fi
    fi

    # shellcheck disable=SC2086
    if ! bash "${SCRIPT_DIR}/validateSBOMcontent.sh" "${sbom}" "${MAJOR_VERSION}" "${TAG}"; then
      print_error "Failed checks on ${sbom}"
      RC=6
    fi
  done
}


##########################################################################################################################
#
# Main function.
#
##########################################################################################################################

parse_options "$@"

# enable ansi logging if enabled
[ "${USE_ANSI}" = "true" ] && init_ansi_logging

if [ -z "${TAG}" ]; then
   print_error "TAG undefined - aborting"
   exit 1
fi

print_verbose "IVT : Verifying Tag '${TAG}'"
extract_major_version

print_verbose "IVT : I will be checking https://github.com/adoptium/temurin${MAJOR_VERSION}-binaries/releases/tag/${TAG}"
if [ -z "${MAJOR_VERSION}" ]; then
   print_error "MAJOR_VERSION undefined - aborting"
   exit 1
fi

JDK_RELEASES=$(download_jdk_releases)

if [ "${SKIP_DOWNLOADING}" = "false" ]; then
  print_verbose "IVT : Downloading files from release repository"

  if [ "${KEEP_STAGING}" = "false" ]; then
    rm -rf "${WORKSPACE}/staging"
  fi
  mkdir -p "${WORKSPACE}/staging/${TAG}"

  download_release_files "${JDK_RELEASES}"
fi

[ "$VERBOSE" = "true" ] && ls -l "${WORKSPACE}"/staging/"${TAG}"/OpenJDK*

import_gpg_key

RC=0

verify_gpg_signatures
verify_valid_archives

determine_os
determine_arch

# FIXME: these 3 checks depend on each other, furthermore they verify only the binary that matches
#        the OS/ARCH of the machine running the script.
verify_working_executables
verify_glibc_version
verify_gcc_version
rm -rf tarballtest

verify_sboms

print_verbose "IVT : Finished. Return code = ${RC}"
exit ${RC}
