#!/bin/bash

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

if [ "${JAVA_TO_BUILD}" == "jdk9" ] || [ "${JAVA_TO_BUILD}" == "jdk10u" ]
then
    export CONFIGURE_ARGS_FOR_ANY_PLATFORM="${CONFIGURE_ARGS_FOR_ANY_PLATFORM} --disable-warnings-as-errors"
fi

if [ "${VARIANT}" != "hotspot" ]
then
  VARIANT_ARG="--build-variant ${VARIANT}"
fi

# shellcheck disable=SC1091,SC1090
source "$SCRIPT_DIR/platform-specific-configurations/${PLATFORM}.sh"