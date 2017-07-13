#!/bin/bash
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
# #
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# shellcheck source=sbin/common-functions.sh
source "$SCRIPT_DIR/common-functions.sh"

WORKING_DIR=$1
OPENJDK_REPO_NAME=$2
BUILD_FULL_NAME=$3
# shellcheck disable=SC2001
JTREG_TEST_SUBSETS=$(echo "$4" | sed 's/:/ /')
JTREG_VERSION=${JTREG_VERSION:-4.2.0-tip}
JTREG_TARGET_FOLDER=${JTREG_TARGET_FOLDER:-jtreg}
JOB_NAME=${JOB_NAME:-OpenJDK}
NUM_PROCESSORS=${NUM_PROCESSORS:-$(getconf _NPROCESSORS_ONLN)}
TMP_DIR=$(dirname "$(mktemp -u)")
OPENJDK_DIR="$WORKING_DIR/$OPENJDK_REPO_NAME"
TARGET_DIR="$WORKING_DIR"

determineBuildProperties

checkIfDockerIsUsedForBuildingOrNot()
{
  if [[ -f /.dockerenv ]] ; then
    echo "Detected we're in docker"
    WORKING_DIR=/openjdk/build/
    OPENJDK_REPO_NAME=openjdk/
    OPENJDK_DIR="$WORKING_DIR/$OPENJDK_REPO_NAME"
    TARGET_DIR=/openjdk/target/
    # Keep as a variable for potential use later
    # if we wish to copy the results to the host
    # shellcheck disable=SC2034
    IN_DOCKER=true
  fi
}

downloadJtregAndSetupEnvironment() 
{
  # Download then add jtreg to our path
  if [[ ! -d "${WORKING_DIR}/${JTREG_TARGET_FOLDER}" ]]; then
   echo "Downloading Jtreg binary"
   JTREG_BINARY_FILE="jtreg-${JTREG_VERSION}.tar.gz"

   # shellcheck disable=SC2046
   if [ $(cd "$TMP_DIR" && wget https://ci.adoptopenjdk.net/job/jtreg/lastSuccessfulBuild/artifact/"$JTREG_BINARY_FILE") -ne 0 ]; then
     echo "Failed to retrieve the jtreg binary, exiting"
     exit
   fi

   
   cd "$WORKING_DIR" && tar xf "$TMP_DIR/$JTREG_BINARY_FILE"
  fi

  echo "List contents of the jtreg folder"
  ls "$WORKING_DIR/$JTREG_TARGET_FOLDER/*"

  export JT_HOME=$WORKING_DIR/$JTREG_TARGET_FOLDER

  export PATH=$JT_HOME/bin:$PATH

  # Clean up after ourselves by removing jtreg tgz
  rm -f "$JTREG_BINARY_FILE"
}

applyingJCovSettingsToMakefileForTests()
{
  echo "Apply JCov settings to Makefile..." 
  cd "$OPENJDK_DIR/jdk/test" || exit
  pwd

  sed -i "s/-vmoption:-Xmx512m.*/-vmoption:-Xmx512m -xml:verify -jcov\/classes:$(ABS_PLATFORM_BUILD_ROOT)\/jdk\/classes\/  -jcov\/source:$(ABS_PLATFORM_BUILD_ROOT)\/..\/..\/jdk\/src\/java\/share\/classes  -jcov\/include:*/" Makefile

  cd "$OPENJDK_DIR" || exit
}

settingUpEnvironmentVariablesForJTREG()
{
  echo "Setting up environment variables for JTREG to run"

  # This is the JDK we'll test
  export PRODUCT_HOME=$OPENJDK_DIR/build/$BUILD_FULL_NAME/images/j2sdk-image
  echo "$PRODUCT_HOME"
  ls "$PRODUCT_HOME"

  export JTREG_DIR=$WORKING_DIR/jtreg
  export JTREG_INSTALL=${JTREG_DIR}
  export JT_HOME=${JTREG_INSTALL}
  export JTREG_HOME=${JTREG_INSTALL}
  export JPRT_JTREG_HOME=${JT_HOME}
  export JPRT_JAVA_HOME=${PRODUCT_HOME}
  export JTREG_TIMEOUT_FACTOR=5
  export CONCURRENCY=$NUM_PROCESSORS
}

runJtregViaMakeCommand()
{
  echo "Running jtreg via make command (debug logs enabled)"
  if [ -z "$JTREG_TEST_SUBSETS" ]; then
    make test jobs=10 LOG=debug
  else
    make test jobs=10 LOG=debug TEST="$JTREG_TEST_SUBSETS"
  fi 
}

packageTestResultsWithJCovReports()
{
  echo "Package test output into archives..." 
  pwd

  cd "$OPENJDK_DIR/build/$BUILD_FULL_NAME/" || exit

  artifact="${JOB_NAME}-testoutput-with-jcov-reports"
  echo "Tarring and zipping the 'testoutput' folder into artefact: $artifact.tar.gz" 
  tar -czf "$TARGET_DIR/$artifact.tar.gz"   testoutput/

  if [ -d testoutput  ]; then  
     rm -fr "$WORKING_DIR/$OPENJDK_REPO_NAME/testoutput"
  fi
  cp -fr testoutput/ "$WORKING_DIR/testoutput/"

  cd "$WORKING_DIR" || exit
}

packageOnlyJCovReports()
{
  echo "Package jcov reports into archives..." 
  pwd

  cd "$OPENJDK_DIR/build/$BUILD_FULL_NAME/" || exit
  pwd

  artifact="${JOB_NAME}-jcov-results-only"
  echo "Tarring and zipping the 'testoutput/../jcov' folder into artefact: $artifact.tar.gz" 
  tar -czf "$TARGET_DIR/$artifact.tar.gz"   testoutput/*/JTreport/jcov/

  cd "$WORKING_DIR" || exit
}

packageReports()
{
  echo "Archiving your jtreg results (includes jcov reports)"
  packageTestResultsWithJCovReports
  packageOnlyJCovReports  
}

checkIfDockerIsUsedForBuildingOrNot
downloadingRequiredDependencies
downloadJtregAndSetupEnvironment
applyingJCovSettingsToMakefileForTests
settingUpEnvironmentVariablesForJTREG
runJtregViaMakeCommand
packageReports
