#!/bin/bash

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
#
################################################################################

################################################################################
# TBA
################################################################################

set -eux # TODO remove once we've finished debugging

# i.e. Where we are
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Load the common functions
## shellcheck source=sbin/common-functions.sh
source "$SCRIPT_DIR/sbin/common-functions.sh"

init_build_config() {
  # Dir where we clone the OpenJDK source code for building, defaults to 'src'
  BUILD_CONFIG[OPENJDK_SOURCE_DIR]=${BUILD_CONFIG[OPENJDK_SOURCE_DIR]:-src}

  # Repo to pull the OpenJDK source from, defaults to AdoptOpenJDK/openjdk-jdk8u
  BUILD_CONFIG[REPOSITORY]=${BUILD_CONFIG[REPOSITORY]:-"AdoptOpenJDK/openjdk-jdk8u"}

  # By default only git clone the HEAD commit
  BUILD_CONFIG[SHALLOW_CLONE_OPTION]="--depth=1"

  # Set Docker Container names and defaults
  BUILD_CONFIG[DOCKER_SOURCE_VOLUME_NAME]="openjdk-source-volume"
  BUILD_CONFIG[CONTAINER_NAME]=openjdk_container
  BUILD_CONFIG[TMP_CONTAINER_NAME]=openjdk-copy-src
  BUILD_CONFIG[CLEAN_DOCKER_BUILD]=false

  # Copy the results of the docker build (defaults to false)
  BUILD_CONFIG[COPY_TO_HOST]=false

  # Use Docker to build (defaults to false)
  BUILD_CONFIG[USE_DOCKER]=false

  # Location of DockerFile and where scripts get copied to inside the container
  BUILD_CONFIG[DOCKER_FILE_PATH]=""

  # Whether we keep the Docker container after we build it
  # TODO Please note that the persistent volume is managed separately
  BUILD_CONFIG[KEEP_CONTAINER]=false

  # Whether we use an existing container
  # TODO Please note that the persistent volume is managed separately
  BUILD_CONFIG[REUSE_CONTAINER]=true

  # The current working directory
  BUILD_CONFIG[WORKING_DIR]=""

  # Root of the workspace
  BUILD_CONFIG[WORKSPACE_DIR]=""

  # Use SSH for the GitHub connection (defaults to false)
  BUILD_CONFIG[USE_SSH]=false

  # Directory where OpenJDK binary gets built to
  BUILD_CONFIG[TARGET_DIR]=""

  # Which repo branch to build, e.g. dev
  BUILD_CONFIG[BRANCH]=""

  # Which repo tag to build, e.g. jdk8u172-b03
  BUILD_CONFIG[TAG]=""

  # Update version e.g. 172
  BUILD_CONFIG[OPENJDK_UPDATE_VERSION]=""

  # build number e.g. b03
  BUILD_CONFIG[OPENJDK_BUILD_NUMBER]=""

  # Build variant, e.g. openj9, defaults to "" which means hotspot
  BUILD_CONFIG[BUILD_VARIANT]=${BUILD_CONFIG[BUILD_VARIANT]:-""}

  # JVM variant, e.g. client or server, defaults to server
  BUILD_CONFIG[JVM_VARIANT]=${BUILD_CONFIG[JVM_VARIANT]:-server}

  # Any extra args provided by the user
  BUILD_CONFIG[USER_SUPPLIED_CONFIGURE_ARGS]=""

  BUILD_CONFIG[DOCKER]="docker"

  # Print to console using colour codes
  BUILD_CONFIG[COLOUR]="true"
}

sourceFileWithColourCodes()
{
  if [[ "${BUILD_CONFIG[COLOUR]}" == "true" ]] ; then
    # shellcheck disable=SC1091
    source ./sbin/colour-codes.sh
  fi
}

sourceSignalHandler()
{
  source sbin/signalhandler.sh
}

