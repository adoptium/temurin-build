#!/usr/bin/env bash


################################################################################
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
################################################################################

set -eux

# i.e. Where we are
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"


testOpenJDKInNativeEnvironmentIfExpected()
{
  if [[ "${BUILD_CONFIG[JTREG]}" == "true" ]];
  then
      "${SCRIPT_DIR}"/sbin/jtreg.sh "${BUILD_CONFIG[WORKING_DIR]}" "${BUILD_CONFIG[OPENJDK_SOURCE_DIR]}" "${BUILD_CONFIG[BUILD_FULL_NAME]}" "${BUILD_CONFIG[JTREG_TEST_SUBSETS]}"
  fi
}

buildAndTestOpenJDKInNativeEnvironment()
{
  "${SCRIPT_DIR}"/sbin/build.sh

  #testOpenJDKInNativeEnvironmentIfExpected
}
