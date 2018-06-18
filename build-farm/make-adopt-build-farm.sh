#!/bin/bash

set -ex

PLATFORM_SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

## Very very build farm specific configuration

TIMESTAMP="$(date +'%Y-%m-%d-%H-%M')"


echo "BUILD TYPE: "
echo "VERSION: ${JAVA_TO_BUILD}"
echo "ARCHITECTURE ${ARCHITECTURE}"
echo "VARIANT: ${VARIANT}"

OPTIONS=""
PLATFORM=""
EXTENSION=""
# shellcheck disable=SC2034
CONFIGURE_ARGS_FOR_ANY_PLATFORM=${CONFIGURE_ARGS:-""}
BUILD_ARGS=${BUILD_ARGS:-""}
VARIANT_ARG=""

if [ -n "${JDK_BOOT_VERSION}" ]
then
  case "${JDK_BOOT_VERSION}" in
        "7")    export JDK_BOOT_DIR="${JDK_BOOT_DIR:-$JDK7_BOOT_DIR}";;
        "8")    export JDK_BOOT_DIR="${JDK_BOOT_DIR:-$JDK8_BOOT_DIR}";;
        "9")    export JDK_BOOT_DIR="${JDK_BOOT_DIR:-$JDK9_BOOT_DIR}";;
        "10")   export JDK_BOOT_DIR="${JDK_BOOT_DIR:-$JDK10_BOOT_DIR}";;
        "home") export JDK_BOOT_DIR="${JDK_BOOT_DIR:-$JAVA_HOME}";;
        *)    export JDK_BOOT_DIR="${JDK_BOOT_VERSION}";;
  esac
else
  export JDK_BOOT_DIR="${JDK_BOOT_DIR:-$JDK7_BOOT_DIR}";
fi

if [[ $NODE_LABELS = *"linux"* ]] ; then
  PLATFORM="Linux"
  EXTENSION="tar.gz"

  if [ ! -z "${TAG}" ]; then
    OPTIONS="${OPTIONS} --tag $TAG"
  fi
elif [[ $NODE_LABELS = *"aix"* ]] ; then
  PLATFORM="Aix"
  EXTENSION="tar.gz"
elif [[ $NODE_LABELS = *"mac"* ]] ; then
  PLATFORM="Mac"
  EXTENSION="tar.gz"
elif [[ $NODE_LABELS = *"windows"* ]] ; then
  PLATFORM=Windows
  EXTENSION=zip
fi

# shellcheck source=build-farm/set-platform-specific-configurations.sh
source "${PLATFORM_SCRIPT_DIR}/set-platform-specific-configurations.sh"

# Set the file name
JAVA_TO_BUILD_UPPERCASE=$(echo "${JAVA_TO_BUILD}" | tr '[:lower:]' '[:upper:]')
FILENAME="Open${JAVA_TO_BUILD_UPPERCASE}_${ARCHITECTURE}_${PLATFORM}_${VARIANT}_${TIMESTAMP}.${EXTENSION}"
echo "Filename will be: $FILENAME"

# shellcheck disable=SC2086
bash "$PLATFORM_SCRIPT_DIR/../makejdk-any-platform.sh"  --jdk-boot-dir "${JDK_BOOT_DIR}" --configure-args "${CONFIGURE_ARGS_FOR_ANY_PLATFORM}" --target-file-name "${FILENAME}" ${TAG_OPTION} ${OPTIONS} ${BUILD_ARGS} ${VARIANT_ARG} "${JAVA_TO_BUILD}"

