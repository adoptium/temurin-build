#!/bin/bash
# shellcheck disable=SC1091
# ********************************************************************************
# Copyright (c) 2018 Contributors to the Eclipse Foundation
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

set -e

PLATFORM_SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

## autodetect defaults to improve usability when running this for debugging/testing
## On most platforms "uname -p" matches what the OS name used in the Temurin
## scripts uses, but not on xLinux, Windows or AIX.

if [ -z "$ARCHITECTURE"  ]; then
   ARCHITECTURE=$(uname -p)
   if [ "$OSTYPE" = "cygwin"  ] || [ "${ARCHITECTURE}" = "unknown" ]; then ARCHITECTURE=$(uname -m); fi # Windows / Alpine
   if [ "$ARCHITECTURE" = "x86_64"  ]; then ARCHITECTURE=x64;        fi # Linux/x64
   if [ "$ARCHITECTURE" = "i386"    ]; then ARCHITECTURE=x64;        fi # Solaris/x64 and mac/x64
   if [ "$ARCHITECTURE" = "sparc"   ]; then ARCHITECTURE=sparcv9;    fi # Solaris/SPARC
   if [ "$ARCHITECTURE" = "powerpc" ]; then ARCHITECTURE=ppc64;      fi # AIX
   if [ "$ARCHITECTURE" = "arm"     ]; then ARCHITECTURE=aarch64;    fi # mac/aarch64
   if [ "$ARCHITECTURE" = "armv7l"  ]; then ARCHITECTURE=arm;        fi # Linux/arm32
   echo ARCHITECTURE not defined - assuming "$ARCHITECTURE"
   export ARCHITECTURE
fi

## Temurin uses "windows" instead of "cygwin" for the OS name on Windows
## so needs to be special cased - on everthing else "uname" is valid
if [ -z "$TARGET_OS" ]; then
  TARGET_OS=$(uname)
  if [ "$OSTYPE"    = "cygwin" ]; then TARGET_OS=windows     ; fi
  if [ "$TARGET_OS" = "SunOS"  ]; then TARGET_OS=solaris     ; fi
  if [ "$TARGET_OS" = "Darwin" ]; then TARGET_OS=mac         ; fi
  if [ -r /etc/alpine-release  ]; then TARGET_OS=alpine-linux; fi
  echo TARGET_OS not defined - assuming you want "$TARGET_OS"
  export TARGET_OS
fi

## Allow JAVA_TO_BUILD to be supplied as a parameter to the script
## and if not there or definied in environment, use latest LTS (jdk11u)
if [ -z "$JAVA_TO_BUILD" ]; then
  if [ "$1" != "${1##jdk}" ]; then
    echo Setting JAVA_TO_BUILD to "$1" from the parameter supplied
    export JAVA_TO_BUILD="$1"
  else
    echo JAVA_TO_BUILD not defined - defaulting to jdk11u
    export JAVA_TO_BUILD=jdk11u
  fi
fi

[ -z "$JAVA_TO_BUILD" ] && echo JAVA_TO_BUILD not defined - set to e.g. jdk8u
[ -z "$VARIANT"       ] && echo VARIANT not defined - assuming hotspot && export VARIANT=hotspot
if [ -z "$FILENAME"   ]; then
  if [ "${VARIANT}" = "temurin" ]; then
     # I don't like this - perhaps we should override elsewhere to keep consistency with existing release names
     echo FILENAME not defined - assuming "${JAVA_TO_BUILD}-hotspot.tar.gz" && export FILENAME="${JAVA_TO_BUILD}-hotspot.tar.gz"
  else
     echo FILENAME not defined - assuming "${JAVA_TO_BUILD}-${VARIANT}.tar.gz" && export FILENAME="${JAVA_TO_BUILD}-${VARIANT}.tar.gz"
  fi
fi

# shellcheck source=sbin/common/constants.sh
source "$PLATFORM_SCRIPT_DIR/../sbin/common/constants.sh"

# Check that the given variant is in our list of common variants
# shellcheck disable=SC2086,SC2143
if [ -z "$(echo ${BUILD_VARIANTS} | grep -w ${VARIANT})" ]; then
  echo "[ERROR] ${VARIANT} is not a recognised build variant. Valid Variants = ${BUILD_VARIANTS}"
  exit 1
fi

## Very very build farm specific configuration
export OPERATING_SYSTEM
OPERATING_SYSTEM=$(echo "${TARGET_OS}" | tr '[:upper:]' '[:lower:]')

export JAVA_FEATURE_VERSION
JAVA_FEATURE_VERSION=$(echo "${JAVA_TO_BUILD}" | tr -d "[:alpha:]")

