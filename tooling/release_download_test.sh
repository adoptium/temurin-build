#!/bin/sh
#
# Adoptium download and SBOM validation utility
# Takes a tagged build as a parameter and downloads it from the
# GitHub temurinXX-binaries and runs validation checks on it
#
# Exit codes:
#   1 - Something fundamentally wrong before we could check anything
#   2 - GPG signature verification failed
#   3 - SHA checksum failed
#   4 - aarch64 detected GCC/GLIBC version not as expected
#   5 - CylconeDX validation checks failed
#   6 - SBOM contents did not meet expectations
# Note that if there are multiple failures the highest will be the exit code
# If there is a non-zero exit code check the output for "ERROR:"
# 
# For future enhancement ideas, see https://github.com/adoptium/temurin-build/issues/3506#issuecomment-1783237963
#
STARTDIR="$PWD"
TAG=${1:-$TAG}
[ -z "$TAG" ] && echo "Usage: $0 TAG" && exit 1
[ "$(uname -m)" != "aarch64" ] && echo "This script is hard coded to be run on Linux/aarch64 - aborting" && exit 1

[ "$VERBOSE" = "true" ] && set +x
if echo "$TAG" | grep jdk8u; then
  MAJOR_VERSION=8
elif echo "$TAG" | grep ^jdk-; then
  MAJOR_VERSION=$(echo "$TAG" | cut -d- -f2 | cut -d. -f1 | cut -d\+ -f1)
else
  # Probably a beta with the tag starting jdkXXu
  MAJOR_VERSION=$(echo "$TAG" | cut -d- -f1 | tr -d jdku)
fi

echo "$(date +%T) : IVT : I will be checking https://github.com/adoptium/temurin${MAJOR_VERSION}-binaries/releases/tag/$TAG"
if [ -z "${MAJOR_VERSION}" ] || [ -z "${TAG}" ]; then
   echo "MAJOR_VERSION or TAG undefined - aborting"
   exit 1
fi

if ! curl -sS "https://api.github.com/repos/adoptium/temurin${MAJOR_VERSION}-binaries/releases" > "$WORKSPACE/jdk${MAJOR_VERSION}.txt"; then
   echo "github API call failed - aborting"
   exit 2
fi

[ "$VERBOSE" = "true" ] && echo "$(date +%T) : IVT: Downloading files from release repository"

# Leaving this "if/fi" commented out as it can be useful if doing standalone
# testing to avoid having to re-download. May be removed in future
#if [ ! -r "staging/$TAG/OpenJDK21U-debugimage_aarch64_mac_hotspot_ea_21-0-35.tar.gz.json" ]; then
  rm -rf staging
  mkdir staging "staging/$TAG"
  cd "staging/$TAG" || exit 3
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
    [ "$VERBOSE" = "true" ] && echo Downloading $(basename "$URL")
    curl -LORsS "$URL"
  done
  
  ls -l "$WORKSPACE/staging/$TAG"
#fi

echo "$(date +%T) : IVT : Import Temurin GPG key" 
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

echo "$(date +%T): IVT : Testing GPG and sha256 signatures of all tar.gz/json files"
# Note: This will run into problems if there are no tar.gz files
#       e.g. if only windows has been uploaded to the release
for A in OpenJDK*.tar.gz OpenJDK*.zip *.msi *.pkg *sbom*[0-9].json; do
  if ! gpg -q --verify "${A}.sig" "$A"; then
    echo "ERROR: GPG signature verification failed for ${A}"
    RC=2
  fi
  if ! grep sbom "$A" > /dev/null; then # SBOMs don't have sha256.txt files
    if ! sha256sum -c "${A}.sha256.txt"; then
      echo "ERROR: SHA256 signature for ${A} is not valid"
      RC=3
    fi
  fi
done

echo "$(date +%T): IVT : Verifying that all tarballs are a valid format and counting files within them"

for A in OpenJDK*.tar.gz; do
  if ! tar tfz "$A" > /dev/null; then
    echo "ERROR: Failed to verify that $A can be extracted"
    RC=4
  fi
  # NOTE: 40 chosen because the static-libs is in the 40s - maybe switch for different tarballs in the future?
  if [ "$(tar tfz "$A" | wc -l)" -lt 40 ]; then
    echo "ERROR: Less than 40 files in $A - that does not seem correct"
    RC=4
  fi
done
for A in OpenJDK*.zip; do 
  if ! unzip -t "$A" > /dev/null; then
    echo "ERROR: Failed to verify that $A can be extracted"
    RC=4
  fi
  if [ "$(unzip -l "$A" | wc -l)" -lt 44 ]; then
    echo "ERROR: Less than 40 files in $A - that does not seem correct"
    RC=4
  fi
done

echo "$(date +%T): IVT : Running java -version and checking glibc version on Linux/aarch64 tarballs"

rm -rf tarballtest && mkdir tarballtest
tar -C tarballtest --strip-components=1 -xzpf OpenJDK*-jre_aarch64_linux_hotspot_*.tar.gz && tarballtest/bin/java -version || exit 3
rm -r tarballtest && mkdir tarballtest
tar -C tarballtest --strip-components=1 -xzpf OpenJDK*-jdk_aarch64_linux_hotspot_*.tar.gz && tarballtest/bin/java -version || exit 3

strings tarballtest/bin/java | grep ^GLIBC
if ! strings tarballtest/bin/java | grep ^GLIBC_2.17 > /dev/null; then
  echo "ERROR: GLIBC version detected in the JDK java executable is not the expected 2.17"
  RC=4
fi

# shellcheck disable=SC2166
[ "${MAJOR_VERSION}" = "8" -o "${MAJOR_VERSION}" = "11" ] && EXPECTED_GCC=7.5
[ "${MAJOR_VERSION}" = "17" ] && EXPECTED_GCC=10.3
[ "${MAJOR_VERSION}" -ge 20 ] && EXPECTED_GCC=11.2
if ! strings tarballtest/bin/java | grep "^GCC:.*${EXPECTED_GCC}"; then
  echo "ERROR: GCC version detected in the JDK java executable is not the expected $EXPECTED_GCC"
  RC=4
fi
rm -r tarballtest

# Also verify SBOM contant matches the above
echo "$(date +%T): IVT : Downloading CycloneDX validation tool"
[ ! -r "cyclonedx-linux-arm64" ] && curl -LOsS https://github.com/CycloneDX/cyclonedx-cli/releases/download/v0.25.0/cyclonedx-linux-arm64
if [ "$(sha256sum cyclonedx-linux-arm64 | cut -d' ' -f1)" != "eaac307ca4d7f3ee2a10e5fe898d7ff16c4b8054b10cc210abe6f6d703d17852" ]; then
   echo "ERROR: Cannot verify checksum of cycloneDX CLI binary"
   exit 1
fi
chmod 700 cyclonedx-linux-*
cd "$STARTDIR" || exit 1

# shellcheck disable=SC2010
for SBOM in $(ls -1 staging/"$TAG"/OpenJDK*-sbom*json | grep -v metadata); do
  echo "$(date +%T) : IVT : Validating $SBOM ..."
  if ! staging/"$TAG"/cyclonedx-linux-arm64 validate --input-file "$SBOM"; then
    echo "ERROR: Failed CycloneDX validation check"
    RC=5
  fi
  # shellcheck disable=SC2086
  if ! bash "$(dirname $0)/validateSBOMcontent.sh" "$SBOM" "$MAJOR_VERSION" "$TAG"; then
    echo "ERROR: Failed checks on $SBOM"
    RC=6
  fi
done

echo "$(date +%T) : IVT : Finished. Return code = $RC"
exit $RC
