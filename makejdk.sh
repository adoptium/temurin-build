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

REPOSITORY=AdoptOpenJDK/openjdk-jdk8u
OPENJDK_REPO_NAME=openjdk

OS_KERNAL_NAME=$(echo $(uname) | awk '{print tolower($0)}')

OS_MACHINE=$(uname -m)

JVM_VARIANT=server
if [[ "$OS_MACHINE" == "s390x" ]] || [[ "$OS_MACHINE" == "armv7l" ]] ; then
 JVM_VARIANT=zero
fi 

BUILD_TYPE=normal

BUILD_FULL_NAME=${OS_KERNAL_NAME}-${OS_MACHINE}-${BUILD_TYPE}-${JVM_VARIANT}-release

USE_DOCKER=false
WORKING_DIR=""
USE_SSH=false
TARGET_DIR=""
BRANCH=""
KEEP=false
JTREG=false

initialiseEscapeCodes()
{
  # Escape code
  esc=$(echo -en "\033")

  # Set colors
  error="${esc}[0;31m"
  good="${esc}[0;32m"
  info="${esc}[0;33m"
  git="${esc}[0;34m"
  normal=$(echo -en "${esc}[m\017")
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
      USE_SSH=true; shift;;

      "--destination" | "-d" )
      TARGET_DIR="$1"; shift;;

      "--repository" | "-r" )
      REPOSITORY="$1"; shift;;

      "--branch" | "-b" )
      BRANCH="$1"; shift;;

      "--keep" | "-k" )
      KEEP=true; shift;;

      "--jtreg" | "-j" )
      JTREG=true; shift;;

    "--jtreg_subsets" )
    JTREG=true; JTREG_TEST_SUBSETS="$1"; shift;;

      *) echo >&2 "${error}Invalid option: ${opt}${normal}"; man ./makejdk.1; exit 1;;
     esac
  done
}

checkIfDockerIsUsedForBuildingOrNot()
{
  # Both a working directory and a target directory provided
  if [ ! -z "$WORKING_DIR" ] && [ ! -z "$TARGET_DIR" ] ; then
    # This uses sbin/build.sh directly
    echo "${info} Not using Docker, working area will be ${WORKING_DIR}, target for the JDK will be ${TARGET_DIR} ${normal}"
  fi

  # No working directory and no target directory provided
  if [ -z "$WORKING_DIR" ] && [ -z "$TARGET_DIR" ] ; then
    echo "${info}No parameters provided, using Docker ${normal}"
    USE_DOCKER=true
  elif [ ! -z "$TARGET_DIR" ] && [ -z "$WORKING_DIR" ] ; then
    # Target directory is defined but the working directory isn't
    # Calls sbin/build.sh inside of Docker followed by a docker cp command
    echo "${info}Using Docker, target directory for the tgz on the host: ${TARGET_DIR}"
    USE_DOCKER=true
  fi
}

checkInCaseOfDockerShouldTheContainerBePreserved()
{
  echo ${info}
  if [ "$KEEP" == "true" ] ; then
    echo "We'll keep the built Docker container if you're using Docker"
  else
    echo "We'll remove the built Docker container if you're using Docker"
  fi
  echo ${normal}
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
  if [ -z "$WORKING_DIR" ] ; then
    echo "${info}WORKING_DIR is undefined so setting to $PWD${normal}"
    WORKING_DIR=$PWD
  else
    echo "${info}Working directory is ${WORKING_DIR}${normal}"
  fi
}

setTargetDirectoryIfProvided()
{
  echo $info
  if [ -z "$TARGET_DIR" ] ; then
    echo "${info}TARGET_DIR is undefined so setting to ${PWD}"
    TARGET_DIR=$PWD
    # Only makes a difference if we're in Docker
    echo "If you're using Docker The build artifact will not be copied to the host"
  else
    echo "${info}Target directory is ${TARGET_DIR}${normal}"
    COPY_TO_HOST=true
    echo "If you're using Docker we'll copy the build artifact to the host"
  fi
}

cloneOpenJDKGitRepo()
{
  echo $git
  if [ -d "${WORKING_DIR}/${OPENJDK_REPO_NAME}/.git" ] && [ "$REPOSITORY" == "AdoptOpenJDK/openjdk-jdk8u" ] ; then
    # It does exist and it's a repo other than the AdoptOpenJDK one
    cd ${WORKING_DIR}/${OPENJDK_REPO_NAME}
    echo "${info}Will reset the repository at ${PWD} in 10 seconds...${git}"
    sleep 10
    echo "${git}Pulling latest changes from git repo"
    git fetch --all
    git reset --hard origin/${BRANCH}
    echo ${normal}
    cd $WORKING_DIR
  elif [ ! -d "${WORKING_DIR}/${OPENJDK_REPO_NAME}/.git" ] ; then
    # If it doesn't exixt, clone it
    echo "${info}Didn't find any existing openjdk repository at WORKING_DIR (set to ${WORKING_DIR}) so cloning the source to openjdk"
    if [[ "$USE_SSH" == "true" ]] ; then
      echo "git clone -b ${BRANCH} git@github.com:${REPOSITORY}.git ${WORKING_DIR}/${OPENJDK_REPO_NAME}"
      git clone -b ${BRANCH} git@github.com:${REPOSITORY}.git $WORKING_DIR/$OPENJDK_REPO_NAME
    else
      echo "git clone -b ${BRANCH} https://github.com/${REPOSITORY}.git ${WORKING_DIR}/${OPENJDK_REPO_NAME}"
      git clone -b ${BRANCH} https://github.com/${REPOSITORY}.git $WORKING_DIR/$OPENJDK_REPO_NAME
    fi
  fi
  echo $normal
}

