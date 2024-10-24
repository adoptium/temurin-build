#!/bin/bash
# shellcheck disable=SC1091
# ********************************************************************************
# Copyright (c) 2020 Contributors to the Eclipse Foundation
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

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# shellcheck source=sbin/common/constants.sh
source "$SCRIPT_DIR/../../sbin/common/constants.sh"

# Solves issues seen on 4GB HC4 systems with two large ld processes
if [ "$(awk '/^MemTotal:/{print$2}' < /proc/meminfo)" -lt "5000000" ]
then
  export CONFIGURE_ARGS_FOR_ANY_PLATFORM="${CONFIGURE_ARGS_FOR_ANY_PLATFORM} --with-extra-ldflags=-Wl,--no-keep-memory"
fi

# ccache seems flaky on alpine
export CONFIGURE_ARGS_FOR_ANY_PLATFORM="${CONFIGURE_ARGS_FOR_ANY_PLATFORM} --disable-ccache"

if [[ "$JAVA_FEATURE_VERSION" -ge 21 ]]; then
  # jdk-21+ uses "bundled" FreeType
  export BUILD_ARGS="${BUILD_ARGS} --freetype-dir bundled"
else
  # We don't bundle freetype on alpine anymore, and expect the user to have it.
  export BUILD_ARGS="${BUILD_ARGS} --skip-freetype"
fi

## This affects Alpine docker images and also evaluation pipelines
if [ "$(pwd | wc -c)" -gt 83 ]; then
  # Use /tmp for alpine in preference to $HOME as Alpine fails gpg operation if PWD > 83 characters
  # Alpine also cannot create ~/.gpg-temp within a docker context
  GNUPGHOME="$(mktemp -d /tmp/.gpg-temp.XXXXXX)"
else
  GNUPGHOME="${WORKSPACE:-$PWD}/.gpg-temp"
fi
if [ ! -d "$GNUPGHOME" ]; then
    mkdir -m 700 "$GNUPGHOME"
fi
export GNUPGHOME

BOOT_JDK_VARIABLE="JDK${JDK_BOOT_VERSION}_BOOT_DIR"
if [ ! -d "$(eval echo "\$$BOOT_JDK_VARIABLE")" ]; then
  bootDir="$PWD/jdk$JDK_BOOT_VERSION"
  # Note we export $BOOT_JDK_VARIABLE (i.e. JDKXX_BOOT_DIR) here
  # instead of BOOT_JDK_VARIABLE (no '$').
  export "${BOOT_JDK_VARIABLE}"="$bootDir"
  if [ ! -d "$bootDir/bin" ]; then
    mkdir -p "$bootDir"
    releaseType="ga"
    apiUrlTemplate="https://api.adoptium.net/v3/binary/latest/\${JDK_BOOT_VERSION}/\${releaseType}/alpine-linux/\${ARCHITECTURE}/jdk/hotspot/normal/eclipse"
    apiURL=$(eval echo ${apiUrlTemplate})
    echo "Downloading GA release of boot JDK version ${JDK_BOOT_VERSION} from ${apiURL}"
    # make-adopt-build-farm.sh has 'set -e'. We need to disable that for
    # the fallback mechanism, as downloading of the GA binary might fail.
    set +e
    wget -q -O - "${apiURL}" | tar xpzf - --strip-components=1 -C "$bootDir"
    retVal=$?
    set -e
    if [ $retVal -ne 0 ]; then
      # We must be a JDK HEAD build for which no boot JDK exists other than
      # nightlies?
      echo "Downloading GA release of boot JDK version ${JDK_BOOT_VERSION} failed."
      # shellcheck disable=SC2034
      releaseType="ea"
      apiURL=$(eval echo ${apiUrlTemplate})
      echo "Attempting to download EA release of boot JDK version ${JDK_BOOT_VERSION} from ${apiURL}"
      wget -q -O - "${apiURL}" | tar xpzf - --strip-components=1 -C "$bootDir"
    fi
  fi
fi

# shellcheck disable=SC2155
export JDK_BOOT_DIR="$(eval echo "\$$BOOT_JDK_VARIABLE")"
"$JDK_BOOT_DIR/bin/java" -version 2>&1 | sed 's/^/BOOT JDK: /'
"$JDK_BOOT_DIR/bin/java" -version > /dev/null 2>&1
executedJavaVersion=$?
if [ $executedJavaVersion -ne 0 ]; then
    echo "Failed to obtain or find a valid boot jdk"
    exit 1
fi
