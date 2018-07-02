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
  jdkDir="$1"

  cd "${jdkDir}" || exit 1

  case "$OPERATING_SYSTEM" in
    "windows")
      echo "Signing Windows release"
      signToolPath=${signToolPath:-"/cygdrive/c/Program Files/Microsoft SDKs/Windows/v7.1/Bin/signtool.exe"}

      # Sign .exe files
      FILES=$(find . -type f -name '*.exe')
      echo "$FILES" | while read -r f;
      do
        echo "Signing ${f}"
        "$signToolPath" sign /f "${SIGNING_CERTIFICATE}" /p "$SIGN_PASSWORD" /fd SHA256 /t http://timestamp.verisign.com/scripts/timstamp.dll "$f";
      done

      # Sign .dll files
      FILES=$(find . -type f -name '*.dll')
      echo "$FILES" | while read -r f;
      do
        "$signToolPath" sign /f "${SIGNING_CERTIFICATE}" /p "$SIGN_PASSWORD" /fd SHA256 /t http://timestamp.verisign.com/scripts/timstamp.dll "$f";
      done
    ;;
    "mac"*)
      echo "Signing OSX release"
      # Login to KeyChain
      # shellcheck disable=SC2046
      # shellcheck disable=SC2006
      security unlock-keychain -p `cat ~/.password`
      # Sign all files with the executable permission bit set.
      FILES=$(find "${TMP_DIR}" -perm +111 -type f || find "${TMP_DIR}" -perm /111 -type f)
      echo "$FILES" | while read -r f; do codesign -s "${SIGNING_CERTIFICATE}" "$f"; done
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
jdkDir=$(ls "${TMP_DIR}" | head -n1)
signRelease "${TMP_DIR}/${jdkDir}"

cd "${TMP_DIR}"
signedArchive=$(createOpenJDKArchive "${jdkDir}")
cd "${WORKSPACE}"
mv "${signedArchive}" "${ARCHIVE}"
rm -rf "${TMP_DIR}"
