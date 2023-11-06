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

STARTDIR="$PWD"
WORKSPACE=${WORKSPACE:-"$PWD"}
VERBOSE=false
KEEP_STAGING=false
SKIP_DOWNLOADING=false

NORMAL=""
BOLD=""
RED=""
YELLOW=""

# check if stdout is a terminal...
if test -t 1; then
  # see if it supports colors...
  ncolors=$(tput colors)

  if test -n "$ncolors" && test $ncolors -ge 8; then
    NORMAL="$(tput sgr0)"
    BOLD="$(tput bold)"
    RED="$(tput setaf 1)"
    YELLOW="$(tput setaf 3)"
  fi
fi

print_verbose() {
  [ "$VERBOSE" = "true" ] && echo "${BOLD}$(date +%T) : $@${NORMAL}" 1>&2;
}

print_error() {
  echo "${RED}ERROR:${NORMAL} $@" 1>&2; 
}

print_warning() {
  echo "${YELLOW}WARN:${NORMAL} $@" 1>&2; 
}

usage() {
  local USAGE
  USAGE="
Usage: $(basename "${0}") [OPTIONS] TAG

This scripts downloads the specified release from the GitHub temurinXX-binaries and runs validation checks on it.

Options:
  -k             keep staging area
  -s             skip downloading release
  -v             enable verbose mode
  -h             show this help

"
  echo "$USAGE"
  exit 1
}

while getopts ":hvks" opt; do
    case "${opt}" in
        h)
            usage
            ;;
        v)
            VERBOSE=true
            ;;
        k)
            KEEP_STAGING=true
            ;;
        s)
            SKIP_DOWNLOADING=true
            ;;
        "?")
            echo "Unknown option '-$OPTARG'"
            usage
            ;;
        ":")
            echo "No argument value for option '-$OPTARG'"
            usage
            ;;
        *)
            usage
            ;;
    esac
done

shift $((OPTIND-1))

[ "$VERBOSE" = "true" ] && set +x

