#!/bin/sh
# shellcheck disable=SC2155,SC2153,SC2038,SC1091,SC2116,SC2086,SC2006
# ********************************************************************************
# Copyright (c) 2017, 2024 Contributors to the Eclipse Foundation
#
# See the NOTICE file(s) with this work for additional
# information regarding copyright ownership.
#
# This program and the accompanying materials are made
# available under the terms of the Apache Software License 2.0
# which is available at https://www.apache.org/licenses/LICENSE-2.0.
#
# SPDX-License-Identifier: Apache-2.0
# ********************************************************************************
#
# dotests.sh
# Designed for running via a proxy machine for the Temurin Solaris tests
# Expects the build under test to be either in $PWD/build_artifacts or
# an accessible job name specified as UPSTREAM_JOBLINK e.g.
# https://ci.adoptium.net/job/build-scripts/job/jobs/job/jdk8u/job/jdk8u-solaris-x64-temurin-simplepipe/167
#
# Requires two parameters for the name of the test suite to run e.g.
# ./dotests.sh sanity openjdk
#

# Check for Xvfb on display :5
XVFB5=`ps -fu vagrant | awk '/Xvfb :5/ && !/awk/ {c=c+1} END {print c+0}'`
echo "XVFB5 = $XVFB5"

if [ $XVFB5 != 1 ]; then
   echo WARNING: Xvfb was not started - attempting to start ...
   nohup /usr/X11/bin/Xvfb :5 -screen 0 1024x768x24 &
   sleep 2
   XVFB5=`ps -fu vagrant | awk '/Xvfb :5/ && !/awk/ {c=c+1} END {print c+0}'`
   echo XVFB5 = $XVFB5
   [ $XVFB5 != 1 ] && echo Still failed to start Xvfb - manual intervention required && exit 1
fi
set -x
rm -rf $HOME/workspace && mkdir $HOME/workspace && WORKSPACE=$HOME/workspace && export WORKSPACE
pwd
if [ "$3" = "usecache" ]; then
  cd aqa-tests || exit 1
else
  rm -rf aqa-tests
  git clone https://github.com/adoptium/aqa-tests
  cd aqa-tests || exit 1
  if [ -z "${UPSTREAM_JOBLINK}" ]; then
    # Jenkins simpletest job will copy the artifacts to this location
    if [ ! -r "build_artifacts/filenames.txt" ]; then
       echo "ERROR: dotests.sh : UPSTREAM_JOBLINK not defined and build_artifacts/filenames.txt does not exist" - cannot progress
       exit 1
    fi
    CAT_OUTPUT=`cat build_artifacts/filenames.txt | grep "OpenJDK8U-jdk_.*tar.gz$"`
    JDK_TARBALL_NAME=`pwd`/build_artifacts/${CAT_OUTPUT}
  else
    # Linter can go do one if it objects to the backticks - "$(" is not understood by Solaris' bourne shell (SC2006)
    JDK_TARBALL_NAME=`curl -s "${UPSTREAM_JOBLINK}/artifact/workspace/target/filenames.txt" | grep "OpenJDK8U-jdk_.*tar.gz$"`
    [ -z "$JDK_TARBALL_NAME" ] && echo "Could not retrieve filenames.txt from $UPSTREAM_JOBLINK" && exit 1
    echo Downloading and extracting JDK tarball ...
    curl -O "${UPSTREAM_JOBLINK}/artifact/workspace/target/$JDK_TARBALL_NAME" || exit 1
  fi
  cd aqa-tests || exit 1
  gzip -cd "$JDK_TARBALL_NAME" | tar xpf -
  echo Downloading and extracting JRE tarball ... Required for special.openjdk jdk_math_jre_0 target
  JRE_TARBALL_NAME="`echo $JDK_TARBALL_NAME | sed s/jdk/jre/`"
  if [ "$1" = "special" ]; then
    if [ "$2" = "openjdk" ]; then
      if [ "${UPSTREAM_JOBLINK}" != "" ]; then
        curl -O "${UPSTREAM_JOBLINK}/artifact/workspace/target/$JRE_TARBALL_NAME" || exit 1
      fi
      gzip -cd "$JRE_TARBALL_NAME" | tar xpf -
    fi
  fi
fi
PWD=`pwd`
TEST_JDK_HOME=""
JRE_IMAGE=""
for FILE in "$PWD"/jdk8u*; do
  [ "`echo "$FILE" | grep -v jre`" ] && TEST_JDK_HOME="$FILE"
  [ "`echo "$FILE" | grep jre`" ] && JRE_IMAGE="$FILE"
done
env
# TODO: Check if this actually exists
[ -z "$TEST_JDK_HOME" ] && echo "Could not resolve TEST_JDK_HOME - aborting" && exit 1
echo TEST_JDK_HOME=$TEST_JDK_HOME
"$TEST_JDK_HOME/bin/java" -version || exit 1
BUILD_LIST=$2
if [ "$BUILD_LIST" = "system" ]; then
  mkdir -p "`pwd`/systemtest_prereqs/mauve" # systemtest_preqeqs not created til compile phase
  curl -o "`pwd`/systemtest_prereqs/mauve/mauve.jar" \
	https://ci.adoptium.net/job/systemtest.getDependency/lastSuccessfulBuild/artifact/systemtest_prereqs/mauve/mauve.jar
fi
GET_SH_PARAMS=""
if [ "$1" = "smoke" ]; then
  # shellcheck disable=SC2121
  set extended functional
  GET_SH_PARAMS="--vendor_repos https://github.com/adoptium/temurin-build --vendor_branches master --vendor_dirs /test/functional"
  BUILD_LIST=functional/buildAndPackage
fi
# Remove xpg4 from path as stf.pl fails to parse the xpg4 df output
PATH=/usr/local/bin:/opt/csw/bin:`echo $PATH | sed 's,/usr/xpg4/bin,,g'`
export TEST_JDK_HOME BUILD_LIST PATH JRE_IMAGE
[ "$3" != "usecache" ] && ./get.sh ${GET_SH_PARAMS}
cd TKG || exit 1
(echo VENDOR OPTIONS = $VENDOR_TEST_REPOS / $VENDOR_TEST_DIRS / $VENDOR_TEST_BRANCHES)
gmake compile
echo SXAEC: Running gmake _$1.$2 from "`pwd`"
DISPLAY=:5; export DISPLAY
gmake _$1.$2 2>&1 | tee $1.$2.$$.log
