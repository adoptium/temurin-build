#!/bin/bash

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# shellcheck source=sbin/common/constants.sh
source "$SCRIPT_DIR/../sbin/common/constants.sh"

if [ "${JAVA_TO_BUILD}" == "${JDK9_VERSION}" ] || [ "${JAVA_TO_BUILD}" == "${JDK10_VERSION}" ]
then
    export CONFIGURE_ARGS_FOR_ANY_PLATFORM="${CONFIGURE_ARGS_FOR_ANY_PLATFORM} --disable-warnings-as-errors"
fi

if [ "${VARIANT}" != "hotspot" ]
then
  export VARIANT_ARG="--build-variant ${VARIANT}"
fi

# shellcheck disable=SC1091,SC1090
source "$SCRIPT_DIR/platform-specific-configurations/${OPERATING_SYSTEM}.sh"