if [ $# -ne "1" ]; then
    usage
fi

TAG=${@:1:1}

if [ -z "${TAG-}" ]; then
    usage
fi

print_verbose "IVT : Verifying Tag '$TAG'"

##########################################################################################################################
#
# Extract JDK major version from TAG.
#
##########################################################################################################################

if [[ "$TAG" =~ ^jdk8u.* ]]; then
  MAJOR_VERSION=8
elif [[ "$TAG" =~ ^jdk-.* ]]; then
  MAJOR_VERSION=$(echo "$TAG" | cut -d- -f2 | cut -d. -f1 | cut -d\+ -f1)
else
  # Probably a beta with the tag starting jdkXXu
  MAJOR_VERSION=$(echo "$TAG" | cut -d- -f1 | tr -d jdku)
fi

print_verbose "IVT : I will be checking https://github.com/adoptium/temurin${MAJOR_VERSION}-binaries/releases/tag/$TAG"
if [ -z "${MAJOR_VERSION}" ] || [ -z "${TAG}" ]; then
   print_error "MAJOR_VERSION or TAG undefined - aborting"
   exit 1
fi

##########################################################################################################################
#
# Download release information from GitHub for the specified major version.
#
##########################################################################################################################

if ! curl -sS "https://api.github.com/repos/adoptium/temurin${MAJOR_VERSION}-binaries/releases" > "$WORKSPACE/jdk${MAJOR_VERSION}.txt"; then
   print_error "GitHub API call failed - aborting"
   exit 2
fi

##########################################################################################################################
#
# Download all files of the specified release if required.
#
##########################################################################################################################

if [ "$SKIP_DOWNLOADING" = "false" ]; then
  print_verbose "IVT: Downloading files from release repository"

  if [ "$KEEP_STAGING" = "true" ]; then
    mkdir -p staging "staging/$TAG"
  else
    rm -rf "$WORKSPACE/staging"
    mkdir "$WORKSPACE/staging" "$WORKSPACE/staging/$TAG"
  fi

  cd "$WORKSPACE/staging/$TAG" || exit 3
  # Early access versions are currently in a different format
  if echo "$TAG" | grep ea-beta; then
    FILTER="ea_${MAJOR_VERSION}"
  else
    FILTER=$(echo "$TAG" | sed 's/+/%2B/g')
  fi

  # Parse the releases list for the one we want and download everything in it
  # shellcheck disable=SC2013
  for URL in $(grep "$FILTER" "$WORKSPACE/jdk${MAJOR_VERSION}.txt" | awk -F'"' '/browser_download_url/{print$4}'); do
    # shellcheck disable=SC2046
    print_verbose "IVT : Downloading $(basename "$URL")"
    curl -LORsS -C - "$URL"
  done
fi

ls -l "$WORKSPACE/staging/$TAG"

##########################################################################################################################
#
# Import the Temurin GPG key.
#
##########################################################################################################################

print_verbose "IVT : Import Temurin GPG key" 
cd "$WORKSPACE/staging/$TAG" || exit 3
umask 022
export GPGID=3B04D753C9050D9A5D343F39843C48A565F8F04B
export GNUPGHOME="$WORKSPACE/.gpg-temp"
rm -rf "$GNUPGHOME"
mkdir -p "$GNUPGHOME" && chmod og-rwx "$GNUPGHOME"
gpg -q --keyserver keyserver.ubuntu.com --recv-keys "${GPGID}" || exit 1
# shellcheck disable=SC3037
/bin/echo -e "5\ny\nq\n" | gpg -q --batch --command-fd 0 --expert --edit-key "${GPGID}" trust || exit 1

RC=0

##########################################################################################################################
#
# Verify GPG and SHA256 signatures of all archives / json files.
#
##########################################################################################################################

print_verbose "IVT : Testing GPG and sha256 signatures of all tar.gz/json files"
# Note: This will run into problems if there are no tar.gz files
#       e.g. if only windows has been uploaded to the release
for A in OpenJDK*.tar.gz OpenJDK*.zip *.msi *.pkg *sbom*[0-9].json; do
  print_verbose "IVT : Verifying signature of file ${A}"
  
  if ! gpg -q --verify "${A}.sig" "$A"; then
    print_error "GPG signature verification failed for ${A}"
    RC=2
  fi
  if ! grep sbom "$A" > /dev/null; then # SBOMs don't have sha256.txt files
    if ! sha256sum -c "${A}.sha256.txt"; then
      print_error "SHA256 signature for ${A} is not valid"
      RC=3
    fi
  fi
done

##########################################################################################################################
#
# Verify that all archives are valid and have a reasonable amount of files contained in them.
#
##########################################################################################################################

print_verbose "IVT : Verifying that all tarballs/zip files are valid and counting files within them"
for A in OpenJDK*.tar.gz; do
  print_verbose "IVT : Counting files in tarball ${A}"

  if ! tar tfz "$A" > /dev/null; then
    print_error "Failed to verify that $A can be extracted"
    RC=4
  fi
  # NOTE: 40 chosen because the static-libs is in the 40s - maybe switch for different tarballs in the future?
  if [ "$(tar tfz "$A" | wc -l)" -lt 40 ]; then
    print_error "Less than 40 files in $A - that does not seem correct"
    RC=4
  fi
done

for A in OpenJDK*.zip; do 
  print_verbose "IVT : Counting files in archive ${A}"
  if ! unzip -t "$A" > /dev/null; then
    print_error "Failed to verify that $A can be extracted"
    RC=4
  fi
  if [ "$(unzip -l "$A" | wc -l)" -lt 44 ]; then
    print_error "Less than 40 files in $A - that does not seem correct"
    RC=4
  fi
done

##########################################################################################################################
#
# Verify that the release matching the OS/ARCH on which this script is running can execute 'java -version'.
#
##########################################################################################################################

kernel="$(uname -s)"
case "${kernel}" in
    Linux*)     OS=linux;;
    Darwin*)    OS=mac;;
    CYGWIN*)    OS=windows;;
    *)          echo 'Unknown kernel "$kernel"' && exit 3
esac

machine="$(uname -m)"
case "${machine}" in
    x86_64)     ARCH=x64;;
    aarch64)    ARCH=aarch64;;
    ppc64le)    ARCH=ppc64le;;
    *)          echo 'Unknown machine "$machine"' && exit 3
esac

print_verbose "IVT : Running java -version and checking glibc version on ${OS}/${ARCH} tarballs"

rm -rf tarballtest && mkdir tarballtest
tar -C tarballtest --strip-components=1 -xzpf OpenJDK*-jre_${ARCH}_${OS}_hotspot_*.tar.gz && tarballtest/bin/java -version || exit 3
rm -rf tarballtest && mkdir tarballtest
tar -C tarballtest --strip-components=1 -xzpf OpenJDK*-jdk_${ARCH}_${OS}_hotspot_*.tar.gz && tarballtest/bin/java -version || exit 3

##########################################################################################################################
#
# Verify GLIBC and GCC version of the release matching the OS/ARCH on which this script is running.
# TODO: this should actually not only check the release matching the OS/ARCH but rather test all.
#       I tested the OpenJDK21U-jdk_x64_linux_hotspot_21.0.1_12.tar.gz release and the GLIBC version used to build it is: GLIBC_2.2.5
#       Currently only linux-aarch64 seems to be handled correctly.
##########################################################################################################################

print_verbose "IVT : Detected GLIBC version '$(strings tarballtest/bin/java | grep ^GLIBC)'"
if ! strings tarballtest/bin/java | grep ^GLIBC_2.17 > /dev/null; then
  print_error "GLIBC version detected in the JDK java executable is not the expected 2.17"
  RC=4
