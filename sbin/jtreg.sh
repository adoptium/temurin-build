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
## shellcheck source=sbin/common-functions.sh
source "$SCRIPT_DIR/common-functions.sh"
source "$SCRIPT_DIR/prepareWorkspace.sh"
source "$SCRIPT_DIR/config_init.sh"
source "$SCRIPT_DIR/colour-codes.sh"


#WORKING_DIR=$1
#OPENJDK_SOURCE_DIR=$2
#BUILD_FULL_NAME=$3
## shellcheck disable=SC2001
#JTREG_TEST_SUBSETS=$(echo "$4" | sed 's/:/ /')
#JTREG_VERSION=${JTREG_VERSION:-4.2.0-tip}
#JTREG_TARGET_FOLDER=${JTREG_TARGET_FOLDER:-jtreg}
#JOB_NAME=${JOB_NAME:-OpenJDK}
#NUM_PROCESSORS=${NUM_PROCESSORS:-$(getconf _NPROCESSORS_ONLN)}
#TMP_DIR=$(dirname "$(mktemp -u)")
#OPENJDK_DIR="$WORKING_DIR/$OPENJDK_SOURCE_DIR"
#TARGET_DIR="$WORKING_DIR"


downloadJtregAndSetupEnvironment() 
{
  local jtregDir
  jtregDir="${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[WORKING_DIR]}/jtreg"


  # Download then add jtreg to our path
  if [[ ! -d "${jtregDir}" ]]; then

   local download_dir="${BUILD_CONFIG[WORKSPACE_DIR]}/libs/jtreg"

   mkdir -p "${download_dir}" || exit 1
   echo "Downloading Jtreg binary"
   local jtreg_binary_file="jtreg-${BUILD_CONFIG[JTREG_VERSION]}.tar.gz"

   # shellcheck disable=SC2046
   if ! (cd "${download_dir}" && wget https://ci.adoptopenjdk.net/job/jtreg/lastSuccessfulBuild/artifact/"${jtreg_binary_file}"); then
     echo "Failed to retrieve the jtreg binary, exiting"
     exit
   fi

   mkdir -p "${jtregDir}" || exit 1
   cd "${jtregDir}" && tar  -xf "${download_dir}/${jtreg_binary_file}" --strip 1
  fi

  export JT_HOME="${jtregDir}"

  export PATH="${jtregDir}/bin:$PATH"
}

applyingJCovSettingsToMakefileForTests()
{
  echo "Apply JCov settings to Makefile..." 
  cd "${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[WORKING_DIR]}/${BUILD_CONFIG[OPENJDK_SOURCE_DIR]}/jdk/test" || exit

  local abs_platform_build_root="${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[WORKING_DIR]}/${BUILD_CONFIG[OPENJDK_SOURCE_DIR]}"

  sed -i "s/-vmoption:-Xmx512m.*/-vmoption:-Xmx512m -xml:verify -jcov\/classes:$(abs_platform_build_root)\/jdk\/classes\/  -jcov\/source:$(abs_platform_build_root)\/..\/..\/jdk\/src\/java\/share\/classes  -jcov\/include:*/" Makefile
}

runJtregViaMakeCommand()
{
  cd "${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[WORKING_DIR]}/${BUILD_CONFIG[OPENJDK_SOURCE_DIR]}"

  export CONCURRENCY=${BUILD_CONFIG[NUM_PROCESSORS]}:-$(getconf _NPROCESSORS_ONLN)}
  export JPRT_JTREG_HOME="${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[WORKING_DIR]}/jtreg"

  echo "Running jtreg via make command (debug logs enabled)"
  if [ -z "${BUILD_CONFIG[JTREG_TEST_SUBSETS]}" ]; then
    make test jobs=10 LOG=debug
  else
    make test jobs=10 LOG=debug TEST="${BUILD_CONFIG[JTREG_TEST_SUBSETS]}"
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
     rm -fr "$WORKING_DIR/$OPENJDK_SOURCE_DIR/testoutput"
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

loadConfigFromFile
cd "${BUILD_CONFIG[WORKSPACE_DIR]}"

parseConfigurationArguments "$@"
downloadingRequiredDependencies
downloadJtregAndSetupEnvironment

runJtregViaMakeCommand
exit 1
packageReports
