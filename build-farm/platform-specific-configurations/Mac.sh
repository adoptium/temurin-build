#!/bin/bash

export MACOSX_DEPLOYMENT_TARGET=10.8

XCODE_SWITCH_PATH="/";

if [ "${JAVA_TO_BUILD}" == "jdk8u" ]
then
  XCODE_SWITCH_PATH="/Applications/Xcode.app"
fi
sudo xcode-select --switch "${XCODE_SWITCH_PATH}"


if [ "${JAVA_TO_BUILD}" == "jdk9" ] || [ "${JAVA_TO_BUILD}" == "jdk10u" ]
then
    export PATH="/Users/jenkins/ccache-3.2.4:$PATH"
fi