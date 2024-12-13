#!/usr/bin/bash
# A set of tests for the functionLibrary script

source functionLibrary.sh

sampleFileURL=https://github.com/adamfarley/temurin-build
sampleFileName=sampleFileForTesting.txt
sampleFileSha="12345"

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
  info "enable"
  [[ "$(info 123)" == "123" ]]
  testResults "infoTest 2" "$?"
}

# checkFileSha
function checkFileShaTests(){
  return 0
}

# doesThisURLExist
function doesThisURLExistTests(){
  return 0
}

# downloadFile
function downloadFileTests(){
  return 0
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
