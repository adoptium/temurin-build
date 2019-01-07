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
#
################################################################################

################################################################################
#
# This script sets up the initial configuration for an (Adopt) OpenJDK Build.
# See the configure_build function and its child functions for details.
# It's sourced by the makejdk-any-platform.sh script.
#
################################################################################

set -eu

# i.e. Where we are
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# shellcheck source=sbin/common/constants.sh
source "$SCRIPT_DIR/sbin/common/constants.sh"

# shellcheck source=sbin/common/common.sh
source "$SCRIPT_DIR/sbin/common/common.sh"

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
    setDockerVolumeSuffix "$1"
  fi
}

# Extra config for OpenJDK variants such as OpenJ9, SAP et al
# shellcheck disable=SC2153
doAnyBuildVariantOverrides()
{
  if [[ "${BUILD_CONFIG[BUILD_VARIANT]}" == "SapMachine" ]]
  then
    local branch="sapmachine10"
    BUILD_CONFIG[BRANCH]=${branch:-${BUILD_CONFIG[BRANCH]}};
  fi
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
  if [ "$openjdk_core_version" == "${JDK9_CORE_VERSION}" ] || \
    [ "$openjdk_core_version" == "${JDK10_CORE_VERSION}" ] || \
    [ "$openjdk_core_version" == "${JDK11_CORE_VERSION}" ] || \
    [ "$openjdk_core_version" == "${AMBER_CORE_VERSION}" ] || \
    [ "$openjdk_core_version" == "${JDKHEAD_CORE_VERSION}" ]; then
    local jdk_path="jdk"
    local jre_path="jre"
    case "${BUILD_CONFIG[OS_KERNEL_NAME]}" in
    "darwin")
      local jdk_path="jdk-bundle/jdk-*.jdk"
      local jre_path="jre-bundle/jre-*.jre"
    ;;
    esac
    #BUILD_CONFIG[CONFIGURE_ARGS_FOR_ANY_PLATFORM]=${BUILD_CONFIG[CONFIGURE_ARGS_FOR_ANY_PLATFORM]:-"--disable-warnings-as-errors"}
  elif [ "$openjdk_core_version" == "${JDK8_CORE_VERSION}" ]; then
    local jdk_path="j2sdk-image"
    local jre_path="j2re-image"
    case "${BUILD_CONFIG[OS_KERNEL_NAME]}" in
    "darwin")
      local jdk_path="j2sdk-bundle/jdk*.jdk"
      local jre_path="j2re-bundle/jre*.jre"
    ;;
    esac
  else
    echo "Please specify a version, either jdk8u, jdk9, jdk10, amber etc, with or without a 'u' suffix. e.g. $0 [options] jdk8u"
    exit 1
  fi

  BUILD_CONFIG[JDK_PATH]=$jdk_path
  BUILD_CONFIG[JRE_PATH]=$jre_path
}


# Set the repository to build from, defaults to AdoptOpenJDK if not set by the user
# shellcheck disable=SC2153
setRepository() {

  local repository;

  # Location of Extensions for OpenJ9 project
  if [[ "${BUILD_CONFIG[BUILD_VARIANT]}" == "openj9" ]]
  then
    if [[ "${BUILD_CONFIG[USE_SSH]}" == "true" ]] ; then
      repository="git@github.com:ibmruntimes/openj9-openjdk-${BUILD_CONFIG[OPENJDK_CORE_VERSION]}";
    else
      repository="https://github.com/ibmruntimes/openj9-openjdk-${BUILD_CONFIG[OPENJDK_CORE_VERSION]}";
    fi
  elif [[ "${BUILD_CONFIG[BUILD_VARIANT]}" == "SapMachine" ]]
  then
    # TODO need to map versions to SAP branches going forwards
    # sapmachine10 is the current branch for OpenJDK10 mainline
    # (equivalent to jdk/jdk10 on hotspot)
    if [[ "${BUILD_CONFIG[USE_SSH]}" == "true" ]]
    then
      repository="git@github.com:SAP/SapMachine";
    else
      repository="https://github.com/SAP/SapMachine";
    fi
  else
    if [[ "${BUILD_CONFIG[USE_SSH]}" == "true" ]] ; then
      repository="git@github.com:adoptopenjdk/openjdk-${BUILD_CONFIG[OPENJDK_FOREST_NAME]}";
    else
      repository="https://github.com/adoptopenjdk/openjdk-${BUILD_CONFIG[OPENJDK_FOREST_NAME]}";
    fi
  fi

  repository="$(echo "${repository}" | awk '{print tolower($0)}')";

  BUILD_CONFIG[REPOSITORY]="${BUILD_CONFIG[REPOSITORY]:-${repository}}";
}

