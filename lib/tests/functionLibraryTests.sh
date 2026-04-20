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

scriptLocation=$0
scriptDir="${scriptLocation%/*}"
[[ ! -r "${scriptDir}" || ! "${scriptDir}" =~ .*tests$ ]] && scriptDir="."
[[ ! -r "${scriptDir}/../functionLibrary.sh" ]] && echo "Error: Please launch this script with a full path, or from within the test directory." && exit 1

source "${scriptDir}/../functionLibrary.sh"

sampleFileURL="https://raw.githubusercontent.com/adamfarley/temurin-build/refs/heads/build_scripts_secure_mode/lib/tests"
sampleFileName="sampleFileForTesting.txt"
sampleFileSha="041bef0ff1e6d44a0464a06131d20ea21e47da9359f485f3f59c9bdb92255379"

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
  checkFileSha "${sampleFileSha}" "${scriptDir}/${sampleFileName}"
  testResults "checkFileShaTest 1" "$?"

  # Does it fail when we have the wrong sha?
  checkFileSha "12345" "${scriptDir}/${sampleFileName}" &> /dev/null
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
  workdir="${scriptDir}/tmp_test_work_dir"
  # Setup
  [[ -r "${workdir}" ]] && echo "Error: Temporary test work directory exists and shouldn't: ${workdir}" && exit 1
  mkdir "${workdir}"
  [[ ! -r "${workdir}" ]] && echo "Error: Temporary test work directory could not be created: ${workdir}" && exit 1

  # Does it pass when it should (no sha)?
  downloadFile -s "${sampleFileURL}/${sampleFileName}" -d "${workdir}"
  [[ $? == 0 && -r "${workdir}/${sampleFileName}" ]]
  testResults "downloadFileTest 1" "$?"
  rm -rf "${workdir}/*"

  # Does it pass when it should (sha)?
  downloadFile -s "${sampleFileURL}/${sampleFileName}" -d "${workdir}" -sha "${sampleFileSha}"
  [[ $? == 0 && -r "${workdir}/${sampleFileName}" ]]
  testResults "downloadFileTest 2" "$?"
  rm -rf "${workdir}/*"

  # Does it correctly rename the downloaded file?
  downloadFile -s "${sampleFileURL}/${sampleFileName}" -d "${workdir}" -sha "${sampleFileSha}" -f "newfilename"
  [[ $? == 0 && -r "${workdir}/newfilename" ]]
  testResults "downloadFileTest 3" "$?"
  rm -rf "${workdir}/*"

  # Does it fail when it should (no sha, source does not exist)?
  downloadFile -s "${sampleFileURL}/thisFileDoesNotExist" -d "${workdir}" &> /dev/null
  [[ $? != 0 && ! -r "${workdir}/${sampleFileName}" ]]
  testResults "downloadFileTest 4" "$?"

  # Does it fail when it should (with sha, source does not exist)?
  downloadFile -s "${sampleFileURL}/thisFileDoesNotExist" -d "${workdir}" -sha "${sampleFileSha}" &> /dev/null
  [[ $? != 0 && ! -r "${workdir}/${sampleFileName}" ]]
  testResults "downloadFileTest 5" "$?"

  # Does it fail when it should (with invalid sha, source exists)?
  downloadFile -s "${sampleFileURL}/${sampleFileName}" -d "${workdir}" -sha "thisisaninvalidsha12345" -f "newfilename" &> /dev/null
  [[ $? != 0 && ! -r "${workdir}/newfilename" ]]
  testResults "downloadFileTest 6" "$?"

  # Does it fail when it should (secure mode)?
  downloadFile -s "${sampleFileURL}/${sampleFileName}" -d "${workdir}" -secure "true" &> /dev/null
  [[ $? != 0 && ! -r "${workdir}/newfilename" ]]
  testResults "downloadFileTest 7" "$?"

  # Clean up
  rm -rf "${workdir}"
  [[ $? != 0 ]] && echo "Error: Temporary test work directory could not be deleted." && exit 1
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
