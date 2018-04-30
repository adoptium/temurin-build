#!/usr/bin/env bash

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
# This shell script deals with writing the AdoptOpenJDK build configuration to
# the file system so it can be picked up by further build steps, Docker
# containers etc
#
# We are deliberately writing to shell because this needs to work on some truly
# esoteric platforms to fulfil the Java Write Once Run Anywhere (WORA) promise
#
################################################################################


# We can't use Bash 4.x+ associative arrays as as Apple won't support bash 4.0
# (because of GPL3), we therefore have to name the indexes of the CONFIG_PARAMS
# map. This is why we can't have nice things.
CONFIG_PARAMS=(
OS_KERNEL_NAME
OS_ARCHITECTURE
OPENJDK_FOREST_NAME
OPENJDK_CORE_VERSION
BUILD_VARIANT
REPOSITORY
CONFIGURE_ARGS_FOR_ANY_PLATFORM
JDK_PATH
JRE_PATH
COPY_MACOSX_FREE_FONT_LIB_FOR_JDK_FLAG
COPY_MACOSX_FREE_FONT_LIB_FOR_JRE_FLAG
FREETYPE_FONT_BUILD_TYPE_PARAM
FREETYPE_FONT_VERSION
JVM_VARIANT
BUILD_FULL_NAME
MAKE_ARGS_FOR_ANY_PLATFORM
MAKE_COMMAND_NAME
OPENJDK_SOURCE_DIR
SHALLOW_CLONE_OPTION
DOCKER_SOURCE_VOLUME_NAME
CONTAINER_NAME
TMP_CONTAINER_NAME
CLEAN_DOCKER_BUILD
COPY_TO_HOST
USE_DOCKER
DOCKER_BUILD_PATH
KEEP
WORKING_DIR
USE_SSH
TARGET_DIR
BRANCH
TAG
OPENJDK_UPDATE_VERSION
OPENJDK_BUILD_NUMBER
JTREG
USER_SUPPLIED_CONFIGURE_ARGS
DOCKER
COLOUR
WORKSPACE_DIR
FREETYPE
FREETYPE_DIRECTORY
SIGN
JDK_BOOT_DIR
)


# Directory structure of build environment:
###########################################################################################################################################
#  Dir                                                 Purpose                              Docker Default            Native default
###########################################################################################################################################
#  <WORKSPACE_DIR>                                     Root                                 /openjdk/                   $(pwd)/workspace/
#  <WORKSPACE_DIR>/config                              Configuration                        /openjdk/config             $(pwd)/workspace/config
#  <WORKSPACE_DIR>/<WORKING_DIR>                       Build area                           /openjdk/build              $(pwd)/workspace/build/
#  <WORKSPACE_DIR>/<WORKING_DIR>/<OPENJDK_SOURCE_DIR>  Source code                          /openjdk/build/src          $(pwd)/workspace/build/src
#  <WORKSPACE_DIR>/target                              Destination of built artifacts       /openjdk/target             $(pwd)/workspace/target



# Helper code to perform index lookups by name
declare -a -x PARAM_LOOKUP
for index in $(seq 0 $(expr ${#CONFIG_PARAMS[@]} - 1))
do
    paramName=${CONFIG_PARAMS[$index]};
    eval declare -r -x "$paramName=$index"
    PARAM_LOOKUP[$index]=$paramName
done

function displayParams() {
    set +x
    echo "# ============================"
    echo "# OPENJDK BUILD CONFIGURATION:"
    echo "# ============================"
    for K in "${!BUILD_CONFIG[@]}";
    do
      echo "BUILD_CONFIG[${PARAM_LOOKUP[$K]}]=\"${BUILD_CONFIG[$K]}\""
    done | sort
    set -x
}

function writeConfigToFile() {
  if [ ! -d "workspace/config" ]
  then
    mkdir -p "workspace/config"
  fi
  displayParams > ./workspace/config/built_config.cfg
}

function loadConfigFromFile() {
  if [ -f "$SCRIPT_DIR/../config/built_config.cfg" ]
  then
    source "$SCRIPT_DIR/../config/built_config.cfg"
  elif [ -f "config/built_config.cfg" ]
  then
    source config/built_config.cfg
  elif [ -f "workspace/config/built_config.cfg" ]
  then
    source workspace/config/built_config.cfg
  elif [ -f "built_config.cfg" ]
  then
    source built_config.cfg
  else
    echo "Failed to find configuration"
    exit
  fi
}

# Declare the map of build configuration that we're going to use
declare -ax BUILD_CONFIG
export BUILD_CONFIG

# The OS kernel name, e.g. 'darwin' for Mac OS X
BUILD_CONFIG[OS_KERNEL_NAME]=$(uname | awk '{print tolower($0)}')

# The O/S architecture, e.g. x86_64 for a modern intel / Mac OS X
BUILD_CONFIG[OS_ARCHITECTURE]=$(uname -m)

# The full forest name, e.g. jdk8, jdk8u, jdk9, jdk9u, etc.
BUILD_CONFIG[OPENJDK_FOREST_NAME]=""

# The abridged openjdk core version name, e.g. jdk8, jdk9, etc.
BUILD_CONFIG[OPENJDK_CORE_VERSION]=""

# The build variant, e.g. openj9
BUILD_CONFIG[BUILD_VARIANT]=""

# The OpenJDK source code repository to build from, e.g. an AdoptOpenJDK repo
BUILD_CONFIG[REPOSITORY]=""

BUILD_CONFIG[COPY_MACOSX_FREE_FONT_LIB_FOR_JDK_FLAG]=""
BUILD_CONFIG[COPY_MACOSX_FREE_FONT_LIB_FOR_JRE_FLAG]=""
BUILD_CONFIG[FREETYPE]=true
BUILD_CONFIG[FREETYPE_DIRECTORY]=""
BUILD_CONFIG[FREETYPE_FONT_VERSION]="2.4.0"
BUILD_CONFIG[FREETYPE_FONT_BUILD_TYPE_PARAM]=""

BUILD_CONFIG[MAKE_COMMAND_NAME]="make"
BUILD_CONFIG[SIGN]="false"
BUILD_CONFIG[JDK_BOOT_DIR]=""
