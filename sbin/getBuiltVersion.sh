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


set -eu

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# shellcheck source=sbin/common/config_init.sh
source "$SCRIPT_DIR/common/config_init.sh"

# shellcheck source=sbin/common/constants.sh
source "$SCRIPT_DIR/common/constants.sh"

# shellcheck source=sbin/common/common.sh
source "$SCRIPT_DIR/common/common.sh"

loadConfigFromFile

cd "${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[WORKING_DIR]}/${BUILD_CONFIG[OPENJDK_SOURCE_DIR]}"  || exit

case "${BUILD_CONFIG[OS_KERNEL_NAME]}" in
"darwin")
  # shellcheck disable=SC2086
  PRODUCT_HOME=$(ls -d ${PWD}/build/*/images/jdk*/Contents/Home | head -n 1)
;;
*)
  # shellcheck disable=SC2086
  PRODUCT_HOME=$(ls -d ${PWD}/build/*/images/jdk* | head -n 1)
;;
esac

if [[ -d "$PRODUCT_HOME" ]]; then
  echo "=JAVA VERSION OUTPUT="
  "$PRODUCT_HOME"/bin/java -version 2>&1
  echo "=/JAVA VERSION OUTPUT="
else
  echo "'$PRODUCT_HOME' does not exist, build might have not been successful or not produced the expected JDK image at this location."
  exit -1
fi