parseCommandLineArgs()
{
  parseConfigurationArguments "$@"

  while [[ $# -gt 1 ]] ; do
    shift;
  done

  # Now that we've processed the flags, grab the mandatory argument(s)
  local forest_name=$1

  # Derive the openjdk_core_version from the forest name.
  local openjdk_core_version=${forest_name}
  if [[ ${forest_name} == *u ]]; then
    openjdk_core_version=${forest_name%?}
  fi

  BUILD_CONFIG[OPENJDK_CORE_VERSION]=$openjdk_core_version;
  BUILD_CONFIG[OPENJDK_FOREST_NAME]=$forest_name;

  # 'u' means it's an update repo, e.g. jdk8u
  if [[ ${BUILD_CONFIG[OPENJDK_FOREST_NAME]} == *u ]]; then
    BUILD_CONFIG[OPENJDK_CORE_VERSION]=${BUILD_CONFIG[OPENJDK_FOREST_NAME]%?}
  fi

  # TODO check that OPENJDK_CORE_VERSION has been set by the caller
}

doAnyBuildVariantOverrides()
{
  if [[ "${BUILD_CONFIG[BUILD_VARIANT]}" == "openj9" ]]; then
    # current (not final) location of Extensions for OpenJDK9 for OpenJ9 project
    local repository="ibmruntimes/openj9-openjdk-${BUILD_CONFIG[OPENJDK_CORE_VERSION]}"
    local branch="openj9"
  fi
  if [[ "${BUILD_CONFIG[BUILD_VARIANT]}" == "SapMachine" ]]; then
    # current location of SAP variant
    local repository="SAP/SapMachine"
     # sapmachine10 is the current branch for OpenJDK10 mainline
     # (equivalent to jdk/jdk10 on hotspot)
    local branch="sapmachine10"
  fi

  BUILD_CONFIG[REPOSITORY]=${repository:-${BUILD_CONFIG[REPOSITORY]}};
  BUILD_CONFIG[BRANCH]=${branch:-${BUILD_CONFIG[BRANCH]}};
}

setDefaultBranchIfNotProvided()
{
  if [ -z "${BUILD_CONFIG[BRANCH]}" ] ; then
    echo "${info}BRANCH is undefined so checking out dev${normal}."
    BUILD_CONFIG[BRANCH]="dev"
  fi
}

setWorkingDirectory()
{
  if [ -z "${BUILD_CONFIG[WORKSPACE_DIR]}" ] ; then
    if [[ "${BUILD_CONFIG[USE_DOCKER]}" == "true" ]];
    then
       BUILD_CONFIG[WORKSPACE_DIR]="/openjdk/";
     else
       BUILD_CONFIG[WORKSPACE_DIR]="$PWD/workspace";
       mkdir -p "${BUILD_CONFIG[WORKSPACE_DIR]}" || exit
    fi
  else
    echo "${info}Workspace dir is ${BUILD_CONFIG[WORKSPACE_DIR]}${normal}"
  fi


  if [ -z "${BUILD_CONFIG[WORKING_DIR]}" ] ; then
    echo "${info}WORKING_DIR is undefined so setting to ${PWD}${normal}."
    BUILD_CONFIG[WORKING_DIR]="./build/"
  else
    echo "${info}Working dir is ${BUILD_CONFIG[WORKING_DIR]}${normal}"
  fi
}

setTargetDirectory()
{
  if [ -z "${BUILD_CONFIG[TARGET_DIR]}" ] ; then
    echo "${info}TARGET_DIR is undefined so setting to $PWD.${normal}"
    BUILD_CONFIG[TARGET_DIR]="${BUILD_CONFIG[WORKSPACE_DIR]}/target/"
  else
    echo "${info}Target directory is ${BUILD_CONFIG[TARGET_DIR]}${normal}"
    BUILD_CONFIG[COPY_TO_HOST]=true
    echo "If you're using Docker, the build artifact will be copied to the host."
  fi
}

determineBuildProperties() {
    BUILD_CONFIG[JVM_VARIANT]=${BUILD_CONFIG[JVM_VARIANT]:-server}

    local build_type=normal
    local default_build_full_name=${BUILD_CONFIG[OS_KERNEL_NAME]}-${BUILD_CONFIG[OS_ARCHITECTURE]}-${build_type}-${BUILD_CONFIG[JVM_VARIANT]}-release

    BUILD_CONFIG[BUILD_FULL_NAME]=${BUILD_CONFIG[BUILD_FULL_NAME]:-"$default_build_full_name"}
}

################################################################################

configure_build() {
    determineBuildProperties
    init_build_config
    sourceSignalHandler
    parseCommandLineArgs "$@"
    doAnyBuildVariantOverrides
    sourceFileWithColourCodes
    setDefaultBranchIfNotProvided
    setWorkingDirectory
    setTargetDirectory
}
