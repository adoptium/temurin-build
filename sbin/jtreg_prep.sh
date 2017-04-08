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

# Purpose: This script was designed to do any+all setup required by the jtreg.sh script in order to run it.
# Tasks: Retrieve Java, unpack it if need-be, and store it locally in a specific location. If the location is blank, we put it in 

REPOSITORY=AdoptOpenJDK/openjdk-jdk8u
OPENJDK_REPO_NAME=openjdk

while [[ $# -gt 0 ]] && [[ ."$1" = .-* ]] ; do
  opt="$1";
  shift;
  case "$opt" in
    "--" ) break 2;;

    "--java_source" )
    JAVA_SOURCE="$1"; shift;;

    "--java_destination" )
    JAVA_DESTINATION="$1"; shift;;

    "--ssh" | "-S" )
    USE_SSH=true; shift;;

    "--repository" | "-r" )
    REPOSITORY="$1"; shift;;

    "--branch" | "-b" )
    BRANCH="$1"; shift;;

    "--working_dir" )
    WORKING_DIR="$1"; shift;;

    *) echo >&2 "Invalid option: ${opt}"; man ./makejdk.1; exit 1;;
   esac
done

if [ -z "${JAVA_SOURCE}" ]; then
  echo >&2 "jtreg_prep.sh failed: --java_source must be specified"; exit 1
fi

if [ -z "${WORKING_DIR}" ] ; then
  echo "WORKING_DIR is undefined so setting to $PWD"
  WORKING_DIR=$PWD
else
  echo "Working dir is $WORKING_DIR"
fi

if [ -z "${JAVA_DESTINATION}" ]; then
  JAVA_DESTINATION="$WORKING_DIR/$OPENJDK_REPO_NAME/build/java_home/images"
fi

if [ -z "${BRANCH}" ] ; then
  echo "BRANCH is undefined so checking out dev"
  BRANCH="dev"
fi

# Step 1: Retrieve Java

if [ ! -d "${JAVA_DESTINATION}" ]; then
  mkdir -p "${JAVA_DESTINATION}"
fi
cd "${JAVA_DESTINATION}"

#If it's a http location, use wget.
if [[ "${JAVA_SOURCE}" == http* ]]; then 
  wget "${JAVA_SOURCE}"
  if [ $? -ne 0 ]; then
    echo "Failed to retrieve the jtreg binary, exiting"
    exit 1
  fi
else #Assume it's local or on a mounted drive.
  if [ -f "${JAVA_SOURCE}" ] || [ -d "${JAVA_SOURCE}" ]; then
    cp -r "${JAVA_SOURCE}" .
  else
    echo "Java could not be found at the java_source location."
    exit 1
  fi
fi

# Step 2: Unpack Java if we need to.

if [[ "$JAVA_SOURCE" == *\.tar\.gz ]]; then #If it's a tar file, unpack it.
  cd "${JAVA_DESTINATION}"
  tar xvf *.tar.gz
  echo "Java has been untarred."
  cd "${WORKING_DIR}"
elif [ ! -d "${JAVA_SOURCE}" ]; then #If it's not a directory, then we don't know how to unpack it. 
  echo "The Java file you specified as source was copied to the destination, but this script doesn't know how to unpack it. Please add this logic to this script, or unpack it manually before running jtreg.";
fi

# Step 3: Fetch OpenJDK, as that's where the tests live.

if [ -d "$WORKING_DIR"/$OPENJDK_REPO_NAME/.git ] && [ $REPOSITORY == "AdoptOpenJDK/openjdk-jdk8u" ] ; then
  # It does exist and it's a repo other than the AdoptOpenJDK one
  cd $WORKING_DIR/$OPENJDK_REPO_NAME
  echo "Will reset the repository at $PWD in 10 seconds..."
  sleep 10
  echo "Pulling latest changes from git repo"
  git fetch --all
  git reset --hard origin/$BRANCH
  cd $WORKING_DIR
elif [ ! -d "${WORKING_DIR}"/$OPENJDK_REPO_NAME/.git ] ; then
  # If it doesn't exixt, clone it
  echo "Didn't find any existing openjdk repository at WORKING_DIR (set to ${WORKING_DIR}) so cloning the source to openjdk"
  if [[ "${USE_SSH}" == true ]] ; then
    echo "git clone -b ${BRANCH} git@github.com:${REPOSITORY}.git $WORKING_DIR/$OPENJDK_REPO_NAME"
    git clone -b ${BRANCH} git@github.com:${REPOSITORY}.git $WORKING_DIR/$OPENJDK_REPO_NAME
  else
    echo "git clone -b ${BRANCH} https://github.com/${REPOSITORY}.git $WORKING_DIR/$OPENJDK_REPO_NAME"
    git clone -b ${BRANCH} https://github.com/${REPOSITORY}.git $WORKING_DIR/$OPENJDK_REPO_NAME
  fi
fi

# Step 4: Finish
echo "jtreg_prep.sh has finished successfully."
exit 0
