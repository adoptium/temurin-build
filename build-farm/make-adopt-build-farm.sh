#!/bin/bash

set -ex

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

## Very very build farm specific configuration

TIMESTAMP="$(date +'%Y%d%m%H%M')"

OPTIONS=""
PLATFORM=""
EXTENSION=""
CONFIGURE_ARGS_FOR_ANY_PLATFORM=${CONFIGURE_ARGS:-""}
BUILD_ARGS=${BUILD_ARGS:-""}

if [ -n "${JDK_BOOT_VERSION}" ]
then
  case "${JDK_BOOT_VERSION}" in
        "7")    export JDK_BOOT_DIR="${JDK_BOOT_DIR:-$JDK7_BOOT_DIR}";;
        "8")    export JDK_BOOT_DIR="${JDK_BOOT_DIR:-$JDK8_BOOT_DIR}";;
        "9")    export JDK_BOOT_DIR="${JDK_BOOT_DIR:-$JDK9_BOOT_DIR}";;
        "10")   export JDK_BOOT_DIR="${JDK_BOOT_DIR:-$JDK10_BOOT_DIR}";;
        "home") echo "setting home $JAVA_HOME"
                export JDK_BOOT_DIR="${JDK_BOOT_DIR:-$JAVA_HOME}";;
        *)    export JDK_BOOT_DIR="${JDK_BOOT_VERSION}";;
  esac
else
  export JDK_BOOT_DIR="${JDK_BOOT_DIR:-$JDK7_BOOT_DIR}";
fi

if [ -n "${USER_PATH}" ]
then
  export PATH="${USER_PATH}:$PATH"
fi




if [[ $NODE_LABELS = *"linux"* ]] ; then
  PLATFORM="Linux"
  EXTENSION="tar.gz"

  if [ ! -z "${TAG}" ]; then
    OPTIONS="${OPTIONS} --tag $TAG"
  fi
elif [[ $NODE_LABELS = *"mac"* ]] ; then
  PLATFORM="Mac"
  EXTENSION="tar.gz"

  export MACOSX_DEPLOYMENT_TARGET=10.8
  sudo xcode-select --switch ${XCODE_SWITCH_PATH}
elif [[ $NODE_LABELS = *"windows"* ]] ; then
  PLATFORM=Windows
  EXTENSION=zip

  export ANT_HOME=/cygdrive/C/Projects/OpenJDK/apache-ant-1.10.1
  export ALLOW_DOWNLOADS=true
  export LANG=C
  export JAVA_HOME=$JDK_BOOT_DIR

  export BUILD_ARGS="--tmp-space-build ${BUILD_ARGS}"
fi



additionalSetupScript="${SCRIPT_DIR}/${JAVA_TO_BUILD}/${PLATFORM}/${ARCHITECTURE}/setup.sh"

if [ -e "${additionalSetupScript}" ]
then
    echo "loading ${additionalSetupScript}"
    source "${additionalSetupScript}"
fi

# Set the file name
FILENAME="OpenJDK8_x64_${PLATFORM}_${TIMESTAMP}.${EXTENSION}"
echo "Filename will be: $FILENAME"

bash "$SCRIPT_DIR/../makejdk-any-platform.sh"  --jdk-boot-dir "${JDK_BOOT_DIR}" --configure-args "${CONFIGURE_ARGS_FOR_ANY_PLATFORM}" --target-file-name "${FILENAME}" ${GIT_SHALLOW_CLONE_OPTION} ${TAG_OPTION} ${OPTIONS} ${BUILD_ARGS} "${JAVA_TO_BUILD}"