testOpenJDKViaDocker()
{
  if [[ ! -z "$JTREG" ]]; then
    docker run --privileged -t -v ${WORKING_DIR}/${OPENJDK_REPO_NAME}:/openjdk/jdk8u/openjdk --entrypoint jtreg.sh ${CONTAINER}
  fi
}

buildAndTestOpenJDKViaDocker()
{
  PS_DOCKER=$(ps -ef | grep "docker" | wc -l)

  if [ -z $(which docker) ] || [ "$PS_DOCKER" -lt 2 ]; then
    echo "${error}Error, please install docker and ensure that it is in your path and running!${normal}"
    exit
  fi

  echo "${info}Using Docker to build the JDK${normal}"

  CONTAINER=openjdk_container

  # Copy our script for usage inside of the container
  rm docker/jdk8u/x86_64/ubuntu/build.sh
  cp sbin/build.sh docker/jdk8u/x86_64/ubuntu 2>/dev/null

  rm docker/jdk8u/x86_64/ubuntu/jtreg.sh
  cp sbin/jtreg.sh docker/jdk8u/x86_64/ubuntu 2>/dev/null
  # Keep is undefined so we'll kill the docker image

  if [[ "$KEEP" == "true" ]] ; then
     if [ $(docker ps -a | grep openjdk_container | wc -l) == 0 ]; then
         echo "${info}No docker container found so creating one${normal}"
         docker build -t $CONTAINER docker/jdk8u/x86_64/ubuntu
     fi
  else
     echo "${info}Building as you've not specified -k or --keep"
     echo $good
     docker ps -a | awk '{ print $1,$2 }' | grep $CONTAINER | awk '{print $1 }' | xargs -I {} docker rm -f {}
     docker build -t $CONTAINER docker/jdk8u/x86_64/ubuntu
     echo ${normal}
  fi

  docker run --privileged -t -v ${WORKING_DIR}/${OPENJDK_REPO_NAME}:/openjdk/jdk8u/openjdk --entrypoint build.sh $CONTAINER

  testOpenJDKViaDocker

  CONTAINER_ID=$(docker ps -a | awk '{ print $1,$2 }' | grep openjdk_container | awk '{print $1 }'| head -1)

  if [[ "$COPY_TO_HOST" == "true" ]] ; then
    echo "Copying to the host with docker cp ${id}:/openjdk/jdk8u/OpenJDK.tar.gz ${TARGET_DIR}"
    docker cp ${CONTAINER_ID}:/openjdk/jdk8u/OpenJDK.tar.gz $TARGET_DIR
  fi

  if [[ "$JTREG" == "true" ]] ; then
    echo "Copying jtreg reports from docker"
    docker cp ${CONTAINER_ID}:/openjdk/jdk8u/jtreport.zip $TARGET_DIR
    docker cp ${CONTAINER_ID}:/openjdk/jdk8u/jtwork.zip $TARGET_DIR
  fi

  # Didn't specify to keep
  if [[ -z "$KEEP" ]] ; then
    docker ps -a | awk '{ print $1,$2 }' | grep $CONTAINER | awk '{print $1 }' | xargs -I {} docker rm {}
  fi
}

testOpenJDKInNativeEnvironmentIfExpected()
{
  if [[ "$JTREG" == "true" ]];
  then
      $WORKING_DIR/sbin/jtreg.sh $WORKING_DIR $OPENJDK_REPO_NAME $BUILD_FULL_NAME $JTREG_TEST_SUBSETS
  fi
}

buildAndTestOpenJDKInNativeEnvironment()
{
  echo "Calling sbin/build.sh ${WORKING_DIR} ${TARGET_DIR} ${OPENJDK_REPO_NAME} ${BUILD_FULL_NAME} ${JVM_VARIANT}"
  $WORKING_DIR/sbin/build.sh $WORKING_DIR $TARGET_DIR $OPENJDK_REPO_NAME $BUILD_FULL_NAME $JVM_VARIANT

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

initialiseEscapeCodes
sourceSignalHandler
parseCommandLineArgs "$@"
checkIfDockerIsUsedForBuildingOrNot
checkInCaseOfDockerShouldTheContainerBePreserved
setDefaultIfBranchIsNotProvided
setWorkingDirectoryIfProvided
setTargetDirectoryIfProvided
cloneOpenJDKGitRepo
buildAndTestOpenJDK
