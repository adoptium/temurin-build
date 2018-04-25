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
# TODO rewrite the doc here
#
# Script to clone the OpenJDK source then build it
#
# Optionally uses Docker, otherwise you can provide two arguments:
# the area to build the JDK e.g. $HOME/mybuilddir as -s or --source and the
# target destination for the tar.gz e.g. -d or --destination $HOME/mytargetdir
# Both must be absolute paths! You can use $PWD/mytargetdir
#
# To install dependencies persistently is to use our Ansible playbooks
#
# You can set the JDK boot directory with the JDK_BOOT_DIR environment variable
#
################################################################################

set -eux # TODO remove once we've finished debugging

# i.e. Where we are
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Load the common functions
# shellcheck source=sbin/common-functions.sh
#source "$SCRIPT_DIR/sbin/common-functions.sh"

init_build_config() {
  # The name of the directory where we clone the OpenJDK source code for
  # building, defaults to 'openjdk'
  # TODO Note sure if setting this openjdk default is a good idea...

  BUILD_CONFIG[OPENJDK_SOURCE_DIR]=${BUILD_CONFIG[OPENJDK_SOURCE_DIR]:-openjdk}

  # Repo to pull the OpenJDK source from, defaults to AdoptOpenJDK/openjdk-jdk8u
  BUILD_CONFIG[REPOSITORY]=${BUILD_CONFIG[REPOSITORY]:-"AdoptOpenJDK/openjdk-jdk8u"}

  # By default only git clone the HEAD commit
  BUILD_CONFIG[SHALLOW_CLONE_OPTION]="--depth=1"

  # Set Docker Container names and defaults
  BUILD_CONFIG[DOCKER_SOURCE_VOLUME_NAME]="openjdk-source-volume"
  BUILD_CONFIG[CONTAINER_NAME]=openjdk_container
  BUILD_CONFIG[TMP_CONTAINER_NAME]=openjdk-copy-src
  BUILD_CONFIG[CLEAN_DOCKER_BUILD]=false
  BUILD_CONFIG[TARGET_DIR_IN_THE_CONTAINER]="/openjdk/target/"

  # Copy the results of the docker build (defaults to false)
  BUILD_CONFIG[COPY_TO_HOST]=false

  # Use Docker to build (defaults to false)
  BUILD_CONFIG[USE_DOCKER]=false

  # Location of DockerFile and where scripts get copied to inside the container
  BUILD_CONFIG[DOCKER_BUILD_PATH]=""

  # Whether we keep the Docker image after we build it
  BUILD_CONFIG[KEEP]=false

  # The current working directory
  BUILD_CONFIG[WORKING_DIR]=""

  # Root of the workspace
  BUILD_CONFIG[WORKSPACE_DIR]=""

  # Use SSH for the GitHub connection (defaults to false)
  BUILD_CONFIG[USE_SSH]=false

  # Director where OpenJDK binary gets built to
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

  # Whether we execute the jtreg tests
  BUILD_CONFIG[JTREG]=false

  # Any extra args provided by the user
  BUILD_CONFIG[USER_SUPPLIED_CONFIGURE_ARGS]=""

  BUILD_CONFIG[DOCKER]="docker"

  # Print to console using colour codes
  BUILD_CONFIG[COLOUR]="true"
}

