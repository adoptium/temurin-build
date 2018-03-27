#!/bin/bash
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

################################################################################################
# TODO rewrite hte doc here

#
# Script to clone the OpenJDK source then build it

# Optionally uses Docker, otherwise you can provide two arguments:
# the area to build the JDK e.g. $HOME/mybuilddir as -s or --source
# and the target destination for the tar.gz e.g. -d or --destination $HOME/mytargetdir
# Both must be absolute paths! You can use $PWD/mytargetdir

# A simple way to install dependencies persistently is to use our Ansible playbooks

# You can set the JDK boot directory with the JDK_BOOT_DIR environment variable
#
################################################################################################

# set -x # TODO remove once we've finished debugging

# TODO This only exists for backwards compatibility - remove once all jenkins jobs have migrated
OS_ARCHITECTURE=$OS_MACHINE_NAME

# i.e. Where we are
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Load the common functions
# shellcheck source=sbin/common-functions.sh
source "$SCRIPT_DIR/sbin/common-functions.sh"

# The name of the directory where we clone the OpenJDK source code for building, defaults to 'openjdk'
# TODO Note sure if setting this openjdk default is a good idea...
OPENJDK_SOURCE_DIR=${OPENJDK_SOURCE_DIR:-openjdk}

# The repository to pull the OpenJDK source from, defaults to AdoptOpenJDK/openjdk-jdk8u
REPOSITORY=${REPOSITORY:-"AdoptOpenJDK/openjdk-jdk8u"}

# By default only git clone the HEAD commit
SHALLOW_CLONE_OPTION="--depth=1"

# Set Docker Container names and defaults
DOCKER_SOURCE_VOLUME_NAME="openjdk-source-volume"
CONTAINER_NAME=openjdk_container
TMP_CONTAINER_NAME=openjdk-copy-src
CLEAN_DOCKER_BUILD=false
TARGET_DIR_IN_THE_CONTAINER="/openjdk/target/"

# Copy the results of the docker build (defaults to false)
export COPY_TO_HOST=false

# Use Docker to build (defaults to false)
export USE_DOCKER=false

# The location of the DockerFile and where scripts get copied to for a build inside a Docker container
DOCKER_BUILD_PATH=""

# Whether we keep the Docker image after we build it
KEEP=false

# The current working directory
WORKING_DIR=""

# Use SSH for the GitHub connection (defaults to false)
USE_SSH=false

# Director where OpenJDK binary gets built to
TARGET_DIR=""

# Which repo branch to build, e.g. dev
BRANCH=""

# Which repo tag to build, e.g. jdk8u172-b03
TAG=""

# Update version e.g. 172
OPENJDK_UPDATE_VERSION=""

# build number e.g. b03
OPENJDK_BUILD_NUMBER=""

# Build variant, e.g. openj9, defaults to "" which means hotspot
BUILD_VARIANT=${BUILD_VARIANT:-""}

# JVM variant, e.g. client or server, defaults to server
JVM_VARIANT=${JVM_VARIANT:-server}

# Whether we execute the jtreg tests
JTREG=false

# Any extra args provided by the user
USER_SUPPLIED_CONFIGURE_ARGS=""

# TODO This function is in sbin/common-functions.sh
determineBuildProperties

sourceFileWithColourCodes()
{
  if [[ -z "${COLOUR}" ]] ; then
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
      WORKING_DIR="$1"; shift;;

      "--ssh" | "-S" )
      USE_SSH=true;;

      "--destination" | "-d" )
      TARGET_DIR="$1"; shift;;

      "--repository" | "-r" )
      REPOSITORY="$1"; shift;;

      "--branch" | "-b" )
      BRANCH="$1"; shift;;

      "--tag" | "-t" )
      TAG="$1"; SHALLOW_CLONE_OPTION=""; shift;;

      "--keep" | "-k" )
      KEEP=true;;

      "--clean-docker-build" | "-c" )
      CLEAN_DOCKER_BUILD=true;;

      "--jtreg" | "-j" )
      JTREG=true;;

      "--jtreg-subsets" | "-js" )
      JTREG=true; JTREG_TEST_SUBSETS="$1"; shift;;

      "--no-colour" | "-nc" )
      COLOUR=false;;

      "--sign" )
      export SIGN=true; export CERTIFICATE="$1"; shift;;

      "--disable-shallow-git-clone" | "-dsgc" )
      SHALLOW_CLONE_OPTION=""; shift;;

      "--skip-freetype" | "-sf" )
      export FREETYPE=false;;

      "--freetype-dir" | "-ftd" )
      export FREETYPE_DIRECTORY="$1"; shift;;

      "--variant"  | "-bv" )
      export BUILD_VARIANT="$1"; shift;;

      "--configure-args"  | "-ca" )
      export USER_SUPPLIED_CONFIGURE_ARGS="$1"; shift;;

      *) echo >&2 "${error}Invalid option: ${opt}${normal}"; man ./makejdk-any-platform.1; exit 1;;
     esac
  done

  # Now that we've processed the flags, grab the mandatory argument(s)
  OPENJDK_FOREST_NAME=$(echo "$1" | awk "{print $string}")
  export OPENJDK_CORE_VERSION=${OPENJDK_FOREST_NAME}

  # 'u' means it's an update repo, e.g. jdk8u
  if [[ ${OPENJDK_FOREST_NAME} == *u ]]; then
    export OPENJDK_CORE_VERSION=${OPENJDK_FOREST_NAME%?}
  fi

  # TODO check that OPENJDK_CORE_VERSION and other mandatory flags have been set by the caller
}

