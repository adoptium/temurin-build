#!/bin/bash
# shellcheck disable=SC1091

################################################################################
#
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
#
################################################################################

################################################################################
#
# Entry point to build (Adoptium) OpenJDK binaries for any platform.
#
# 1. Source scripts to support configuration, docker builds and native builds.
# 2. Parse the Command Line Args
# 3. Set a host of configuration options based on args, platform etc
# 4. Display and then persist those configuration options
# 5. Build the binary in Docker or natively
#
################################################################################

set -eu

# i.e. Where we are
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Pull in configuration and build support
# shellcheck source=sbin/common/config_init.sh
source "${SCRIPT_DIR}/sbin/common/config_init.sh"

# shellcheck source=docker-build.sh
source "${SCRIPT_DIR}/docker-build.sh"

# shellcheck source=native-build.sh
source "${SCRIPT_DIR}/native-build.sh"

# shellcheck source=configureBuild.sh
source "${SCRIPT_DIR}/configureBuild.sh"

echo "Starting $0 to configure, build (Adoptium)OpenJDK binary"

# Configure the build, display the parameters and write the config to disk
# see ${SCRIPT_DIR}/sbin/common/config_init.sh for details
configure_build "$@"
writeConfigToFile

# Store params to this script as "buildinfo"
echo "$@" > ./workspace/config/makejdk-any-platform.args

# Let's build and test the (Adoptium) OpenJDK binary in Docker or natively
if [ "${BUILD_CONFIG[USE_DOCKER]}" == "true" ] ; then
  buildOpenJDKViaDocker
else
  buildOpenJDKInNativeEnvironment
fi
