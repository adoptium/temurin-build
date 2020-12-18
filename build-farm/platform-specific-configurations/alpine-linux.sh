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

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# shellcheck source=sbin/common/constants.sh
source "$SCRIPT_DIR/../../sbin/common/constants.sh"

# ccache seems flaky on alpine
export CONFIGURE_ARGS_FOR_ANY_PLATFORM="${CONFIGURE_ARGS_FOR_ANY_PLATFORM} --disable-ccache"

# Any version above 8 (11 for now due to openjdk-build#1409
if [ "$JAVA_FEATURE_VERSION" -gt 11 ]; then
    BOOT_JDK_VERSION="$((JAVA_FEATURE_VERSION-1))"
    BOOT_JDK_VARIABLE="JDK$(echo $BOOT_JDK_VERSION)_BOOT_DIR"
    if [ ! -d "$(eval echo "\$$BOOT_JDK_VARIABLE")" ]; then
      bootDir="$PWD/jdk-$BOOT_JDK_VERSION"
      # Note we export $BOOT_JDK_VARIABLE (i.e. JDKXX_BOOT_DIR) here
      # instead of BOOT_JDK_VARIABLE (no '$').
      export ${BOOT_JDK_VARIABLE}="$bootDir"
      if [ ! -d "$bootDir/bin" ]; then
        mkdir -p "$bootDir"
        echo "Downloading GA release of boot JDK version ${BOOT_JDK_VERSION}..."
        releaseType="ga"
        apiUrlTemplate="https://api.adoptopenjdk.net/v3/binary/latest/\${BOOT_JDK_VERSION}/\${releaseType}/alpine-linux/\${ARCHITECTURE}/jdk/\${VARIANT}/normal/adoptopenjdk"
        apiURL=$(eval echo ${apiUrlTemplate})
        # make-adopt-build-farm.sh has 'set -e'. We need to disable that
        # for the fallback mechanism, as downloading of the GA binary might
        # fail.
        set +e
        wget -q -O - "${apiURL}" | tar xpzf - --strip-components=1 -C "$bootDir"
        retVal=$?
        set -e
        if [ $retVal -ne 0 ]; then
          # We must be a JDK HEAD build for which no boot JDK exists other than
          # nightlies?
          echo "Downloading GA release of boot JDK version ${BOOT_JDK_VERSION} failed."
          echo "Attempting to download EA release of boot JDK version ${BOOT_JDK_VERSION} ..."
          # shellcheck disable=SC2034
          releaseType="ea"
          apiURL=$(eval echo ${apiUrlTemplate})
          wget -q -O - "${apiURL}" | tar xpzf - --strip-components=1 -C "$bootDir"
        fi
      fi
    fi
    export JDK_BOOT_DIR="$(eval echo "\$$BOOT_JDK_VARIABLE")"
    "$JDK_BOOT_DIR/bin/java" -version
    executedJavaVersion=$?
    if [ $executedJavaVersion -ne 0 ]; then
        echo "Failed to obtain or find a valid boot jdk"
        exit 1
    fi
    "$JDK_BOOT_DIR/bin/java" -version 2>&1 | sed 's/^/BOOT JDK: /'
fi