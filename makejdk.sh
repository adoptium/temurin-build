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

# Script to clone the OpenJDK source then build it

# Optionally uses Docker, otherwise you can provide two arguments:
# the area to build the JDK e.g. $HOME/mybuilddir as -s or --source
# and the target destination for the tar.gz e.g. -d or --destination $HOME/mytargetdir
# Both must be absolute paths! You can use $PWD/mytargetdir

# A simple way to install dependencies persistently is to use our Ansible playbooks

# You can set the JDK boot directory with the JDK_BOOT_DIR environment variable

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# shellcheck source=sbin/common-functions.sh
source "$SCRIPT_DIR/sbin/common-functions.sh"

OPENJDK_REPO_NAME=${OPENJDK_REPO_NAME:-openjdk}
SHALLOW_CLONE_OPTION="--depth=1"

DOCKER_SOURCE_VOLUME_NAME="openjdk-source-volume"
CONTAINER=openjdk_container
TMP_CONTAINER_NAME=openjdk-copy-src
CLEAN_DOCKER_BUILD=false

export COPY_TO_HOST=false
export USE_DOCKER=false

TARGET_DIR_IN_THE_CONTAINER="/openjdk/target/"

WORKING_DIR=""
USE_SSH=false
TARGET_DIR=""
BRANCH=""
TAG=""
KEEP=false
JTREG=false
BUILD_VARIANT=${BUILD_VARIANT-:""}

JVM_VARIANT=${JVM_VARIANT-:server}

OPENJDK_UPDATE_VERSION=""
OPENJDK_BUILD_NUMBER=""

PATH_BUILD=""

determineBuildProperties

sourceFileWithColourCodes()
{
  # shellcheck disable=SC1091
  source ./sbin/colour-codes.sh
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

      "--version" | "-v" )
      shift;;

      "--freetype-dir" | "-ftd" )
      export FREETYPE_DIRECTORY="$1"; shift;;

      "--variant"  | "-bv" )
      export BUILD_VARIANT="$1"; shift;;

      *) echo >&2 "${error}Invalid option: ${opt}${normal}"; man ./makejdk-any-platform.1; exit 1;;
     esac
  done
}

doAnyBuildVariantOverrides()
{
  if [[ "${BUILD_VARIANT}" == "openj9" ]]; then
    # current (hoping not final) location of Extensions for OpenJDK9 for OpenJ9 project
    REPOSITORY="ibmruntimes/openj9-openjdk-${OPENJDK_CORE_VERSION}"
    BRANCH="openj9"
    if [[ "$OSTYPE" != "cygwin" ]]; then
      # shellcheck disable=SC2155
      export CC=$(which gcc-4.8)
      # shellcheck disable=SC2155
      export CXX=$(which g++-4.8)
    fi
  fi
  if [[ "${BUILD_VARIANT}" == "SapMachine" ]]; then
    # current (hoping not final) location of Extensions for OpenJDK9 for OpenJ9 project
    REPOSITORY="SAP/SapMachine"
    BRANCH="sapmachine"
  fi
}

