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

set -e

PLATFORM_SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

## Very very build farm specific configuration

TIMESTAMP="$(date +'%Y-%m-%d-%H-%M')"

export OPERATING_SYSTEM
OPERATING_SYSTEM=$(echo "${TARGET_OS}" | tr '[:upper:]' '[:lower:]')


echo "BUILD TYPE: "
echo "VERSION: ${JAVA_TO_BUILD}"
echo "ARCHITECTURE ${ARCHITECTURE}"
echo "VARIANT: ${VARIANT}"
echo "OS: ${OPERATING_SYSTEM}"
echo "BRANCH: ${BRANCH}"

OPTIONS=""
EXTENSION=""
# shellcheck disable=SC2034
CONFIGURE_ARGS_FOR_ANY_PLATFORM=${CONFIGURE_ARGS:-""}
BUILD_ARGS=${BUILD_ARGS:-""}
VARIANT_ARG="${JAVA_TO_BUILD}-"

if [ -z "${JDK_BOOT_VERSION}" ]
then
  echo "Detecting boot jdk for: ${JAVA_TO_BUILD}"
  currentBuildNumber=$(echo "${JAVA_TO_BUILD}" | tr -d "[:alpha:]")
  echo "Found build version: ${currentBuildNumber}"
  JDK_BOOT_VERSION=$((currentBuildNumber-1))
  echo "Boot jdk version: ${JDK_BOOT_VERSION}"
fi

case "${JDK_BOOT_VERSION}" in
      "7")    export JDK_BOOT_DIR="${JDK_BOOT_DIR:-$JDK7_BOOT_DIR}";;
      "8")    export JDK_BOOT_DIR="${JDK_BOOT_DIR:-$JDK8_BOOT_DIR}";;
      "9")    export JDK_BOOT_DIR="${JDK_BOOT_DIR:-$JDK9_BOOT_DIR}";;
      "10")   export JDK_BOOT_DIR="${JDK_BOOT_DIR:-$JDK10_BOOT_DIR}";;
      "11")   export JDK_BOOT_DIR="${JDK_BOOT_DIR:-$JDK11_BOOT_DIR}";;
      *)    export JDK_BOOT_DIR="${JDK_BOOT_DIR:-$JDK11_BOOT_DIR}";;
esac


if [ ! -d "${JDK_BOOT_DIR}" ]
then
  export JDK_BOOT_DIR="${JAVA_HOME}"
fi

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

if [ ! -z "${BRANCH}" ]
then
  OPTIONS="${OPTIONS} --disable-shallow-git-clone -b ${BRANCH}"
fi

# shellcheck source=build-farm/set-platform-specific-configurations.sh
source "${PLATFORM_SCRIPT_DIR}/set-platform-specific-configurations.sh"

# Set the file name
JAVA_TO_BUILD_UPPERCASE=$(echo "${JAVA_TO_BUILD}" | tr '[:lower:]' '[:upper:]')

FILENAME="Open${JAVA_TO_BUILD_UPPERCASE}-jdk_${ARCHITECTURE}_${OPERATING_SYSTEM}_${VARIANT}"

if [ ! -z "${ADDITIONAL_FILE_NAME_TAG}" ]; then
  FILENAME="${FILENAME}_${ADDITIONAL_FILE_NAME_TAG}"
fi

if [ -z "${TAG}" ]; then
  FILENAME="${FILENAME}_${TIMESTAMP}"
else
  nameTag=$(echo "${TAG}" | sed -e 's/jdk//' -e 's/-//' -e 's/+/_/g')
  FILENAME="${FILENAME}_${nameTag}"
fi

FILENAME="${FILENAME}.${EXTENSION}"


echo "Filename will be: $FILENAME"

export BUILD_ARGS="${BUILD_ARGS} --use-jep319-certs"

echo "$PLATFORM_SCRIPT_DIR/../makejdk-any-platform.sh" --clean-git-repo --jdk-boot-dir "${JDK_BOOT_DIR}" --configure-args "${CONFIGURE_ARGS_FOR_ANY_PLATFORM}" --target-file-name "${FILENAME}" ${TAG_OPTION} ${OPTIONS} ${BUILD_ARGS} ${VARIANT_ARG} "${JAVA_TO_BUILD}"

# shellcheck disable=SC2086
bash "$PLATFORM_SCRIPT_DIR/../makejdk-any-platform.sh" --clean-git-repo --jdk-boot-dir "${JDK_BOOT_DIR}" --configure-args "${CONFIGURE_ARGS_FOR_ANY_PLATFORM}" --target-file-name "${FILENAME}" ${TAG_OPTION} ${OPTIONS} ${BUILD_ARGS} ${VARIANT_ARG} "${JAVA_TO_BUILD}"
