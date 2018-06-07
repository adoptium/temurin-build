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
#
# This script sets up the initial configuration for an (Adopt) OpenJDK Build.
# See the configure_build function and its child functions for details.
# It's sourced by the makejdk-any-platform.sh script.
#
################################################################################

set -eux # TODO remove once we've finished debugging

# i.e. Where we are
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Bring in the source signal handler
sourceSignalHandler()
{
  #shellcheck source=signalhandler.sh
  source "$SCRIPT_DIR/signalhandler.sh"
}

# Parse the command line arguments
parseCommandLineArgs()
{
  # Defer most of the work to the shared function in common-functions.sh
  parseConfigurationArguments "$@"

  # this check is to maintain backwards compatibility and allow user to use
  # -v rather than the mandatory argument
  if [[ "${BUILD_CONFIG[OPENJDK_FOREST_NAME]}" == "" ]]
  then
    if [[ $# -eq 0 ]]
    then
      echo "Please provide a java version to build as an argument"
      exit 1
    fi

    while [[ $# -gt 1 ]] ; do
      shift;
    done

    # Now that we've processed the flags, grab the mandatory argument(s)
    setOpenJdkVersion "$1"
  fi
}

# Extra config for OpenJDK variants such as OpenJ9, SAP et al
# shellcheck disable=SC2153
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

# Set the working directory for this build
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
    echo "Workspace dir is ${BUILD_CONFIG[WORKSPACE_DIR]}"
  fi

  echo "Working dir is ${BUILD_CONFIG[WORKING_DIR]}"
}

# shellcheck disable=SC2153
determineBuildProperties() {
    local build_type=normal
    local default_build_full_name=${BUILD_CONFIG[OS_KERNEL_NAME]}-${BUILD_CONFIG[OS_ARCHITECTURE]}-${build_type}-${BUILD_CONFIG[JVM_VARIANT]}-release

    BUILD_CONFIG[BUILD_FULL_NAME]=${BUILD_CONFIG[BUILD_FULL_NAME]:-"$default_build_full_name"}
}

# Set variables that the `configure` command (which builds OpenJDK) will need
# shellcheck disable=SC2153
setVariablesForConfigure() {

  local openjdk_core_version=${BUILD_CONFIG[OPENJDK_CORE_VERSION]}

  # TODO Regex this in the if or use cut to grab out the number and see if >= 9
  # TODO 9 should become 9u as will 10 shortly....
  if [ "$openjdk_core_version" == "jdk9" ] || [ "$openjdk_core_version" == "jdk10" ] || [ "$openjdk_core_version" == "jdk11" ] || [ "$openjdk_core_version" == "amber" ]; then
    local jdk_path="jdk"
    local jre_path="jre"
    #BUILD_CONFIG[CONFIGURE_ARGS_FOR_ANY_PLATFORM]=${BUILD_CONFIG[CONFIGURE_ARGS_FOR_ANY_PLATFORM]:-"--disable-warnings-as-errors"}
  elif [ "$openjdk_core_version" == "jdk8" ]; then
    local jdk_path="j2sdk-image"
    local jre_path="j2re-image"
  else
    echo "Please specify a version, either jdk8u, jdk9, jdk10, amber etc, with or without a 'u' suffix. e.g. $0 [options] jdk8u"
    exit 1
  fi

  BUILD_CONFIG[JDK_PATH]=$jdk_path
  BUILD_CONFIG[JRE_PATH]=$jre_path
}

# Set the repository to build from
setRepository() {
  local repository="${BUILD_CONFIG[REPOSITORY]:-adoptopenjdk/openjdk-${BUILD_CONFIG[OPENJDK_FOREST_NAME]}}";
  repository="$(echo "${repository}" | awk '{print tolower($0)}')";

  BUILD_CONFIG[REPOSITORY]=$repository
}

# Specific platforms need to have special build settings
processArgumentsforSpecificPlatforms() {

  case "${BUILD_CONFIG[OS_KERNEL_NAME]}" in
  "darwin")
    if [ "${BUILD_CONFIG[OPENJDK_CORE_VERSION]}" == "jdk8" ] ; then
      BUILD_CONFIG[COPY_MACOSX_FREE_FONT_LIB_FOR_JDK_FLAG]="false"
      BUILD_CONFIG[COPY_MACOSX_FREE_FONT_LIB_FOR_JRE_FLAG]="true"
    fi
  ;;
  esac

}

# Specific architectures need to have special build settings
# shellcheck disable=SC2153
processArgumentsforSpecificArchitectures() {
  local jvm_variant=server
  local build_full_name=""
  local make_args_for_any_platform=""
  local configure_args_for_any_platform=""

  case "${BUILD_CONFIG[OS_ARCHITECTURE]}" in
  "s390x")
    if [ "${BUILD_CONFIG[OPENJDK_CORE_VERSION]}" == "jdk8" ] && [ "$jvm_variant" != "openj9" ]; then
      jvm_variant=zero
    else
      jvm_variant=server
    fi

    build_full_name=linux-s390x-normal-${jvm_variant}-release
    make_args_for_any_platform="CONF=${build_full_name} DEBUG_BINARIES=true images"
  ;;

  "ppc64le")
    jvm_variant=server
    build_full_name=linux-ppc64-normal-${jvm_variant}-release
    # shellcheck disable=SC1083
    BUILD_CONFIG[FREETYPE_FONT_BUILD_TYPE_PARAM]=${BUILD_CONFIG[FREETYPE_FONT_BUILD_TYPE_PARAM]:="--build=$(rpm --eval %{_host})"}
  ;;

  "armv7l")
    jvm_variant=zero
    make_args_for_any_platform="DEBUG_BINARIES=true images"
    configure_args_for_any_platform="--with-jobs=${NUM_PROCESSORS}"
  ;;

  "aarch64")
    BUILD_CONFIG[FREETYPE_FONT_VERSION]="2.5.2"
  ;;
  esac

  BUILD_CONFIG[JVM_VARIANT]=${BUILD_CONFIG[JVM_VARIANT]:-$jvm_variant}
  BUILD_CONFIG[BUILD_FULL_NAME]=${BUILD_CONFIG[BUILD_FULL_NAME]:-$build_full_name}
  BUILD_CONFIG[MAKE_ARGS_FOR_ANY_PLATFORM]=${BUILD_CONFIG[MAKE_ARGS_FOR_ANY_PLATFORM]:-$make_args_for_any_platform}
  BUILD_CONFIG[CONFIGURE_ARGS_FOR_ANY_PLATFORM]=${BUILD_CONFIG[CONFIGURE_ARGS_FOR_ANY_PLATFORM]:-$configure_args_for_any_platform}
}

# Different platforms have different default make commands
# shellcheck disable=SC2153
setMakeCommandForOS() {
  local make_command_name
  case "$OS_KERNEL_NAME" in
  "aix")
    make_command_name="gmake"
  ;;
  "SunOS")
    make_command_name="gmake"
  ;;
  esac

  BUILD_CONFIG[MAKE_COMMAND_NAME]=${BUILD_CONFIG[MAKE_COMMAND_NAME]:-$make_command_name}
}

################################################################################

configure_build() {
    configDefaults

    # Parse the CL Args, see ${SCRIPT_DIR}/configureBuild.sh for details
    parseCommandLineArgs "$@"

    # Update the configuration with the arguments passed in, the platform etc
    setVariablesForConfigure
    setRepository
    processArgumentsforSpecificPlatforms
    processArgumentsforSpecificArchitectures
    setMakeCommandForOS

    determineBuildProperties
    sourceSignalHandler
    doAnyBuildVariantOverrides
    setWorkingDirectory
}