doAnyBuildVariantOverrides()
{
  if [[ "${BUILD_VARIANT}" == "openj9" ]]; then
    # current (hoping not final) location of Extensions for OpenJDK9 for OpenJ9 project
    REPOSITORY="ibmruntimes/openj9-openjdk-${OPENJDK_CORE_VERSION}"
    BRANCH="openj9"
  fi
  if [[ "${BUILD_VARIANT}" == "SapMachine" ]]; then
    # current location of SAP variant
    REPOSITORY="SAP/SapMachine"
    BRANCH="sapmachine10" # sapmachine10 is the current branch for OpenJDK10 mainline (equivalent to jdk/jdk10)
  fi
}

# TODO refactor - surely we just want to check if the user has passed in a useDocker flag
checkIfDockerIsUsedForBuildingOrNot()
{
  # If both a working directory and a target directory provided then build natively
  if [ ! -z "$WORKING_DIR" ] && [ ! -z "$TARGET_DIR" ] ; then
    # This uses sbin/build.sh directly
    echo "${info}Not using Docker, working area will be ${WORKING_DIR}, target for the JDK will be ${TARGET_DIR} ${normal}"
  fi

  # If working directory and target directory are not provided, then use docker
  if [ -z "${WORKING_DIR}" ] && [ -z "${TARGET_DIR}" ] ; then
    echo "${info}No parameters provided, using Docker. ${normal}"
    USE_DOCKER=true
  elif [ ! -z "$TARGET_DIR" ] && [ -z "$WORKING_DIR" ] ; then
    # Target directory is defined but the working directory isn't
    # Calls sbin/build.sh inside of Docker followed by a docker cp command
    echo "${info}Using Docker, target directory for the tgz on the host: ${TARGET_DIR}"
    USE_DOCKER=true
  fi
}

# TODO Check what this flag does when not using docker
checkIfDockerIsUsedShouldTheContainerBePreserved()
{
  echo "${info}"
  if [ "${KEEP}" == "true" ] ; then
    echo "We'll keep the built Docker container."
  else
    echo "The --keep, -k flag was not set so we'll remove any pre-existing Docker container and build a new one."
  fi
  echo "${normal}"
}

setDefaultBranchIfNotProvided()
{
  if [ -z "$BRANCH" ] ; then
    echo "${info}BRANCH is undefined so checking out dev${normal}."
    BRANCH="dev"
  fi
}

setWorkingDirectory()
{
  if [ -z "${WORKING_DIR}" ] ; then
    echo "${info}WORKING_DIR is undefined so setting to ${PWD}${normal}."
    WORKING_DIR=$PWD
  else
    echo "${info}Working dir is ${WORKING_DIR}${normal}"
  fi
}

setTargetDirectory()
{
  if [ -z "${TARGET_DIR}" ] ; then
    echo "${info}TARGET_DIR is undefined so setting to $PWD."
    TARGET_DIR=$PWD
    # Only makes a difference if we're in Docker
    echo "If you're using Docker, the build artifact will *NOT* be copied to the host (as you did not specify your own TARGET_DIR)."
  else
    echo "${info}Target directory is ${TARGET_DIR}${normal}"
    COPY_TO_HOST=true
    echo "If you're using Docker, the build artifact will be copied to the host."
  fi
}

