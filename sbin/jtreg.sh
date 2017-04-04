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

WORKING_DIR=$1
OPENJDK_REPO_NAME=$2
BUILD_FULL_NAME=$3

if [[ -f /.dockerenv ]] ; then
  echo "Detected we're in docker"
  WORKING_DIR=/openjdk/jdk8u/openjdk
  # Keep as a variable for potential use later
  # if we wish to copy the results to the host
  IN_DOCKER=true
fi

echo "Running jtreg"

cd $WORKING_DIR/$OPENJDK_REPO_NAME/jdk/test

# This is the JDK we'll test
export PRODUCT_HOME=$WORKING_DIR/$OPENJDK_REPO_NAME/build/$BUILD_FULL_NAME/images/j2sdk-image

echo $PRODUCT_HOME
ls $PRODUCT_HOME

# Download then add jtreg to our path
wget https://adopt-openjdk.ci.cloudbees.com/job/jtreg/lastSuccessfulBuild/artifact/jtreg-4.2.0-tip.tar.gz

if [ $? -ne 0 ]; then
  echo "Failed to retrieve the jtreg binary, exiting"
  exit
fi

tar xvf *.tar.gz

mv jtreg* $WORKING_DIR
ls $WORKING_DIR/jtreg*

export PATH=$WORKING_DIR/jtreg/bin:$PATH

export JT_HOME=$WORKING_DIR/jtreg

# Clean up after ourselves by removing jtreg tgz
rm -f jtreg*.tar.gz

echo "Running jtreg via make command"

echo "Apply JCov settings to Makefile..." 
cd $WORKING_DIR/$OPENJDK_REPO_NAME/jdk/test
pwd

sed -i 's/-vmoption:-Xmx512m.*/-vmoption:-Xmx512m -jcov\/classes:$(ABS_PLATFORM_BUILD_ROOT)\/jdk\/classes\/  -jcov\/source:$(ABS_PLATFORM_BUILD_ROOT)\/..\/..\/jdk\/src\/java\/share\/classes  -jcov\/include:*/' Makefile

# This is the JDK we'll test
export PRODUCT_HOME=$WORKING_DIR/$OPENJDK_REPO_NAME/build/$BUILD_FULL_NAME/images/j2sdk-image
cd $WORKING_DIR/$OPENJDK_REPO_NAME

make test jobs=10

if [ $? -ne 0 ]; then
  echo "Failed to run jtreg, exiting"
  exit
fi

packageTestResultsWithJCovReports()
{
  echo "Package test output into archives..." 
  pwd

  cd $WORKING_DIR/$OPENJDK_REPO_NAME/build/$BUILD_FULL_NAME/
 
  artifact=${JOB_NAME}-testoutput-with-jcov-reports
  echo "Tarring and zipping the 'testoutput' folder into artefact: $artifact.tar.gz" 
  tar -cvzf $WORKING_DIR/$artifact.tar.gz   testoutput/

  if [ -d testoutput  ]; then  
     rm -fr $WORKING_DIR/$OPENJDK_REPO_NAME/testoutput
  fi
  cp -fr testoutput/ $WORKING_DIR/testoutput/
  
  cd $WORKING_DIR
}

packageOnlyJCovReports()
{
  echo "Package jcov reports into archives..." 
  pwd

  cd $WORKING_DIR/$OPENJDK_REPO_NAME/build/$BUILD_FULL_NAME/
 
  artifact=${JOB_NAME}-jcov-results-only
  echo "Tarring and zipping the 'testoutput/../jcov' folder into artefact: $artifact.tar.gz" 
  tar -cvzf $WORKING_DIR/$artifact.tar.gz   testoutput/jdk_core/JTreport/jcov/

  cd $WORKING_DIR
}


echo "Archiving your jtreg results (includes jcov reports)"
packageTestResultsWithJCovReports
packageOnlyJCovReports
