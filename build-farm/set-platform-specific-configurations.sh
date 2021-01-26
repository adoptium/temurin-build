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
source "$SCRIPT_DIR/../sbin/common/constants.sh"

if [ "${JAVA_TO_BUILD}" != "${JDK8_VERSION}" ]
then
    export CONFIGURE_ARGS_FOR_ANY_PLATFORM="${CONFIGURE_ARGS_FOR_ANY_PLATFORM} --disable-warnings-as-errors"
fi

export VARIANT_ARG="--build-variant ${VARIANT}"

# Create placeholders for curl --output
if [ ! -d "$SCRIPT_DIR/platform-specific-configurations" ]
then
    mkdir "$SCRIPT_DIR/platform-specific-configurations"
fi
if [ ! -f "$SCRIPT_DIR/platform-specific-configurations/platformConfigFile.sh" ]
then
    touch "$SCRIPT_DIR/platform-specific-configurations/platformConfigFile.sh"
fi
PLATFORM_CONFIG_FILEPATH="$SCRIPT_DIR/platform-specific-configurations/platformConfigFile.sh"

# Attempt to download and source the user's custom platform config
echo "Attempting to download user platform configuration file from https://raw.githubusercontent.com/${PLATFORM_CONFIG_LOCATION}"
# make-adopt-build-farm.sh has 'set -e'. We need to disable that for the fallback mechanism, as downloading might fail
set +e
curl "https://raw.githubusercontent.com/${PLATFORM_CONFIG_LOCATION}" > "${PLATFORM_CONFIG_FILEPATH}"
ret=$?
# A download will succeed if the location is a directory
fileContents=$(cat $PLATFORM_CONFIG_FILEPATH)
set -e

if [[ $ret -ne 0 || $fileContents == "404: Not Found" ]]
then
    # Check to make sure that the a OS file doesn't exist if we can't find a config file from the direct link
    echo "Failed to a user configuration file, https://raw.githubusercontent.com/${PLATFORM_CONFIG_LOCATION} is likely a directory. Trying https://raw.githubusercontent.com/${PLATFORM_CONFIG_LOCATION}/${OPERATING_SYSTEM}.sh"
    set +e
    curl "https://raw.githubusercontent.com/${PLATFORM_CONFIG_LOCATION}/${OPERATING_SYSTEM}.sh" > "${PLATFORM_CONFIG_FILEPATH}"
    ret=$?
    fileContents=$(cat $PLATFORM_CONFIG_FILEPATH)
    set -e

    if [[ $ret -ne 0 || $fileContents == "404: Not Found" ]]
    then
        # If there is no user platform config, use adopt's as a default instead
        echo "Failed to download a user platform configuration file. Downloading Adopt's platform configuration file instead from https://raw.githubusercontent.com/${ADOPT_PLATFORM_CONFIG_LOCATION}/${OPERATING_SYSTEM}.sh"
        curl "https://raw.githubusercontent.com/${ADOPT_PLATFORM_CONFIG_LOCATION}/${OPERATING_SYSTEM}.sh" > "${PLATFORM_CONFIG_FILEPATH}"
    fi
fi

echo "Config file downloaded successfully to ${PLATFORM_CONFIG_FILEPATH}"
source "${PLATFORM_CONFIG_FILEPATH}"