# TODO refactor this for SRP
checkoutAndCloneOpenJDKGitRepo()
{
  echo "${git}"
  # Check that we have a git repo of a valid openjdk version on our local file system
  if [ -d "${WORKING_DIR}/${OPENJDK_SOURCE_DIR}/.git" ] && ( [ "$OPENJDK_CORE_VERSION" == "jdk8" ] || [ "$OPENJDK_CORE_VERSION" == "jdk9" ] || [ "$OPENJDK_CORE_VERSION" == "jdk10" ]) ; then
    OPENJDK_GIT_REPO_OWNER=$(git --git-dir "${WORKING_DIR}/${OPENJDK_SOURCE_DIR}/.git" remote -v | grep "${OPENJDK_CORE_VERSION}")
    echo "OPENJDK_GIT_REPO_OWNER=${OPENJDK_GIT_REPO_OWNER}"

    # If the local copy of the git source repo is valid then we reset appropriately
    if [ "${OPENJDK_GIT_REPO_OWNER}" ]; then
      cd "${WORKING_DIR}/${OPENJDK_SOURCE_DIR}" || return
      echo "${info}Resetting the git openjdk source repository at $PWD in 10 seconds...${git}"
      sleep 10
      echo "${git}Pulling latest changes from git openjdk source repository"

      showShallowCloningMessage "fetch"
      git fetch --all ${SHALLOW_CLONE_OPTION}
      git reset --hard origin/$BRANCH
      if [ ! -z "$TAG" ]; then
        git checkout "$TAG"
      fi
      git clean -fdx
    else
      echo "Incorrect Source Code for ${OPENJDK_FOREST_NAME}.  This is an error, please check what is in $PWD and manually remove, exiting..."
      exit 1
    fi
    cd "${WORKING_DIR}" || return
  elif [ ! -d "${WORKING_DIR}/${OPENJDK_SOURCE_DIR}/.git" ] ; then
    # If it doesn't exist, clone it
    echo "${info}Didn't find any existing openjdk repository at ${WORKING_DIR} so cloning the source to openjdk"
    cloneOpenJDKGitRepo
  fi
  echo "${normal}"
}

cloneOpenJDKGitRepo()
{
  echo "${git}"
  if [[ "$USE_SSH" == "true" ]] ; then
     GIT_REMOTE_REPO_ADDRESS="git@github.com:${REPOSITORY}.git"
  else
     GIT_REMOTE_REPO_ADDRESS="https://github.com/${REPOSITORY}.git"
  fi

  showShallowCloningMessage "cloning"
  GIT_CLONE_ARGUMENTS=(${SHALLOW_CLONE_OPTION} '-b' "$BRANCH" "$GIT_REMOTE_REPO_ADDRESS" "${WORKING_DIR}/${OPENJDK_SOURCE_DIR}")

  echo "git clone ${GIT_CLONE_ARGUMENTS[*]}"
  git clone "${GIT_CLONE_ARGUMENTS[@]}"
  if [ ! -z "$TAG" ]; then
    cd "${WORKING_DIR}/${OPENJDK_SOURCE_DIR}" || exit 1
    git checkout "$TAG"
  fi

  # TODO extract this to its own function
  # Building OpenJDK with OpenJ9 must run get_source.sh to clone openj9 and openj9-omr repositories
  if [ "$BUILD_VARIANT" == "openj9" ]; then
    cd "${WORKING_DIR}/${OPENJDK_SOURCE_DIR}" || return
    bash get_source.sh
  fi
}

getOpenJDKUpdateAndBuildVersion()
{
  echo "${git}"

  if [ -d "${WORKING_DIR}/${OPENJDK_SOURCE_DIR}/.git" ]; then
    # It does exist and it's a repo other than the AdoptOpenJDK one
    cd "${WORKING_DIR}/${OPENJDK_SOURCE_DIR}" || return
    echo "${git}Pulling latest tags and getting the latest update version using git fetch -q --tags ${SHALLOW_CLONE_OPTION}"
    git fetch -q --tags "${SHALLOW_CLONE_OPTION}"
    OPENJDK_REPO_TAG=${TAG:-$(getFirstTagFromOpenJDKGitRepo)} # getFirstTagFromOpenJDKGitRepo resides in sbin/common-functions.sh
    if [[ "${OPENJDK_REPO_TAG}" == "" ]] ; then
     echo "${error}Unable to detect git tag, exiting..."
     exit 1
    else
     echo "OpenJDK repo tag is $OPENJDK_REPO_TAG"
    fi

    OPENJDK_UPDATE_VERSION=$(echo "${OPENJDK_REPO_TAG}" | cut -d'u' -f 2 | cut -d'-' -f 1)
    OPENJDK_BUILD_NUMBER=$(echo "${OPENJDK_REPO_TAG}" | cut -d'b' -f 2 | cut -d'-' -f 1)
    echo "Version: ${OPENJDK_UPDATE_VERSION} ${OPENJDK_BUILD_NUMBER}"
    cd "${WORKING_DIR}" || return

  fi

  echo "${normal}"
}

