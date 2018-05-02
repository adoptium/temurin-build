#!/bin/bash

################################################################################
#
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
# Entry point to build (Adopt) OpenJDK binaries for any platform.
#
# 1. Source scripts to support configuration, docker builds and native builds.
# 2. Parse the Command Line Args
# 3. Set a host of configuration options based on args, platform etc
# 4. Display and then persist those configuration options
# 5. Build the binary in Docker or natively
#
################################################################################

# TODO Comment out once script is stable.
set -eux

# i.e. Where we are
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Pull in configuration and build support
source "${SCRIPT_DIR}/sbin/config_init.sh"
source "${SCRIPT_DIR}/docker-build.sh"
source "${SCRIPT_DIR}/native-build.sh"
source "${SCRIPT_DIR}/configureBuild.sh"

# Set variables that the `configure` command (which builds OpenJDK) will need
setVariablesForConfigure() {

  local openjdk_core_version=${BUILD_CONFIG[OPENJDK_CORE_VERSION]}

  # TODO Regex this in the if or use cut to grab out the number and see if >= 9
  # TODO 9 should become 9u as will 10 shortly....
  if [ "$openjdk_core_version" == "jdk9" ] || [ "$openjdk_core_version" == "jdk10" ] || [ "$openjdk_core_version" == "jdk11" ] || [ "$openjdk_core_version" == "amber" ]; then
    local jdk_path="jdk"
    local jre_path="jre"
    BUILD_CONFIG[CONFIGURE_ARGS_FOR_ANY_PLATFORM]=${BUILD_CONFIG[CONFIGURE_ARGS_FOR_ANY_PLATFORM]:-"--disable-warnings-as-errors"}
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

echo "Starting $0 to configure, build (Adopt)OpenJDK binary"

# Parse the CL Args, see ${SCRIPT_DIR}/configureBuild.sh for details
parseCommandLineArgs "$@"

# Update the configuration with the arguments passed in, the platform etc
setVariablesForConfigure
setRepository
processArgumentsforSpecificPlatforms
processArgumentsforSpecificArchitectures
setMakeCommandForOS

# Configure the build, display the parameters and write the config to disk
# see ${SCRIPT_DIR}/sbin/config_init.sh for details
configure_build "$@"
writeConfigToFile

# Let's build and test the (Adopt) OpenJDK binary in Docker or natively
if [ "${BUILD_CONFIG[USE_DOCKER]}" == "true" ] ; then
  buildOpenJDKViaDocker
else
  buildOpenJDKInNativeEnvironment
fi



