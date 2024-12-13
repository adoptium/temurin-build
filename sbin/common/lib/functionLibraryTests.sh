#!/usr/bin/bash
# A set of tests for the functionLibrary script

source functionLibrary.sh

sampleFileURL="https://github.com/adamfarley/temurin-build/tree/build_scripts_secure_mode/sbin/common/lib"
sampleFileName="sampleFileForTesting.txt"
sampleFileSha="539446c23c650f24bb4061dc3ee50ee4a8ba68456c3fe19b86f8630f1df74465"

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