showShallowCloningMessage()
{
    mode=$1
    if [[ "$SHALLOW_CLONE_OPTION" == "" ]]; then
        echo "${info}Git repo ${mode} mode: deep (preserves commit history)${normal}"
    else
        echo "${info}Git repo ${mode} mode: shallow (DOES NOT contain commit history)${normal}"
    fi
}

testOpenJDKViaDocker()
{
  if [[ "$JTREG" == "true" ]]; then
    mkdir -p "${WORKING_DIR}/target"
    docker run \
    -v "${DOCKER_SOURCE_VOLUME_NAME}:/openjdk/build" \
    -v "${WORKING_DIR}/target:${TARGET_DIR_IN_THE_CONTAINER}" \
    --entrypoint /openjdk/sbin/jtreg.sh "${CONTAINER_NAME}"
  fi
}

# Create a data volume called $DOCKER_SOURCE_VOLUME_NAME,
# this gets mounted at /openjdk/build inside the container and is persistent between builds/tests
# unless -c is passed to this script, in which case it is recreated using the source
# in the current ./openjdk directory on the host machine (outside the container)
createPersistentDockerDataVolume()
{
  docker volume inspect $DOCKER_SOURCE_VOLUME_NAME > /dev/null 2>&1
  DATA_VOLUME_EXISTS=$?

  if [[ "$CLEAN_DOCKER_BUILD" == "true" || "$DATA_VOLUME_EXISTS" != "0" ]]; then
  
    echo "${info}Removing old volumes and containers${normal}"
    docker rm -f "$(docker ps -a --no-trunc | grep $CONTAINER_NAME | cut -d' ' -f1)" || true
    docker volume rm "${DOCKER_SOURCE_VOLUME_NAME}" || true

    echo "${info}Creating tmp container and copying src${normal}"
    docker volume create --name "${DOCKER_SOURCE_VOLUME_NAME}"
    docker run -v "${DOCKER_SOURCE_VOLUME_NAME}":/openjdk/build --name "$TMP_CONTAINER_NAME" ubuntu:14.04 /bin/bash
    docker cp openjdk "$TMP_CONTAINER_NAME":/openjdk/build/

    echo "${info}Removing tmp container${normal}"
    docker rm -f "$TMP_CONTAINER_NAME"
  fi
}

# TODO I think we have a few bugs here - if you're passing a variant you override? the hotspot version
buildDockerContainer()
{
  echo "Building docker container"
  docker build -t "${CONTAINER_NAME}" "${DOCKER_BUILD_PATH}" "$1" "$2"
  if [[ "${BUILD_VARIANT}" != "" && -f "${DOCKER_BUILD_PATH}/Dockerfile-${BUILD_VARIANT}" ]]; then
    CONTAINER_NAME="${CONTAINER_NAME}-${BUILD_VARIANT}"
    echo "Building DockerFile variant ${BUILD_VARIANT}"
    docker build -t "${CONTAINER_NAME}" -f "${DOCKER_BUILD_PATH}/Dockerfile-${BUILD_VARIANT}" "${DOCKER_BUILD_PATH}" "$1" "$2"
  fi
}

