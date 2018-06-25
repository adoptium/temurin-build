#!/bin/bash

set -e

PLATFORM_SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

## Very very build farm specific configuration

TIMESTAMP="$(date +'%Y-%m-%d-%H-%M')"

export OPERATING_SYSTEM=$(echo "${TARGET_OS}" | tr '[:upper:]' '[:lower:]')

echo "BUILD TYPE: "
echo "VERSION: ${JAVA_TO_BUILD}"
echo "ARCHITECTURE ${ARCHITECTURE}"
echo "VARIANT: ${VARIANT}"
echo "OS: ${OPERATING_SYSTEM}"

OPTIONS=""
EXTENSION=""
# shellcheck disable=SC2034
CONFIGURE_ARGS_FOR_ANY_PLATFORM=${CONFIGURE_ARGS:-""}
BUILD_ARGS=${BUILD_ARGS:-""}
VARIANT_ARG="${JAVA_TO_BUILD}-"

if [ -z "${JDK_BOOT_VERSION}" ]
then
  echo "Detecting boot jdk for: ${JAVA_TO_BUILD}"
  currentBuildNumber=$(echo "${JAVA_TO_BUILD}" | egrep -o "[0-9]+")
  echo "Found build version: ${currentBuildNumber}"
  JDK_BOOT_VERSION=$((currentBuildNumber-1))
  echo "Boot jdk version: ${JDK_BOOT_VERSION}"
fi

case "${JDK_BOOT_VERSION}" in
      "7")    export JDK_BOOT_DIR="${JDK_BOOT_DIR:-$JDK7_BOOT_DIR}";;
      "8")    export JDK_BOOT_DIR="${JDK_BOOT_DIR:-$JDK8_BOOT_DIR}";;
      "9")    export JDK_BOOT_DIR="${JDK_BOOT_DIR:-$JDK9_BOOT_DIR}";;
      "10")   export JDK_BOOT_DIR="${JDK_BOOT_DIR:-$JDK10_BOOT_DIR}";;
      "home") export JDK_BOOT_DIR="${JDK_BOOT_DIR:-$JAVA_HOME}";;
      *)    export JDK_BOOT_DIR="${JDK_BOOT_VERSION}";;
esac

echo "Boot jdk: ${JDK_BOOT_DIR}"


if [ "${OPERATING_SYSTEM}" == "linux" ] ; then
  EXTENSION="tar.gz"

  if [ ! -z "${TAG}" ]; then
    OPTIONS="${OPTIONS} --tag $TAG"
  fi
elif [ "${OPERATING_SYSTEM}" == "aix" ] ; then
  EXTENSION="tar.gz"
elif [ "${OPERATING_SYSTEM}" == "mac" ] ; then
  EXTENSION="tar.gz"
elif [ "${OPERATING_SYSTEM}" == "windows" ] ; then
  EXTENSION=zip
fi

# shellcheck source=build-farm/set-platform-specific-configurations.sh
source "${PLATFORM_SCRIPT_DIR}/set-platform-specific-configurations.sh"

# Set the file name
JAVA_TO_BUILD_UPPERCASE=$(echo "${JAVA_TO_BUILD}" | tr '[:lower:]' '[:upper:]')
FILENAME="Open${JAVA_TO_BUILD_UPPERCASE}_${ARCHITECTURE}_${OPERATING_SYSTEM}_${VARIANT}_${TIMESTAMP}.${EXTENSION}"
echo "Filename will be: $FILENAME"

# shellcheck disable=SC2086
bash "$PLATFORM_SCRIPT_DIR/../makejdk-any-platform.sh" --clean-git-repo --jdk-boot-dir "${JDK_BOOT_DIR}" --configure-args "${CONFIGURE_ARGS_FOR_ANY_PLATFORM}" --target-file-name "${FILENAME}" ${TAG_OPTION} ${OPTIONS} ${BUILD_ARGS} ${VARIANT_ARG} "${JAVA_TO_BUILD}"

