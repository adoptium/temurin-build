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

if [[ -f /.dockerenv ]] ; then
  echo "Detected we're in docker"
  WORKING_DIR=/openjdk/jdk8u/openjdk
  # Keep as a variable for potential use later
  # if we wish to copy the results to the host
  IN_DOCKER=true
fi

echo "Running jtreg"

cd $WORKING_DIR/jdk/test

# This is the JDK we'll test
export PRODUCT_HOME=$WORKING_DIR/build/linux-x86_64-normal-server-release/images/j2sdk-image

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

echo "Running jtreg with: jtreg -conc:2 -a -verbose:fail -jdk:$PRODUCT_HOME ./ || true"

jtreg -agentvm -conc:2 -a -verbose:fail -jdk:$PRODUCT_HOME ./ || true

if [ $? -ne 0 ]; then
  echo "Failed to run jtreg, exiting"
  exit
fi

echo "Archiving your jtreg results"

zip -r jtreport.zip ./JTreport
zip -r jtwork.zip ./JTwork

mv *.zip $WORKING_DIR/