sourceFileWithColourCodes()
{
  if [[ "${BUILD_CONFIG[COLOUR]}" = true ]] ; then
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
  while [[ $# -gt 0 ]] && [[ ."$1" = .-* ]] ; do
    opt="$1";
    shift;
    case "$opt" in
      "--" ) break 2;;

      "--source" | "-s" )
      BUILD_CONFIG[WORKING_DIR]="$1"; shift;;

      "--ssh" | "-S" )
      BUILD_CONFIG[USE_SSH]=true;;

      "--destination" | "-d" )
      BUILD_CONFIG[TARGET_DIR]="$1"; shift;;

      "--repository" | "-r" )
      BUILD_CONFIG[REPOSITORY]="$1"; shift;;

      "--branch" | "-b" )
      BUILD_CONFIG[BRANCH]="$1"; shift;;

      "--tag" | "-t" )
      BUILD_CONFIG[TAG]="$1"; BUILD_CONFIG[SHALLOW_CLONE_OPTION]=""; shift;;

      "--keep" | "-k" )
      BUILD_CONFIG[KEEP]=true;;

      "--clean-docker-build" | "-c" )
      BUILD_CONFIG[CLEAN_DOCKER_BUILD]=true;;

      "--jtreg" | "-j" )
      BUILD_CONFIG[JTREG]=true;;

      "--jtreg-subsets" | "-js" )
      BUILD_CONFIG[JTREG]=true; BUILD_CONFIG[JTREG_TEST_SUBSETS]="$1"; shift;;

      "--no-colour" | "-nc" )
      BUILD_CONFIG[COLOUR]=false;;

      "--sign" )
      BUILD_CONFIG[SIGN]=true; BUILD_CONFIG[CERTIFICATE]="$1"; shift;;

      "--disable-shallow-git-clone" | "-dsgc" )
      BUILD_CONFIG[SHALLOW_CLONE_OPTION]=""; shift;;

      "--skip-freetype" | "-sf" )
      BUILD_CONFIG[FREETYPE]=false;;

      "--freetype-dir" | "-ftd" )
      BUILD_CONFIG[FREETYPE_DIRECTORY]="$1"; shift;;

      "--variant"  | "-bv" )
      BUILD_CONFIG[BUILD_VARIANT]="$1"; shift;;

      "--configure-args"  | "-ca" )
      BUILD_CONFIG[USER_SUPPLIED_CONFIGURE_ARGS]="$1"; shift;;

      "--sudo" | "-s" )
      BUILD_CONFIG[DOCKER]="sudo /usr/bin/docker";;

      *) echo >&2 "${error}Invalid option: ${opt}${normal}"; man ./makejdk-any-platform.1; exit 1;;
     esac
  done

  # Now that we've processed the flags, grab the mandatory argument(s)
  BUILD_CONFIG[OPENJDK_FOREST_NAME]=$1
  BUILD_CONFIG[OPENJDK_CORE_VERSION]=${BUILD_CONFIG[OPENJDK_FOREST_NAME]}

  # 'u' means it's an update repo, e.g. jdk8u
  if [[ ${BUILD_CONFIG[OPENJDK_FOREST_NAME]} == *u ]]; then
    BUILD_CONFIG[OPENJDK_CORE_VERSION]=${BUILD_CONFIG[OPENJDK_FOREST_NAME]%?}
  fi

  # TODO check that OPENJDK_CORE_VERSION and other mandatory flags have been set by the caller
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

# TODO refactor - surely we just want to check if the user has passed in a useDocker flag
checkIfDockerIsUsedForBuildingOrNot()
{
  # If both a working dir and a target dir provided then build natively
  if [ ! -z "${BUILD_CONFIG[WORKING_DIR]}" ] && [ ! -z "${BUILD_CONFIG[TARGET_DIR]}" ] ; then
    # This uses sbin/build.sh directly
    echo "${info}Not using Docker, working area will be ${BUILD_CONFIG[WORKING_DIR]}, target for the JDK will be ${BUILD_CONFIG[TARGET_DIR]} ${normal}"
  fi

  # If working directory and target directory are not provided, then use docker
  if [ -z "${BUILD_CONFIG[WORKING_DIR]}" ] && [ -z "${BUILD_CONFIG[TARGET_DIR]}" ] ; then
    echo "${info}No parameters provided, using Docker. ${normal}"
    BUILD_CONFIG[USE_DOCKER]=true
  elif [ ! -z "${BUILD_CONFIG[TARGET_DIR]}" ] && [ -z "${BUILD_CONFIG[WORKING_DIR]}" ] ; then
    # Target directory is defined but the working directory isn't
    # Calls sbin/build.sh inside of Docker followed by a docker cp command
    echo "${info}Using Docker, target directory for the tgz on the host: ${BUILD_CONFIG[TARGET_DIR]}"
    BUILD_CONFIG[USE_DOCKER]=true
  fi
}

# TODO Check what this flag does when not using docker
checkIfDockerIsUsedShouldTheContainerBePreserved()
{
  echo "${info}"
  if [ "${BUILD_CONFIG[KEEP]}" == "true" ] ; then
    echo "We'll keep the built Docker container."
  else
    echo "The --keep, -k flag was not set so we'll remove any pre-existing Docker container and build a new one."
  fi
  echo "${normal}"
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
       BUILD_CONFIG[WORKSPACE_DIR]=$PWD;
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
    BUILD_CONFIG[TARGET_DIR]=$PWD
    # Only makes a difference if we're in Docker
    echo "If you're using Docker, the build artifact will *NOT* be copied to the host (as you did not specify your own TARGET_DIR)."
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
    checkIfDockerIsUsedForBuildingOrNot
    checkIfDockerIsUsedShouldTheContainerBePreserved
    setDefaultBranchIfNotProvided
    setWorkingDirectory
    setTargetDirectory
}
