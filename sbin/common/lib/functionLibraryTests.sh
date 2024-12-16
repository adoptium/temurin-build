#!/usr/bin/bash
# ********************************************************************************
# Copyright (c) 2024 Contributors to the Eclipse Foundation
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

# A set of tests for the functionLibrary script

source functionLibrary.sh

sampleFileURL="https://github.com/adamfarley/temurin-build/tree/build_scripts_secure_mode/sbin/common/lib"
sampleFileName="sampleFileForTesting.txt"
sampleFileSha="7eb664568090f0ac7f573b25e4ac7929a48f3fb39fb34e6b21421959acdf94b4"

successTotal=0
failureTotal=0

# takes the name of the test and a boolean indicating whether it passed.
function testResults() {
  if [[ $2 == 0 ]]; then
    echo "Success: $1 has passed."
    successTotal=$((successTotal+1))
  else
    echo "Failure: $1 has failed."
    failureTotal=$((failureTotal+1))
  fi
}

# info
function infoTests(){
  # Does it work when it shouldn't?
  [[ "$(info Test)" == "" ]]
  testResults "infoTest 1" "$?"
  
  # Does it work when it should?
  info "enable" "logging"
  [[ "$(info 123)" == "123" ]]
  testResults "infoTest 2" "$?"
  
  # Clean up
  info "disable" "logging"
}

# checkFileSha
function checkFileShaTests(){
  # Does it work when it should?
  checkFileSha "${sampleFileSha}" "$(pwd)/${sampleFileName}"
  testResults "checkFileShaTest 1" "$?"

  # Does it fail when we have the wrong sha?
  checkFileSha "12345" "$(pwd)/${sampleFileName}" &> /dev/null
  [[ "$?" != "0" ]]
  testResults "checkFileShaTest 2" "$?"
}

# doesThisURLExist
function doesThisURLExistTests(){
  # Does it pass when it should?
  doesThisURLExist "https://adoptium.net/index.html"
  testResults "doesThisURLExistTest 1" "$?"

  # Does it fail when it should?
  doesThisURLExist "https://thisurlshouldneverexist123456gibberish.com" &> /dev/null
  [[ "$?" != "0" ]]
  testResults "doesThisURLExistTest 2" "$?"

  # And does it fail when it's not even a URL?
  doesThisURLExist "thisnonurlshouldneverexist123456gibberish" &> /dev/null
  [[ "$?" != "0" ]]
  testResults "doesThisURLExistTest 3" "$?"
}

# downloadFile
function downloadFileTests() {
  workdir="$(pwd)/tmp_test_work_dir"
  # Setup
  [[ -x "${workdir}" ]] && echo "Error: Temporary test work directory exists and shouldn't." && exit 1
  mkdir "${workdir}"
  [[ ! -x "${workdir}" ]] && echo "Error: Temporary test work directory could not be created." && exit 1
  
  # Clean up
  [[ ! (rm -rf "${workdir}") ]] && echo "Error: Temporary test work directory could not be deleted." && exit 1
}

echo "Test script start."
echo ""

# Test execution
infoTests
checkFileShaTests
doesThisURLExistTests
downloadFileTests

echo ""
echo "${successTotal} tests have passed."
echo "${failureTotal} tests have failed."
echo ""
if [[ $failureTotal -eq 0 ]]; then
  echo "This test script has passed."
  exit 0
else
  echo "This test script has failed."
  exit 1
fi