buildAndTestOpenJDKViaDocker()
{
  # This could be extracted overridden by the user if we support more architectures going forwards
  CONTAINER_ARCHITECTURE="x86_64/ubuntu"
  DOCKER_BUILD_PATH="docker/${OPENJDK_CORE_VERSION}/$CONTAINER_ARCHITECTURE"

  if [ -z "$(which docker)" ]; then
    echo "${error}Error, please install docker and ensure that it is in your path and running!${normal}"
    exit
  fi

  echo "${info}Using Docker to build the JDK${normal}"

  createPersistentDockerDataVolume

  # Copy our scripts for usage inside of the container
  rm -r "${DOCKER_BUILD_PATH}/sbin"
  cp -r "${SCRIPT_DIR}/sbin" "${DOCKER_BUILD_PATH}/sbin" 2>/dev/null

  # If keep is true then use the existing container (or build a new one if we can't find it)
  if [[ "$KEEP" == "true" ]] ; then
     # shellcheck disable=SC2086
     # If we can't find the previous Docker container then build a new one
     if [ "$(docker ps -a | grep -c \"$CONTAINER_NAME\")" == 0 ]; then
         echo "${info}No docker container found so creating '$CONTAINER_NAME' ${normal}"
         buildDockerContainer
     fi
  else
     echo "${info}Since you did not specify -k or --keep, we are removing the existing container (if it exists) and building you a new one"
     echo "$good"
     # Find the previous Docker container and remove it (if it exists)
     docker ps -a | awk '{ print $1,$2 }' | grep "$CONTAINER_NAME" | awk '{print $1 }' | xargs -I {} docker rm -f {}

     # Build a new container
     buildDockerContainer --build-arg "OPENJDK_CORE_VERSION=${OPENJDK_CORE_VERSION}"
     echo "$normal"
  fi

  mkdir -p "${WORKING_DIR}/target"

  docker run -t \
      -e BUILD_VARIANT="$BUILD_VARIANT" \
      -v "${DOCKER_SOURCE_VOLUME_NAME}:/openjdk/build" \
      -v "${WORKING_DIR}/target":/${TARGET_DIR_IN_THE_CONTAINER} \
      --entrypoint /openjdk/sbin/build.sh "${CONTAINER_NAME}"

 testOpenJDKViaDocker

  # If we didn't specify to keep the container then remove it
  if [[ -z ${KEEP} ]] ; then
    docker ps -a | awk '{ print $1,$2 }' | grep "${CONTAINER_NAME}" | awk '{print $1 }' | xargs -I {} docker rm {}
  fi
}

testOpenJDKInNativeEnvironmentIfExpected()
{
  if [[ "$JTREG" == "true" ]];
  then
      "${SCRIPT_DIR}"/sbin/jtreg.sh "${WORKING_DIR}" "${OPENJDK_SOURCE_DIR}" "${BUILD_FULL_NAME}" "${JTREG_TEST_SUBSETS}"
  fi
}

buildAndTestOpenJDKInNativeEnvironment()
{
  BUILD_ARGUMENTS=""
  declare -a BUILD_ARGUMENT_NAMES=("--source" "--destination" "--repository" "--variant" "--update-version" "--build-number" "--repository-tag" "--configure-args")
  declare -a BUILD_ARGUMENT_VALUES=("${WORKING_DIR}" "${TARGET_DIR}" "${OPENJDK_SOURCE_DIR}" "${JVM_VARIANT}" "${OPENJDK_UPDATE_VERSION}" "${OPENJDK_BUILD_NUMBER}" "${TAG}" "${USER_SUPPLIED_CONFIGURE_ARGS}")

  BUILD_ARGS_ARRAY_INDEX=0
  while [[ ${BUILD_ARGS_ARRAY_INDEX} < ${#BUILD_ARGUMENT_NAMES[@]} ]]; do
    if [[ ${BUILD_ARGUMENT_VALUES[${BUILD_ARGS_ARRAY_INDEX}]} != "" ]];
    then
        BUILD_ARGUMENTS="${BUILD_ARGUMENTS}${BUILD_ARGUMENT_NAMES[${BUILD_ARGS_ARRAY_INDEX}]} ${BUILD_ARGUMENT_VALUES[${BUILD_ARGS_ARRAY_INDEX}]} "
    fi
    ((BUILD_ARGS_ARRAY_INDEX++))
  done
  
  echo "Calling ${SCRIPT_DIR}/sbin/build.sh ${BUILD_ARGUMENTS}"
  # shellcheck disable=SC2086
  "${SCRIPT_DIR}"/sbin/build.sh ${BUILD_ARGUMENTS}

  testOpenJDKInNativeEnvironmentIfExpected
}

# TODO Refactor all Docker related functionality to its own script
buildAndTestOpenJDK()
{
  if [ "$USE_DOCKER" == "true" ] ; then
    buildAndTestOpenJDKViaDocker
  else
    buildAndTestOpenJDKInNativeEnvironment
  fi
}

##################################################################

sourceSignalHandler
parseCommandLineArgs "$@"
doAnyBuildVariantOverrides
sourceFileWithColourCodes
checkIfDockerIsUsedForBuildingOrNot
checkIfDockerIsUsedShouldTheContainerBePreserved
setDefaultBranchIfNotProvided
setWorkingDirectory
setTargetDirectory
time (
    checkoutAndCloneOpenJDKGitRepo
)

time (
    getOpenJDKUpdateAndBuildVersion
)

buildAndTestOpenJDK
