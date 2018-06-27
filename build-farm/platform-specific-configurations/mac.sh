#!/bin/bash

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# shellcheck source=sbin/common/constants.sh
source "$SCRIPT_DIR/../../sbin/common/constants.sh"

export MACOSX_DEPLOYMENT_TARGET=10.8
export BUILD_ARGS="${BUILD_ARGS} --sign \"Developer ID Application: London Jamocha Community CIC\""

XCODE_SWITCH_PATH="/";

if [ "${JAVA_TO_BUILD}" == "${JDK8_VERSION}" ]
then
  XCODE_SWITCH_PATH="/Applications/Xcode.app"
fi
sudo xcode-select --switch "${XCODE_SWITCH_PATH}"


if [ "${JAVA_TO_BUILD}" == "${JDK9_VERSION}" ] || [ "${JAVA_TO_BUILD}" == "${JDK10_VERSION}" ]
then
    export PATH="/Users/jenkins/ccache-3.2.4:$PATH"
fi