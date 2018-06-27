#!/bin/bash

set -eu

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# shellcheck source=sbin/common/config_init.sh
source "$SCRIPT_DIR/sbin/common/config_init.sh"

# shellcheck source=sbin/common/constants.sh
source "$SCRIPT_DIR/sbin/common/constants.sh"

# shellcheck source=sbin/common/common.sh
source "$SCRIPT_DIR/sbin/common/common.sh"

ARCHIVE=""
WORKSPACE=$(pwd)
TMP_DIR="${WORKSPACE}/tmp/"

checkSignConfiguration() {
   if [ "${BUILD_CONFIG[SIGN]}" == "true" ]
   then
      if [[ "${OPERATING_SYSTEM}" == "windows" ]] ; then
        if [ ! -f "${BUILD_CONFIG[CERTIFICATE]}" ]
        then
          echo "Could not find certificate at: ${BUILD_CONFIG[CERTIFICATE]}"
          exit 1
        fi

        if [ -z "${SIGN_PASSWORD+x}" ]
        then
          echo "If signing is enabled on window you must set SIGN_PASSWORD"
          exit 1
        fi
      fi
   fi
}

# Sign the built binary
signRelease()
{
  if [ -z "${BUILD_CONFIG[SIGN]}" ]; then
    case "$OPERATING_SYSTEM" in
      "windows")
        echo "Signing Windows release"
        signToolPath=${signToolPath:-"/cygdrive/c/Program Files/Microsoft SDKs/Windows/v7.1/Bin/signtool.exe"}
        # Sign .exe files
        FILES=$(find "${TMP_DIR}" -type f -name '*.exe')
        echo "$FILES" | while read -r f; do "$signToolPath" sign /f "${BUILD_CONFIG[CERTIFICATE]}" /p "$SIGN_PASSWORD" /fd SHA256 /t http://timestamp.verisign.com/scripts/timstamp.dll "$f"; done
        # Sign .dll files
        FILES=$(find "${TMP_DIR}" -type f -name '*.dll')
        echo "$FILES" | while read -r f; do "$signToolPath" sign /f "${BUILD_CONFIG[CERTIFICATE]}" /p "$SIGN_PASSWORD" /fd SHA256 /t http://timestamp.verisign.com/scripts/timstamp.dll "$f"; done
      ;;
      "mac"*)
        echo "Signing OSX release"
        # Login to KeyChain
        # shellcheck disable=SC2046
        # shellcheck disable=SC2006
        security unlock-keychain -p `cat ~/.password`
        # Sign all files with the executable permission bit set.
        FILES=$(find "${TMP_DIR}" -perm +111 -type f || find "${TMP_DIR}" -perm /111 -type f)
        echo "$FILES" | while read -r f; do codesign -s "${BUILD_CONFIG[CERTIFICATE]}" "$f"; done
      ;;
      *)
        echo "Skipping code signing as it's not supported on BUILD_CONFIG"
      ;;
    esac
  fi
}

function parseArguments() {
    parseConfigurationArguments "$@"

    while [[ $# -gt 1 ]] ; do
      shift;
    done

    ARCHIVE="$1";
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
signRelease
jdkDir=$(ls "${TMP_DIR}" | head -n1)
signedArchive=$(createOpenJDKArchive "${jdkDir}")
mv "${signedArchive}" "${ARCHIVE}"
rm -rf "${TMP_DIR}"