checkIfDockerIsUsedForBuildingOrNot()
{
  # Both a working directory and a target directory provided
  if [ ! -z "$WORKING_DIR" ] && [ ! -z "$TARGET_DIR" ] ; then
    # This uses sbin/build.sh directly
    echo "${info}Not using Docker, working area will be ${WORKING_DIR}, target for the JDK will be ${TARGET_DIR} ${normal}"
  fi

  # No working directory and no target directory provided
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

checkIfDockerIsUsedShouldTheContainerBePreserved()
{
  echo "${info}"
  if [ "${KEEP}" == "true" ] ; then
    echo "We'll keep the built Docker container if you're using Docker."
  else
    echo "We'll remove the built Docker container if you're using Docker."
  fi
  echo "${normal}"
}

setDefaultIfBranchIsNotProvided()
{
  if [ -z "$BRANCH" ] ; then
    echo "${info}BRANCH is undefined so checking out dev${normal}"
    BRANCH="dev"
  fi
}

setWorkingDirectoryIfProvided()
{
  if [ -z "${WORKING_DIR}" ] ; then
    echo "${info}WORKING_DIR is undefined so setting to ${PWD}${normal}."
    WORKING_DIR=$PWD
  else
    echo "${info}Working dir is ${WORKING_DIR}${normal}."
  fi
}

setTargetDirectoryIfProvided()
{
  echo "${info}"
  if [ -z "${TARGET_DIR}" ] ; then
    echo "${info}TARGET_DIR is undefined so setting to $PWD"
    TARGET_DIR=$PWD
    # Only makes a difference if we're in Docker
    echo "If you're using Docker the build artifact will not be copied to the host."
  else
    echo "${info}Target directory is ${TARGET_DIR}${normal}"
    COPY_TO_HOST=true
    echo "If you're using Docker we'll copy the build artifact to the host."
  fi
}

checkOpenJDKGitRepo()
{
  echo "${git}"
  if [ -d "${WORKING_DIR}/${OPENJDK_REPO_NAME}/.git" ] && ( [ "$OPENJDK_CORE_VERSION" == "jdk8" ] || [ "$OPENJDK_CORE_VERSION" == "jdk9" ] || [ "$OPENJDK_CORE_VERSION" == "jdk10" ])  ; then
    GIT_VERSION=$(git --git-dir "${WORKING_DIR}/${OPENJDK_REPO_NAME}/.git" remote -v | grep "${OPENJDK_CORE_VERSION}")
     echo "${GIT_VERSION}"
     if [ "$GIT_VERSION" ]; then
       # The repo is the correct JDK Version
       cd "${WORKING_DIR}/${OPENJDK_REPO_NAME}" || return
       echo "${info}Will reset the repository at $PWD in 10 seconds...${git}"
       sleep 10
       echo "${git}Pulling latest changes from git repo"

       showShallowCloningMessage "fetch"
       git fetch --all ${SHALLOW_CLONE_OPTION}
       git reset --hard origin/$BRANCH
       if [ ! -z "$TAG" ]; then
         git checkout "$TAG"
       fi
       git clean -fdx
     else
       # The repo is not for the correct JDK Version
       echo "Incorrect Source Code for ${OPENJDK_FOREST_NAME}. Will re-clone"
       rm -rf "${WORKING_DIR:?}/${OPENJDK_REPO_NAME:?}"
       cloneOpenJDKGitRepo
     fi
     cd "${WORKING_DIR}" || return
  elif [ ! -d "${WORKING_DIR}/${OPENJDK_REPO_NAME}/.git" ] ; then
    # If it doesn't exist, clone it
    echo "${info}Didn't find any existing openjdk repository at WORKING_DIR (set to ${WORKING_DIR}) so cloning the source to openjdk"
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
  GIT_CLONE_ARGUMENTS=($SHALLOW_CLONE_OPTION '-b' "$BRANCH" "$GIT_REMOTE_REPO_ADDRESS" "${WORKING_DIR}/${OPENJDK_REPO_NAME}")

  echo "git clone ${GIT_CLONE_ARGUMENTS[*]}"
  git clone "${GIT_CLONE_ARGUMENTS[@]}"
  if [ ! -z "$TAG" ]; then
    cd "${WORKING_DIR}/${OPENJDK_REPO_NAME}" || exit 1
    git checkout "$TAG"
  fi

  # Building OpenJDK with OpenJ9 must run get_source.sh to clone openj9 and openj9-omr repositories
  if [ "$BUILD_VARIANT" == "openj9" ]; then
    cd "${WORKING_DIR}/${OPENJDK_REPO_NAME}" || return
    bash get_source.sh
  fi

}

# TODO This only works for jdk8u based releases.  Will require refactoring when jdk9 enters an update cycle
getOpenJDKUpdateAndBuildVersion()
{
  echo "${git}"

  if [ -d "${WORKING_DIR}/${OPENJDK_REPO_NAME}/.git" ]; then
    # It does exist and it's a repo other than the AdoptOpenJDK one
    cd "${WORKING_DIR}/${OPENJDK_REPO_NAME}" || return
    echo "${git}Pulling latest tags and getting the latest update version using git fetch -q --tags ${SHALLOW_CLONE_OPTION}"
    git fetch -q --tags "${SHALLOW_CLONE_OPTION}"
    OPENJDK_REPO_TAG=${TAG:-$(getFirstTagFromOpenJDKGitRepo)}
    if [[ "${OPENJDK_REPO_TAG}" == "" ]] ; then
     echo "${error}Unable to detect git tag"
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
    --entrypoint /openjdk/sbin/jtreg.sh "${CONTAINER}"
  fi
}

createPersistentDockerDataVolume()
{
  #Create a data volume called $DOCKER_SOURCE_VOLUME_NAME,
  #this gets mounted at /openjdk/build inside the container and is persistent between builds/tests
  #unless -c is passed to this script, in which case it is recreated using the source
  #in the current ./openjdk directory on the host machine (outside the container)
  docker volume inspect $DOCKER_SOURCE_VOLUME_NAME > /dev/null 2>&1
  DATA_VOLUME_EXISTS=$?

  if [[ "$CLEAN_DOCKER_BUILD" == "true" || "$DATA_VOLUME_EXISTS" != "0" ]]; then
  
    echo "${info}Removing old volumes and containers${normal}"
    docker rm -f "$(docker ps -a --no-trunc | grep $CONTAINER | cut -d' ' -f1)" || true
    docker volume rm "${DOCKER_SOURCE_VOLUME_NAME}" || true

    echo "${info}Creating tmp container and copying src${normal}"
    docker volume create --name "${DOCKER_SOURCE_VOLUME_NAME}"
    docker run -v "${DOCKER_SOURCE_VOLUME_NAME}":/openjdk/build --name "$TMP_CONTAINER_NAME" ubuntu:14.04 /bin/bash
    docker cp openjdk "$TMP_CONTAINER_NAME":/openjdk/build/

    echo "${info}Removing tmp container${normal}"
    docker rm -f "$TMP_CONTAINER_NAME"
  fi
}

buildDockerContainer()
{
  echo Building docker container
  docker build -t "${CONTAINER}" "${PATH_BUILD}" "$1" "$2"
  if [[ "${BUILD_VARIANT}" != "" && -f "${PATH_BUILD}/Dockerfile-${BUILD_VARIANT}" ]]; then
    CONTAINER="${CONTAINER}-${BUILD_VARIANT}"
    echo Building dockerfile variant "${BUILD_VARIANT}"
    docker build -t "${CONTAINER}" -f "${PATH_BUILD}/Dockerfile-${BUILD_VARIANT}" "${PATH_BUILD}" "$1" "$2"
  fi
}

buildAndTestOpenJDKViaDocker()
{


  PATH_BUILD="docker/${OPENJDK_CORE_VERSION}/x86_64/ubuntu"

  if [ -z "$(which docker)" ]; then
    echo "${error}Error, please install docker and ensure that it is in your path and running!${normal}"
    exit
  fi

  echo "${info}Using Docker to build the JDK${normal}"

  createPersistentDockerDataVolume


  # Copy our scripts for usage inside of the container
  rm -r "${PATH_BUILD}/sbin"
  cp -r "${SCRIPT_DIR}/sbin" "${PATH_BUILD}/sbin" 2>/dev/null


  # Keep is undefined so we'll kill the docker image

  if [[ "$KEEP" == "true" ]] ; then
     # shellcheck disable=SC2086
     if [ "$(docker ps -a | grep -c \"$CONTAINER\")" == 0 ]; then
         echo "${info}No docker container found so creating '$CONTAINER' ${normal}"
         buildDockerContainer
     fi
  else
     echo "${info}Building as you've not specified -k or --keep"
     echo "$good"
     docker ps -a | awk '{ print $1,$2 }' | grep "$CONTAINER" | awk '{print $1 }' | xargs -I {} docker rm -f {}
     buildDockerContainer --build-arg "OPENJDK_CORE_VERSION=${OPENJDK_FOREST_NAME}"
     echo "$normal"
  fi

  mkdir -p "${WORKING_DIR}/target"

  docker run -t \
      -e BUILD_VARIANT="$BUILD_VARIANT" \
      -v "${DOCKER_SOURCE_VOLUME_NAME}:/openjdk/build" \
      -v "${WORKING_DIR}/target":/${TARGET_DIR_IN_THE_CONTAINER} \
      --entrypoint /openjdk/sbin/build.sh "${CONTAINER}"

 testOpenJDKViaDocker

  # Didn't specify to keep
  if [[ -z ${KEEP} ]] ; then
    docker ps -a | awk '{ print $1,$2 }' | grep "${CONTAINER}" | awk '{print $1 }' | xargs -I {} docker rm {}
  fi
}

testOpenJDKInNativeEnvironmentIfExpected()
{
  if [[ "$JTREG" == "true" ]];
  then
      "${SCRIPT_DIR}"/sbin/jtreg.sh "${WORKING_DIR}" "${OPENJDK_REPO_NAME}" "${BUILD_FULL_NAME}" "${JTREG_TEST_SUBSETS}"
  fi
}

buildAndTestOpenJDKInNativeEnvironment()
{
  echo "Calling sbin/build.sh $WORKING_DIR $TARGET_DIR $OPENJDK_REPO_NAME $JVM_VARIANT $OPENJDK_UPDATE_VERSION $OPENJDK_BUILD_NUMBER $TAG"
  "${SCRIPT_DIR}"/sbin/build.sh "${WORKING_DIR}" "${TARGET_DIR}" "${OPENJDK_REPO_NAME}" "${JVM_VARIANT}" "${OPENJDK_UPDATE_VERSION}" "${OPENJDK_BUILD_NUMBER}" "${TAG}"

  testOpenJDKInNativeEnvironmentIfExpected
}

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
if [[ -z "${COLOUR}" ]] ; then
  sourceFileWithColourCodes
fi
checkIfDockerIsUsedForBuildingOrNot
checkIfDockerIsUsedShouldTheContainerBePreserved
setDefaultIfBranchIsNotProvided
setWorkingDirectoryIfProvided
setTargetDirectoryIfProvided
time (
    echo "Cloning OpenJDK git repo"
    checkOpenJDKGitRepo
)

time (
    echo "Updating OpenJDK git repo"
    getOpenJDKUpdateAndBuildVersion
)

buildAndTestOpenJDK