if [ -z "${JAVA_FEATURE_VERSION}" ]
then
    retryCount=1
    retryMax=5
    until [ "$retryCount" -ge "$retryMax" ]
    do
        # Use Adoptium API to get the JDK Head number
        echo "This appears to be JDK Head. Querying the Adoptium API to get the JDK HEAD Number (https://api.adoptium.net/v3/info/available_releases)..."
        JAVA_FEATURE_VERSION=$(curl -q https://api.adoptium.net/v3/info/available_releases | awk '/tip_version/{print$2}')

        # Checks the api request was successful and the return value is a number
        if [ -z "${JAVA_FEATURE_VERSION}" ] || ! [[ "${JAVA_FEATURE_VERSION}" -gt 0 ]]
        then
            echo "RETRYWARNING: Query ${retryCount} failed. Retrying in 30 seconds (max retries = ${retryMax})..."
            retryCount=$((retryCount+1))
            sleep 30s
        else
            echo "JAVA_FEATURE_VERSION FOUND: ${JAVA_FEATURE_VERSION}" && break
        fi
    done

    # Fail build if we still can't find the head number
    if [ -z "${JAVA_FEATURE_VERSION}" ] || ! [[ "${JAVA_FEATURE_VERSION}" -gt 0 ]]
    then
        echo "Failed ${retryCount} times to query or parse the Adoptium api. Dumping headers via curl -v https://api.adoptium.net/v3/info/available_releases and exiting..."
        curl -v https://api.adoptium.net/v3/info/available_releases
        echo curl returned RC $? in make_adopt_build_farm.sh
        exit 1
    fi
fi

echo "BUILD TYPE: "
echo "VERSION: ${JAVA_TO_BUILD}"
echo "ARCHITECTURE ${ARCHITECTURE}"
echo "VARIANT: ${VARIANT}"
echo "OS: ${OPERATING_SYSTEM}"
echo "SCM_REF: ${SCM_REF}"
OPTIONS=""

# shellcheck disable=SC2034
CONFIGURE_ARGS_FOR_ANY_PLATFORM=""
CONFIGURE_ARGS=${CONFIGURE_ARGS:-""}
BUILD_ARGS=${BUILD_ARGS:-""}
VARIANT_ARG=""
MAC_ROSETTA_PREFIX=""

if [ -z "${JDK_BOOT_VERSION}" ]
then
  echo "Detecting boot jdk for: ${JAVA_TO_BUILD}"
  echo "Found build version: ${JAVA_FEATURE_VERSION}"
  JDK_BOOT_VERSION=$(( JAVA_FEATURE_VERSION - 1 ))
  if [ "${JAVA_FEATURE_VERSION}" == "11" ] && [ "${VARIANT}" == "openj9" ]; then
    # OpenJ9 only supports building jdk-11 with jdk-11
    JDK_BOOT_VERSION="11"
  elif [ "${JAVA_FEATURE_VERSION}" == "11" ] && [ "${ARCHITECTURE}" == "riscv64" ]; then
    # RISC-V isn't supported on (and isn't planned to support) anything before JDK 11
    JDK_BOOT_VERSION="11"
  elif [ "${JAVA_FEATURE_VERSION}" == "17" ]; then
    # To support reproducible-builds the jar/jmod --date option is required
    # which is only available in jdk-17 and from jdk-19 so we cannot bootstrap with JDK16
    JDK_BOOT_VERSION="17"
  elif [ "${JAVA_FEATURE_VERSION}" == "21" ] && [ "${ARCHITECTURE}" == "riscv64" ]; then
    # JDK20 has issues. No RVV fix for C910/C920 systems and
    # does not run well in in docker containers
    JDK_BOOT_VERSION="21"
  elif [ "${JAVA_FEATURE_VERSION}" == "19" ]; then
    JDK_BOOT_VERSION="19"
  fi
fi
echo "Required boot JDK version: ${JDK_BOOT_VERSION}"

# export for platform specific scripts
export JDK_BOOT_VERSION

# shellcheck source=build-farm/set-platform-specific-configurations.sh
source "${PLATFORM_SCRIPT_DIR}/set-platform-specific-configurations.sh"

# Adding the externally-supplied CONFIGURE_ARGS last, so any user-supplied arguments have priority.
CONFIGURE_ARGS_FOR_ANY_PLATFORM="${CONFIGURE_ARGS_FOR_ANY_PLATFORM} ${CONFIGURE_ARGS}"

case "${JDK_BOOT_VERSION}" in
      "7")    export JDK_BOOT_DIR="${JDK_BOOT_DIR:-$JDK7_BOOT_DIR}";;
      "8")    export JDK_BOOT_DIR="${JDK_BOOT_DIR:-$JDK8_BOOT_DIR}";;
      "9")    export JDK_BOOT_DIR="${JDK_BOOT_DIR:-$JDK9_BOOT_DIR}";;
      "10")   export JDK_BOOT_DIR="${JDK_BOOT_DIR:-$JDK10_BOOT_DIR}";;
      "11")   export JDK_BOOT_DIR="${JDK_BOOT_DIR:-$JDK11_BOOT_DIR}";;
      "12")   export JDK_BOOT_DIR="${JDK_BOOT_DIR:-$JDK12_BOOT_DIR}";;
      "13")   export JDK_BOOT_DIR="${JDK_BOOT_DIR:-$JDK13_BOOT_DIR}";;
      "14")   export JDK_BOOT_DIR="${JDK_BOOT_DIR:-$JDK14_BOOT_DIR}";;
      "15")   export JDK_BOOT_DIR="${JDK_BOOT_DIR:-$JDK15_BOOT_DIR}";;
      "16")   export JDK_BOOT_DIR="${JDK_BOOT_DIR:-$JDK16_BOOT_DIR}";;
      "17")   export JDK_BOOT_DIR="${JDK_BOOT_DIR:-$JDK17_BOOT_DIR}";;
      "18")   export JDK_BOOT_DIR="${JDK_BOOT_DIR:-$JDK18_BOOT_DIR}";;
      *)      export JDK_BOOT_DIR="${JDK_BOOT_DIR:-$JDK19_BOOT_DIR}";;
