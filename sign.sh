#!/bin/bash

################################################################################
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
################################################################################

set -eu

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# shellcheck source=sbin/common/config_init.sh
source "$SCRIPT_DIR/sbin/common/config_init.sh"

# shellcheck source=sbin/common/constants.sh
source "$SCRIPT_DIR/sbin/common/constants.sh"

# shellcheck source=sbin/common/common.sh
source "$SCRIPT_DIR/sbin/common/common.sh"

ARCHIVE=""
SIGNING_CERTIFICATE=""
WORKSPACE=$(pwd)
TMP_DIR_NAME="tmp"
TMP_DIR="${WORKSPACE}/${TMP_DIR_NAME}/"

checkSignConfiguration() {
  if [[ "${OPERATING_SYSTEM}" == "windows" ]] ; then
    if [ ! -f "${SIGNING_CERTIFICATE}" ]
    then
      echo "Could not find certificate at: ${SIGNING_CERTIFICATE}"
      exit 1
    fi

    if [ -z "${SIGN_PASSWORD+x}" ]
    then
      echo "If signing is enabled on window you must set SIGN_PASSWORD"
      exit 1
    fi
  fi
}

# Sign the built binary
signRelease()
{
  case "$OPERATING_SYSTEM" in
    "windows")
      echo "Signing Windows release"
      signToolPath=${signToolPath:-"/cygdrive/c/Program Files (x86)/Windows Kits/10/bin/10.0.17763.0/x64/signtool.exe"}

      # Sign .exe files
      FILES=$(find . -type f -name '*.exe')
      echo "$FILES" | while read -r f;
      do
        echo "Signing ${f}"
        if ! "$signToolPath" sign /f "${SIGNING_CERTIFICATE}" /p "$SIGN_PASSWORD" /fd SHA256 /t http://timestamp.verisign.com/scripts/timstamp.dll "$f"; then
          echo "RETRYWARNING: Failed to sign ${f} at $(date +%T): Possible timestamp server error - RC $? ... Retrying in 10 seconds"
          sleep 10
          "$signToolPath" sign /f "${SIGNING_CERTIFICATE}" /p "$SIGN_PASSWORD" /fd SHA256 /t http://timestamp.verisign.com/scripts/timstamp.dll "$f"
        fi        
      done

      # Sign .dll files
      FILES=$(find . -type f -name '*.dll')
      echo "$FILES" | while read -r f;
      do
        echo "Signing ${f}"
        if ! "$signToolPath" sign /f "${SIGNING_CERTIFICATE}" /p "$SIGN_PASSWORD" /fd SHA256 /t http://timestamp.verisign.com/scripts/timstamp.dll "$f"; then
          echo "RETRYWARNING: Failed to sign ${f} at $(date +%T): Possible timestamp server error - RC $? ... Retrying in 10 seconds"
          sleep 10
          "$signToolPath" sign /f "${SIGNING_CERTIFICATE}" /p "$SIGN_PASSWORD" /fd SHA256 /t http://timestamp.verisign.com/scripts/timstamp.dll "$f"
        fi
      done
      ;;
    "mac"*)
      # TODO: Remove this completly once https://github.com/AdoptOpenJDK/openjdk-jdk11u/commit/b3250adefed0c1778f38a7e221109ae12e7c421e has been backported to JDK8u
      echo "Signing OSX release"

      # Login to KeyChain
      # shellcheck disable=SC2046
      # shellcheck disable=SC2006
      security unlock-keychain -p `cat ~/.password`

      ENTITLEMENTS="$WORKSPACE/entitlements.plist"
      xattr -cr .
      # Sign all files with the executable permission bit set.
      FILES=$(find "${TMP_DIR}" -perm +111 -type f -o -name '*.dylib'  -type f || find "${TMP_DIR}" -perm /111 -type f -o -name '*.dylib'  -type f)
      echo "$FILES" | while read -r f; do codesign --entitlements "$ENTITLEMENTS" --options runtime --timestamp --sign "Developer ID Application: London Jamocha Community CIC" "$f"; done
      ;;
    *)
      echo "Skipping code signing as it's not supported on $OPERATING_SYSTEM"
      ;;
  esac
}

function parseArguments() {
  parseConfigurationArguments "$@"

  while [[ $# -gt 2 ]] ; do
    shift;
  done

  SIGNING_CERTIFICATE="$1";
  ARCHIVE="$2";
}

function extractArchive {
  rm -rf "${TMP_DIR}" || true
  mkdir "${TMP_DIR}"
  if [[ "${OPERATING_SYSTEM}" == "windows" ]]; then
    unzip "${ARCHIVE}" -d "${TMP_DIR}"
  elif [[ "${OPERATING_SYSTEM}" == "mac" ]]; then
    gunzip -dc "${ARCHIVE}" | tar xf - -C "${TMP_DIR}"
  else
    echo "could not detect archive type"
    exit 1
  fi
}

if [ "${OPERATING_SYSTEM}" != "windows" ] && [ "${OPERATING_SYSTEM}" != "mac" ]; then
  echo "Skipping code signing as it's not supported on ${OPERATING_SYSTEM}"
  exit 0;
fi

configDefaults
parseArguments "$@"
extractArchive

# shellcheck disable=SC2012
jdkDir=$(find "${TMP_DIR}" ! -path "${TMP_DIR}" -type d -exec basename {} \; | head -n1)

cd "${TMP_DIR}/${jdkDir}" || exit 1
signRelease

cd "${TMP_DIR}"
createOpenJDKArchive "${jdkDir}" "OpenJDK"
archiveExtension=$(getArchiveExtension)
signedArchive="${TMP_DIR}/OpenJDK${archiveExtension}"

cd "${WORKSPACE}"
mv "${signedArchive}" "${ARCHIVE}"
rm -rf "${TMP_DIR}"