fi


# shellcheck disable=SC2166
[ "${MAJOR_VERSION}" = "8" -o "${MAJOR_VERSION}" = "11" ] && EXPECTED_GCC=7.5.0
[ "${MAJOR_VERSION}" = "17" ] && EXPECTED_GCC=10.3.0
[ "${MAJOR_VERSION}" -ge 20 ] && EXPECTED_GCC=11.2.0


if ! strings tarballtest/bin/java | grep "^GCC:.*${EXPECTED_GCC}"; then
  print_error "GCC version detected in the JDK java executable is not the expected $EXPECTED_GCC"
  RC=4
fi
rm -rf tarballtest

##########################################################################################################################
#
# Verify SBOM content using cyclonedx cli tool / validateSBOMcontent script.
#
##########################################################################################################################

CYCLONEDX_SUFFIX=""

case "${kernel}" in
    Linux*)     CYCLONEDX_OS=linux
                ;;
    Darwin*)    CYCLONEDX_OS=osx
                ;;
    CYGWIN*)    CYCLONEDX_OS=win
                CYCLONEDX_SUFFIX=".exe"
                ;;
    *)          echo 'Unknown kernel "$kernel"' && exit 3
esac

case "${machine}" in
    x86_64)     CYCLONEDX_ARCH=x64;;
    aarch64)    CYCLONEDX_ARCH=arm64;;
    *)          CYCLONEDX_ARCH="unknown";;
esac

case "${CYCLONEDX_OS}-${CYCLONEDX_ARCH}" in
    linux-x64)   CYCLONEDX_CHECKSUM="bd26ccba454cc9f12b6860136e1b14117b829a5f27e993607ff526262c5a7ff0";;
    linux-arm64) CYCLONEDX_CHECKSUM="eaac307ca4d7f3ee2a10e5fe898d7ff16c4b8054b10cc210abe6f6d703d17852";;
    osx-x64)     CYCLONEDX_CHECKSUM="83ba4871298db3123dbea23f425cf23316827abcdaded16824b925f1bc69446d";;
    osx-arm64)   CYCLONEDX_CHECKSUM="826c21a2ad146e0542c22fa3bf31f4a744890d89052d597c4461ec6e2302ff2d";;
    win-x64)     CYCLONEDX_CHECKSUM="52d2f00545a5b380b7268ab917ba5eb31a99bcc43dbe25763e4042a9bb44a2b8";;
    win-arm64)   CYCLONEDX_CHECKSUM="0a506f9e734ae3096ad41bbfd5afc0f11583db33b6f1db6dd1f6db7660d2e44e";;
    *)           CYCLONEDX_CHECKSUM="";;
esac

CYCLONEDX_TOOL=""
if [ ! -z "${CYCLONEDX_CHECKSUM}" ]; then
  print_verbose "IVT : Downloading CycloneDX validation tool"

  CYCLONEDX_TOOL="cyclonedx-${CYCLONEDX_OS}-${CYCLONEDX_ARCH}${CYCLONEDX_SUFFIX}"

  [ ! -r "${CYCLONEDX_TOOL}" ] && curl -LOsS https://github.com/CycloneDX/cyclonedx-cli/releases/download/v0.25.0/cyclonedx-${CYCLONEDX_OS}-${CYCLONEDX_ARCH}${CYCLONEDX_SUFFIX}
  if [ "$(sha256sum ${CYCLONEDX_TOOL} | cut -d' ' -f1)" != "${CYCLONEDX_CHECKSUM}" ]; then
     print_error "Cannot verify checksum of cycloneDX CLI binary"
     exit 1
  fi
  chmod 700 cyclonedx-${CYCLONEDX_OS}-*
else
  print_warning "No CycloneDX tool available for '${kernel}-${machine}', skipping sbom validation with cyclonedx tool"
fi

cd "$STARTDIR" || exit 1

# shellcheck disable=SC2010
for SBOM in $(ls -1 "$WORKSPACE"/staging/"$TAG"/OpenJDK*-sbom*json | grep -v metadata); do
  print_verbose "IVT : Validating $SBOM ..."
  
  if [ ! -z "$CYCLONEDX_TOOL" ]; then
    if ! "$WORKSPACE"/staging/"$TAG"/"${CYCLONEDX_TOOL}" validate --input-file "$SBOM"; then
      print_error "Failed CycloneDX validation check"
      RC=5
    fi
  fi
  
  # shellcheck disable=SC2086
  if ! bash "$(dirname $0)/validateSBOMcontent.sh" "$SBOM" "$MAJOR_VERSION" "$TAG"; then
    print_error "Failed checks on $SBOM"
    RC=6
  fi
done

print_verbose "IVT : Finished. Return code = $RC"
exit $RC