esac


if [ ! -d "${JDK_BOOT_DIR}" ]
then
  echo Setting JDK_BOOT_DIR to \$JAVA_HOME
  export JDK_BOOT_DIR="${JAVA_HOME}"

  # Without this, a blank value can be passed into makejdk-any-platform.sh which causes an obscure parsing failure
  if [ ! -d "${JDK_BOOT_DIR}" ]
  then
    echo "[ERROR] No JDK Boot Directory has been found, the likelihood is that neither JDK${JDK_BOOT_VERSION}_BOOT_DIR or JAVA_HOME are set on this machine"
    exit 2
  fi
fi

echo "Boot jdk directory: ${JDK_BOOT_DIR}"
"${JDK_BOOT_DIR}/bin/java" -version 2>&1 | sed 's/^/BOOT JDK: /'
java -version 2>&1 | sed 's/^/JDK IN PATH: /g'

if [ "${RELEASE}" == "true" ]; then
  OPTIONS="${OPTIONS} --release --clean-libs"
fi

if [ "${RELEASE}" == "true" ] && [ "${VARIANT}" != "openj9" ]; then
    export TAG="${SCM_REF}"
else
    export BRANCH="${SCM_REF}"
fi


if [ -n "${TAG}" ]; then
  OPTIONS="${OPTIONS} --tag $TAG"
fi

if [ -n "${BRANCH}" ]
then
  OPTIONS="${OPTIONS} --disable-shallow-git-clone -b ${BRANCH}"
fi

echo "BRANCH: ${BRANCH} (For release either BRANCH or TAG should be set)"
echo "TAG: ${TAG}"

# shellcheck disable=SC2268
if [ "x${FILENAME}" = "x" ] ; then
    echo "FILENAME must be set in the environment"
    exit 1
fi

echo "Filename will be: $FILENAME"

export BUILD_ARGS="${BUILD_ARGS} --use-jep319-certs"

# Enable debug images for all platforms
export BUILD_ARGS="${BUILD_ARGS} --create-debug-image"

# JRE images are not produced for JDK16 and above
# as per https://github.com/adoptium/adoptium-support/issues/333
# Enable legacy JRE images for all platforms and versions older than 16
if [ "${JAVA_FEATURE_VERSION}" -lt 16 ]; then
  export BUILD_ARGS="${BUILD_ARGS} --create-jre-image"
fi

echo "$MAC_ROSETTA_PREFIX $PLATFORM_SCRIPT_DIR/../makejdk-any-platform.sh --clean-git-repo --jdk-boot-dir ${JDK_BOOT_DIR} --configure-args ${CONFIGURE_ARGS_FOR_ANY_PLATFORM} --target-file-name ${FILENAME} ${TAG_OPTION} ${OPTIONS} ${BUILD_ARGS} ${VARIANT_ARG} ${JAVA_TO_BUILD}"

# Convert all speech marks in config args to make them safe to pass in.
# These will be converted back into speech marks shortly before we use them, in build.sh.
CONFIGURE_ARGS_FOR_ANY_PLATFORM="${CONFIGURE_ARGS_FOR_ANY_PLATFORM//\"/temporary_speech_mark_placeholder}"

# shellcheck disable=SC2086
bash -c "$MAC_ROSETTA_PREFIX $PLATFORM_SCRIPT_DIR/../makejdk-any-platform.sh --clean-git-repo --jdk-boot-dir ${JDK_BOOT_DIR} --configure-args \"${CONFIGURE_ARGS_FOR_ANY_PLATFORM}\" --target-file-name ${FILENAME} ${TAG_OPTION} ${OPTIONS} ${BUILD_ARGS} ${VARIANT_ARG} ${JAVA_TO_BUILD}"

# If this is jdk8u on mac x64 that has cross compiled on arm64 we need to restore Xcode from the Xcode-11.7.app to default
if [[ "${JAVA_TO_BUILD}" == "${JDK8_VERSION}" ]] && [[ -n "$MAC_ROSETTA_PREFIX" ]]; then
  echo "Restoring Xcode select to /"
  echo "[WARNING] You may be asked for your su user password, attempting to switch Xcode version to /"
  sudo xcode-select --switch /
fi

if [ -d "${WORKSPACE}" ]; then
  SPACEUSED=$(du -sk "$WORKSPACE")
  echo "Total disk space in Kb consumed by build process: $SPACEUSED"
fi
