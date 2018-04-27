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
  local build_arguments=""
  declare -a build_argument_names=("--source" "--destination" "--repository" "--variant" "--update-version" "--build-number" "--repository-tag" "--configure-args")
  declare -a build_argument_values=("${BUILD_CONFIG[WORKING_DIR]}" "${BUILD_CONFIG[TARGET_DIR]}" "${BUILD_CONFIG[OPENJDK_SOURCE_DIR]}" "${BUILD_CONFIG[JVM_VARIANT]}" "${BUILD_CONFIG[OPENJDK_UPDATE_VERSION]}" "${BUILD_CONFIG[OPENJDK_BUILD_NUMBER]}" "${BUILD_CONFIG[TAG]}" "${BUILD_CONFIG[USER_SUPPLIED_CONFIGURE_ARGS]}")

  local build_args_array_index=0
  while [[ ${build_args_array_index} < ${#build_argument_names[@]} ]]; do
    if [[ ${build_argument_values[${build_args_array_index}]} != "" ]];
    then
        build_arguments="${build_arguments} ${build_argument_names[${build_args_array_index}]} ${build_argument_values[${build_args_array_index}]} "
    fi
    ((build_args_array_index++))
  done

  echo "Calling ${SCRIPT_DIR}/sbin/build.sh ${build_arguments}"
  # shellcheck disable=SC2086
  "${SCRIPT_DIR}"/sbin/build.sh ${build_arguments}

  #testOpenJDKInNativeEnvironmentIfExpected
}