# Specific platforms need to have special build settings
processArgumentsforSpecificPlatforms() {

  case "${BUILD_CONFIG[OS_KERNEL_NAME]}" in
  "darwin")
    if [ "${BUILD_CONFIG[OPENJDK_CORE_VERSION]}" == "${JDK8_CORE_VERSION}" ] ; then
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
    if [ "${BUILD_CONFIG[OPENJDK_CORE_VERSION]}" == "${JDK8_CORE_VERSION}" ] && [ "${BUILD_CONFIG[BUILD_VARIANT]}" != "openj9" ]; then
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

    if [ "$(command -v rpm)" ]; then
      # shellcheck disable=SC1083
      BUILD_CONFIG[FREETYPE_FONT_BUILD_TYPE_PARAM]=${BUILD_CONFIG[FREETYPE_FONT_BUILD_TYPE_PARAM]:="--build=$(rpm --eval %{_host})"}
    fi

  ;;

  "armv7l")
    if [ "${BUILD_CONFIG[OPENJDK_CORE_VERSION]}" == "${JDK8_CORE_VERSION}" ] && [ "${BUILD_CONFIG[BUILD_VARIANT]}" == "hotspot" ]; then
      jvm_variant=zero
    else
      jvm_variant=server
    fi
    make_args_for_any_platform="DEBUG_BINARIES=true images"
    configure_args_for_any_platform="--with-jobs=${NUM_PROCESSORS}"
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
  "sunos")
    make_command_name="gmake"
  ;;
  esac

  BUILD_CONFIG[MAKE_COMMAND_NAME]=${BUILD_CONFIG[MAKE_COMMAND_NAME]:-$make_command_name}
}

function configureMacFreeFont() {
    if [ "${BUILD_CONFIG[OPENJDK_CORE_VERSION]}" == "${JDK9_VERSION}" ]; then
        BUILD_CONFIG[COPY_MACOSX_FREE_FONT_LIB_FOR_JDK_FLAG]="true";
        BUILD_CONFIG[COPY_MACOSX_FREE_FONT_LIB_FOR_JRE_FLAG]="true";
    fi

    if [ "${BUILD_CONFIG[OPENJDK_CORE_VERSION]}" == "${JDK8_VERSION}" ]; then
        BUILD_CONFIG[COPY_MACOSX_FREE_FONT_LIB_FOR_JDK_FLAG]="false";
        BUILD_CONFIG[COPY_MACOSX_FREE_FONT_LIB_FOR_JRE_FLAG]="true";
    fi

    echo "[debug] COPY_MACOSX_FREE_FONT_LIB_FOR_JDK_FLAG=${BUILD_CONFIG[COPY_MACOSX_FREE_FONT_LIB_FOR_JDK_FLAG]}"
    echo "[debug] COPY_MACOSX_FREE_FONT_LIB_FOR_JRE_FLAG=${BUILD_CONFIG[COPY_MACOSX_FREE_FONT_LIB_FOR_JRE_FLAG]}"
}

function setMakeArgs() {
    echo "JDK Image folder name: ${BUILD_CONFIG[JDK_PATH]}"
    echo "JRE Image folder name: ${BUILD_CONFIG[JRE_PATH]}"

    if [ "${BUILD_CONFIG[OPENJDK_CORE_VERSION]}" == "${JDK11_VERSION}" ] || [ "${BUILD_CONFIG[OPENJDK_CORE_VERSION]}" == "${JDKHEAD_VERSION}" ]; then
      case "${BUILD_CONFIG[OS_KERNEL_NAME]}" in
      "darwin") BUILD_CONFIG[MAKE_ARGS_FOR_ANY_PLATFORM]=${BUILD_CONFIG[MAKE_ARGS_FOR_ANY_PLATFORM]:-"product-images mac-legacy-jre-bundle"} ;;
      *) BUILD_CONFIG[MAKE_ARGS_FOR_ANY_PLATFORM]=${BUILD_CONFIG[MAKE_ARGS_FOR_ANY_PLATFORM]:-"product-images legacy-jre-image"} ;;
      esac
    else
      BUILD_CONFIG[MAKE_ARGS_FOR_ANY_PLATFORM]=${BUILD_CONFIG[MAKE_ARGS_FOR_ANY_PLATFORM]:-"images"}
    fi

    BUILD_CONFIG[CONFIGURE_ARGS_FOR_ANY_PLATFORM]=${BUILD_CONFIG[CONFIGURE_ARGS_FOR_ANY_PLATFORM]:-""}
}

function setBootJdk() {
  if [ -z "${BUILD_CONFIG[JDK_BOOT_DIR]}" ] ; then
    echo "Searching for JDK_BOOT_DIR"

    # shellcheck disable=SC2046,SC2230
    if [[ "${BUILD_CONFIG[OS_KERNEL_NAME]}" == "darwin" ]]; then
      BUILD_CONFIG[JDK_BOOT_DIR]=$(dirname $(dirname $(readlink $(which javac))))
    else
      BUILD_CONFIG[JDK_BOOT_DIR]=$(dirname $(dirname $(readlink -f $(which javac))))
    fi

    echo "Guessing JDK_BOOT_DIR: ${BUILD_CONFIG[JDK_BOOT_DIR]}"
    echo "If this is incorrect explicitly configure JDK_BOOT_DIR"
  else
    echo "Overriding JDK_BOOT_DIR, set to ${BUILD_CONFIG[JDK_BOOT_DIR]}"
  fi

  echo "Boot dir set to ${BUILD_CONFIG[JDK_BOOT_DIR]}"
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
    configureMacFreeFont
    setMakeArgs
    setBootJdk
}
