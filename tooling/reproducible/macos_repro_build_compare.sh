#!/bin/bash
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

# This script examines the given sbom metadata file, and then builds the exact same binary
# and then compares with the temurin jdk for the same build version, or the optionally supplied tarball_url.
# Usage Notes:
# 1. For MacOS, jq must be installed, and the architecture to be built must match the system this script is being executed on.
# 2. This script will only work with xcode, and the executing user must have sudo permissions to run xcode-select -s
# 3. This script requires that the correct versions of the sdk are installed and in the loaction defined in the MAC_SDK_LOCATION below.

set -e

# Check All 3 Params Are Supplied
if [ "$#" -lt 3 ]; then
  echo "Usage: $0 SBOM_URL/SBOM_PATH JDKZIP_URL/JDKZIP_PATH REPORT_DIR"
  echo ""
  echo "1. SBOM_URL/SBOM_PATH - should be the FULL path OR a URL to a Temurin JDK SBOM JSON file in CycloneDX Format"
  echo "    eg. https://github.com/adoptium/temurin21-binaries/releases/download/jdk-21.0.3%2B9/OpenJDK21U-sbom_x64_mac_hotspot_21.0.3_9.json"
  echo ""
  echo "2. JDKZIP_URL/JDKZIP_PATH - should be the FULL path OR a URL to a Temurin Windows JDK Zip file"
  echo "    eg. https://github.com/adoptium/temurin21-binaries/releases/download/jdk-21.0.3%2B9/OpenJDK21U-jdk_x64_mac_hotspot_21.0.3_9.tar.gz"
  echo ""
  echo "3. REPORT_DIR - should be the FULL path OR a URL to the output directory for the comparison report"
  echo ""
  exit 1
fi

# Read Parameters
SBOM_URL="$1"
TARBALL_URL="$2"
REPORT_DIR="$3"

# Constants Required By This Script
# These Values Should Be Updated To Reflect The Build Environment
# The Defaults Below Are Suitable For An Adoptium Mac OS X Build Environment
# Which Has Been Created Via The Ansible Infrastructure Playbooks

WORK_DIR=$(realpath "$(dirname "$0")")/comp-jdk-build
MAC_COMPILER_BASE=/Applications
MAC_COMPILER_APP_PREFIX=Xcode
MAC_SDK_LOCATION=/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk

# These variables relate to the pre-requisite ant installation
ANT_VERSION="1.10.5"
ANT_CONTRIB_VERSION="1.0b3"
ANT_BASE_PATH="/usr/local/bin"

# Addiitonal Working Variables Defined For Use By This Script
SBOMLocalPath="$WORK_DIR/src_sbom.json"
DISTLocalPath="$WORK_DIR/src_jdk_dist.tar.gz"
rc=0

# Function to check if a string is a valid URL
is_url() {
  local url=$1
  if [[ $url =~ ^https?:// ]]; then
    return 0  # URL
  else
    return 1  # Not a URL
  fi
}

Create_WorkDir() {
  # Check if the folder exists & remove if it does
  echo "Checking If Working Directory: $WORK_DIR Exists"
  if [ -d "$WORK_DIR" ]; then
    # Folder exists, delete it
    rm -rf "$WORK_DIR"
    echo "Folder Exists - Removing '$WORK_DIR'"
  fi
  echo "Creating $WORK_DIR"
  mkdir -p "$WORK_DIR"
}

# Function To Check The SBOM
Check_Parameters() {
  # Check If SBOM Is URL OR LOCAL
  if is_url "$SBOM_URL" ; then
    echo "SBOM Is URL - Downloading"
    if wget --spider --server-response "$SBOM_URL" 2>&1 | grep -q "404 Not Found"; then
      echo "Error: SBOM URL Not Found"
      exit 1
    else
      # Download File As It Exists
      wget -q -O "$SBOMLocalPath" "$SBOM_URL"
    fi
  else
    echo "SBOM is Local"
    if [ -e "$SBOM_URL" ] ; then
      cp "$SBOM_URL" "$SBOMLocalPath"
    else
      echo "ERROR - The Supplied Path To The SBOM Does Not Exist"
      exit 1
    fi
  fi

  if is_url "$TARBALL_URL" ; then
    echo "JDK ZIP Is URL - Downloading"
    if wget --spider --server-response "$TARBALL_URL" 2>&1 | grep -q "404 Not Found"; then
      echo "Error: JDK ZIPFILE URL Not Found"
      exit 1
    else
      # Download File As It Exists
      wget -q -O "$DISTLocalPath" "$TARBALL_URL"
    fi
  else
    echo "JDK is Local"
    if [ -e "$TARBALL_URL" ] ; then
      cp "$TARBALL_URL" "$DISTLocalPath"
    else
      echo "ERROR - The Supplied Path To The JDK Zipfile Does Not Exist"
      exit 1
    fi
  fi
}

Install_PreReqs() {
  # Check if jq is installed
  if ! command -v jq &> /dev/null; then
    echo "Error: jq is not installed. Please install jq before running this script."
    exit 1
  else
    echo "JQ Is Installed - Continuing"
  fi
}

Get_SBOM_Values() {
  # Read the content of the SBOM file
  echo "Reading The SBOM Content & Validating The Structure.."
  echo ""
  export PATH=$PATH:/usr/bin
  sbomContent=$(jq -c '.' "$SBOMLocalPath" 2> /dev/null )
  rc=$?
  if [ "$rc" -ne 0 ] ; then
    echo "Error Reading SBOM - Exiting"
    exit 1
  fi

  # Check if the SBOM has the expected structure
  if [ -z "$sbomContent" ] || [ "$(echo "$sbomContent" | jq -r '.metadata.tools.components')" == "null" ]; then
    echo "Invalid SBOM format. Unable to extract Data."
    exit 1
  else
    echo "SBOM Is Structurally Sound.. Extracting Values:"
    echo ""
  fi

    # Extract All Required Fields From The SBOM Content
    macOSCompiler=$(echo "$sbomContent" | jq -r '.metadata.tools.components[] | select(.name == "MacOS Compiler").version')
    bootJDK=$(echo "$sbomContent" | jq -r '.metadata.tools.components[] | select(.name == "BOOTJDK").version' | sed -e 's/-LTS$//')
    buildArch=$(echo "$sbomContent" | jq -r '.metadata.properties[] | select(.name == "OS architecture").value')
    buildSHA=$(echo "$sbomContent" | jq -r '.components[0].properties[] | select(.name == "Temurin Build Ref").value' | awk -F'/' '{print $NF}')
    buildStamp=$(echo "$sbomContent" | jq -r '.components[0].properties[] | select(.name == "Build Timestamp").value')
    buildVersion=$(echo "$sbomContent" | jq -r '.metadata.component.version')
    buildArgs=$(echo "$sbomContent" | jq -r '.components[0].properties[] | select(.name == "makejdk_any_platform_args").value')

  # Check if the tool was found
  if [ -n "$macOSCompiler" ]; then
      echo "MacOS Compiler Version: $macOSCompiler"
      export macOSCompiler
  else
      echo "ERROR: MACOS Compiler Version not found in the SBOM."
      echo "This Is A Mandatory Element"
      exit 1
  fi

  # Ensure The SDK Path Is Correct
  if [ -d "$MAC_SDK_LOCATION" ]; then
      echo "Defined SDK Directory Exists"
      export MAC_SDK_LOCATION
  else
      echo "ERROR: The Defined MacOS SDK Could Not Be Found."
      exit 1
  fi

  if [ -n "$bootJDK" ]; then
      echo "Boot JDK Version: $bootJDK"
      export bootJDK
  else
      echo "ERROR: BOOTJDK Version not found in the SBOM."
      echo "This Is A Mandatory Element"
      exit 1
  fi
  if [ -n "$buildArch" ]; then
      echo "Build Arch: $buildArch"
      export msvsbuildArch
  else
      echo "ERROR: OS Architecture Information not found in the SBOM."
      echo "This Is A Mandatory Element"
      exit 1
  fi
  if [ -n "$buildSHA" ]; then
      echo "Temurin Build SHA: $buildSHA"
      export buildSHA
  else
      echo "ERROR: Temurin Build SHA not found in the SBOM."
      echo "This Is A Mandatory Element"
      exit 1
  fi
  if [ -n "$buildStamp" ]; then
      echo "Temurin Build Stamp: $buildStamp"
      export buildStamp
  else
      echo "ERROR: Temurin Timestamp not found in the SBOM."
      echo "This Is A Mandatory Element"
      exit 1
  fi
  if [ -n "$buildVersion" ]; then
      echo "Temurin Build Version: $buildVersion"
      export buildVersion
  else
      echo "ERROR: Temurin Build Version not found in the SBOM."
      echo "This Is A Mandatory Element"
      exit 1
  fi
  if [ -n "$buildArgs" ]; then
      echo "Temurin Build Arguments: $buildArgs"
      export buildArgs
  else
      echo "ERROR: Temurin Build Arguments not found in the SBOM."
      echo "This Is A Mandatory Element"
      exit 1
  fi
  echo ""
}

Check_Architecture() {
  # Get system information
  # This function may need improvements on systems that can cross compile
  systemArchitecture=$(uname -m)

  # Check if the system architecture contains "64" to determine if it's 64-bit
  if [[ $systemArchitecture == *x86_64* ]]; then
    echo "System Architecture: 64-bit (Intel)"
    sysArch="x64"
    msvsArch="x64"
  elif [[ $systemArchitecture == *86* ]]; then
    echo "System Architecture: 32-bit (Intel)"
    sysArch="x86"
    msvsArch="x86"
  elif [[ $systemArchitecture == *arm64* ]]; then
    echo "System Architecture: 64-bit (ARM)"
    sysArch="arm64"
    msvsArch="arm64"
  else
    echo "System Architecture: Other - Not Supported"
    exit 1
  fi

  if [[ "$sysArch" == "$msvsArch" ]]; then
    echo "SBOM & SYSTEM Architectures Match - All OK"
  else
    echo "ERROR - SBOM & SYSTEM Architectures DO NOT Match - Exiting"
    echo "System Arch : $sysArch"
    echo "Build Arch : $msvsArch"
    exit 1
  fi
}

Check_Compiler_Versions() {
  echo "Checking For Supported Compiler Versions..."
  echo ""
  echo "Compiler Version Returned From SBOM: $macOSCompiler"

  # Check If SBOM Has Xcode
  if [[ $macOSCompiler != *"Xcode"* ]]; then
    echo "ERROR - Xcode Compiler Not Used For Compilation Of Original JDK - This Script Does Not Currently Support This"
    exit 1
  fi

  # Derive Xcode Version From SBOM
  sbom_xcode_version=$(echo "$macOSCompiler" | grep -o 'Xcode [0-9.]*' | grep Xcode|cut -d" " -f2)
  sbom_xcode_version=$(printf "%.1f" "$sbom_xcode_version")

  # Check For Xcode Installations
  # Using The Default Installation Paths
  # Count The Number Of Xcode Installations In The System Default / Script Configuration
  # Lines 47 & 48

  echo "Checking For Xcode Compilers In : $MAC_COMPILER_BASE/"
  XCODE_PATH=()
  while IFS= read -r line; do
    XCODE_PATHS+=("$line")
  done < <(find "$MAC_COMPILER_BASE" -maxdepth 1 -type d -name "$MAC_COMPILER_APP_PREFIX*")
  XCODE_COUNT=${#XCODE_PATHS[@]}

  if  [ "$XCODE_COUNT" -eq 0 ] ; then
    echo "Error - An Xcode Installaton Could Not Be Found In The Default Path : $MAC_COMPILER_BASE / $MAC_COMPILER_APP_PREFIX "
    exit 1
  else
    echo "At Least One Xcode Installation Was Found ... Checking Versions"
    # Check If The Running User Can Sudo To Run Xcode Select
    if sudo -n xcode-select -v &>/dev/null; then
      echo "Current User Can Use Xcode Select... Continuing"
    else
      echo "Error - Current User Does Not Have Sufficient Permissions"
      exit 1
    fi
    # Check Each Version Of Xcode Against The SBOM error if not found
    for XCODE_PATH in "${XCODE_PATHS[@]}"; do
      echo "Checking Path ... $XCODE_PATH"
      # Try to select the Xcode path with sudo, and handle errors gracefully
      if sudo xcode-select -s "$XCODE_PATH"; then
        # If xcode-select succeeded, proceed to get Xcode version
        sudo xcode-select -s "$XCODE_PATH"
        if xcodebuild -version; then
          echo "Xcode Build Success - Get Version"
          XCODE_VER=$(xcodebuild -version | grep ^Xcode | cut -d" " -f2)
        else
          echo "The Xcode Build Version For The Xcode Installation In $XCODE_PATH Could Not Be Obtained"
          XCODE_VER="0.0"
        fi
        if [ "$XCODE_VER" = "$sbom_xcode_version" ]; then
          found_xcode_ver="$XCODE_VER"
          found_xcode_path="$XCODE_PATH"
        fi
      fi
    done
  fi
  if [ -z "$found_xcode_ver" ]; then
    echo "ERROR - No Xcode Installation Matching $sbom_xcode_version Could Be Identified"
    exit 1
  fi

  # Switch To Found Xcode Version
  sudo xcode-select -s "$found_xcode_path"

  # Check if clang is installed
  if ! command -v clang &> /dev/null; then
      echo "Error: clang is not installed. Please install clang before running this script."
      exit 1
  fi

  # Get clang version
  clang_version=$(clang --version | head -n 1 | cut -d' ' -f4)

  echo "Installed clang version: $clang_version"
}

Check_And_Install_Ant() {
  # Check For Existence Of Required Version Of Ant
  echo "Checking For Installation Of Ant Version $ANT_VERSION "
  if [ ! -r ${ANT_BASE_PATH}/apache-ant-${ANT_VERSION}/bin/ant ]; then
    echo "Ant Doesnt Exist At The Correct Version - Installing"
    # Ant Version Not Found... Check And Create Paths
    echo Downloading ant for SBOM creation:
    curl https://archive.apache.org/dist/ant/binaries/apache-ant-${ANT_VERSION}-bin.zip > "${WORK_DIR}"/apache-ant-${ANT_VERSION}-bin.zip
    (cd "$WORK_DIR" && unzip -qn ./apache-ant-${ANT_VERSION}-bin.zip)
    rm "$WORK_DIR"/apache-ant-${ANT_VERSION}-bin.zip
    echo Downloading ant-contrib-${ANT_CONTRIB_VERSION}:
    curl -L https://sourceforge.net/projects/ant-contrib/files/ant-contrib/${ANT_CONTRIB_VERSION}/ant-contrib-${ANT_CONTRIB_VERSION}-bin.zip > "$WORK_DIR"/ant-contrib-${ANT_CONTRIB_VERSION}-bin.zip
    (unzip -qnj "$WORK_DIR"/ant-contrib-${ANT_CONTRIB_VERSION}-bin.zip ant-contrib/ant-contrib-${ANT_CONTRIB_VERSION}.jar -d "$WORK_DIR"/apache-ant-${ANT_VERSION}/lib)
    rm "$WORK_DIR"/ant-contrib-${ANT_CONTRIB_VERSION}-bin.zip
  else
    echo "Ant Version: $ANT_VERSION Is Already Installed"
  fi
  echo ""
  # Check For Existence Of Required Version Of Ant-Contrib For Existing Ant
  echo "Checking For Installation Of Ant Contrib Version $ANT_CONTRIB_VERSION "
  if [ -r ${ANT_BASE_PATH}/apache-ant-${ANT_VERSION}/bin/ant ] && [ ! -r $ANT_BASE_PATH/apache-ant-${ANT_VERSION}/lib/ant-contrib.jar ]; then
    echo "But Ant-Contrib Is Missing - Installing"
    # Ant Version Not Found... Check And Create Paths
    echo Downloading ant-contrib-${ANT_CONTRIB_VERSION}:
    curl -L https://sourceforge.net/projects/ant-contrib/files/ant-contrib/${ANT_CONTRIB_VERSION}/ant-contrib-${ANT_CONTRIB_VERSION}-bin.zip > /tmp/ant-contrib-${ANT_CONTRIB_VERSION}-bin.zip
    (unzip -qnj /tmp/ant-contrib-${ANT_CONTRIB_VERSION}-bin.zip ant-contrib/ant-contrib-${ANT_CONTRIB_VERSION}.jar -d ${ANT_BASE_PATH}/apache-ant-${ANT_VERSION}/lib)
    rm /tmp/ant-contrib-${ANT_CONTRIB_VERSION}-bin.zip
  else
    echo "Ant Contrib Version: $ANT_CONTRIB_VERSION Is Already Installed"
  fi
}

Check_And_Install_BootJDK() {
  # Regardless Of Whats On The Machine, Install The Boot JDK Into A Working Directory
  echo "Checking The Boot JDK Version From The SBOM Exists : $bootJDK"
  if [ -d "${WORK_DIR}/jdk-${bootJDK}" ] ; then
    echo "Error - ${WORK_DIR}/jdk-${bootJDK} Exists - When It Shouldnt...Exiting"
    exit 1
  else
    echo "${WORK_DIR}/jdk-${bootJDK} Doesnt Exist - Installing"
    echo "Retrieving boot JDK $bootJDK"

    # Adjust Sys Arch For API
    if [ $msvsArch = "arm64" ] ; then NATIVE_API_ARCH="aarch64" ; fi
    if [ $msvsArch = "x64" ] ; then NATIVE_API_ARCH="x64" ; fi
    if [ $msvsArch = "x86" ] ; then NATIVE_API_ARCH="x86" ; fi

    echo "https://api.adoptium.net/v3/binary/version/jdk-${bootJDK}/mac/${NATIVE_API_ARCH}/jdk/hotspot/normal/eclipse\?project=jdk"
    echo "Downloading & Extracting.. Boot JDK Version : $bootJDK"
    curl -s -L "https://api.adoptium.net/v3/binary/version/jdk-${bootJDK}/mac/${NATIVE_API_ARCH}/jdk/hotspot/normal/eclipse?project=jdk" --output "$WORK_DIR/bootjdk.tar.gz"
    tar -xzf "$WORK_DIR/bootjdk.tar.gz" -C "$WORK_DIR"
    rm -rf "$WORK_DIR/bootjdk.tar.gz"
  fi
}

Clone_Build_Repo() {
  # Check if git is installed
  if ! command -v git &> /dev/null; then
    echo "Error: Git is not installed. Please install Git before proceeding."
    exit 1
  fi

  echo "Git is installed. Proceeding with the script."
  if [ ! -r "$WORK_DIR/temurin-build" ] ; then
    echo "Cloning Temurin Build Repository"
    echo ""
    git clone -q https://github.com/adoptium/temurin-build "$WORK_DIR/temurin-build" || exit 1
    echo "Switching To Build SHA From SBOM : $buildSHA"
    (cd "$WORK_DIR/temurin-build" && git checkout -q "$buildSHA")
    echo "Completed"
  fi
}

Prepare_Env_For_Build() {
  echo "Setting Variables"
  export BOOTJDK_HOME=$WORK_DIR/jdk-${bootJDK}/Contents/Home

  # set --build-reproducible-date if not yet
  if [[ "${buildArgs}" != *"--build-reproducible-date"* ]]; then
    buildArgs="--build-reproducible-date \"${buildStamp}\" ${buildArgs}" 
  fi
  # reset --jdk-boot-dir
  # shellcheck disable=SC2001
  buildArgs="$(echo "$buildArgs" | sed -e "s|--jdk-boot-dir [^ ]*|--jdk-boot-dir ${BOOTJDK_HOME}|")"
  # shellcheck disable=SC2001
  buildArgs="$(echo "$buildArgs" | sed -e "s|--with-sysroot=[^ ]*|--with-sysroot=${MAC_SDK_LOCATION}|")"
  # shellcheck disable=SC2001
  buildArgs="$(echo "$buildArgs" | sed -e "s|--user-openjdk-build-root-directory [^ ]*|--user-openjdk-build-root-directory ${WORK_DIR}/temurin-build/workspace/build/openjdkbuild/|")"
  # remove ingored options
  buildArgs=${buildArgs/--assemble-exploded-image /}
  buildArgs=${buildArgs/--enable-sbom-strace /}

  echo ""
  echo "Make JDK Any Platform Argument List = "
  echo "$buildArgs"
  echo ""
  echo "Parameters Parsed Successfully"
}

Build_JDK() {
  echo "Building JDK..."

  # Trigger Build
  cd "$WORK_DIR"
  echo "cd temurin-build && ./makejdk-any-platform.sh $buildArgs > build.log 2>&1" | sh
  # Copy The Built JDK To The Working Directory
  cp "$WORK_DIR"/temurin-build/workspace/target/OpenJDK*-jdk_*tar.gz "$WORK_DIR"/reproJDK.tar.gz
  cp "$WORK_DIR"/temurin-build/build.log "$WORK_DIR"/build.log
}

Compare_JDK() {
  echo "Comparing JDKs"
  echo ""
  mkdir "$WORK_DIR/compare"
  cp "$WORK_DIR"/src_jdk_dist.tar.gz "$WORK_DIR"/compare
  cp "$WORK_DIR"/reproJDK.tar.gz "$WORK_DIR"/compare
  cp "$(dirname "$0")"/repro_*.sh "$WORK_DIR"/compare/

  # Set Permissions
  chmod +x "$WORK_DIR/compare/"*sh
  cd "$WORK_DIR/compare"

  # Unzip And Rename The Source JDK
  echo "Unzip Source"
  tar xfz src_jdk_dist.tar.gz
  original_directory_name=$(find . -maxdepth 1 -type d | tail -1)
  mv "$original_directory_name" src_jdk

  #Unzip And Rename The Target JDK
  echo "Unzip Target"
  tar xfz reproJDK.tar.gz
  original_directory_name=$(find . -maxdepth 1 -type d | grep -v src_jdk | tail -1)
  mv "$original_directory_name" tar_jdk

  # Ensure Java Home Is Set
  export JAVA_HOME=$BOOTJDK_HOME
  export PATH=$JAVA_HOME/bin:$PATH
  rc=0
  ./repro_compare.sh temurin src_jdk/Contents/Home temurin tar_jdk/Contents/Home Darwin 2>&1 || rc=$?
  cd "$WORK_DIR"

  if [ $rc -eq 0 ]; then
    echo "Compare identical !"
  else
    echo "Differences found..., logged in: reprotest.diff"
  fi

  if [ -n "$REPORT_DIR" ]; then
    echo "Copying Output To $REPORT_DIR"
    cp "$WORK_DIR"/compare/reprotest.diff "$REPORT_DIR"
    cp "$WORK_DIR"/reproJDK.tar.gz "$REPORT_DIR"
    cp "$WORK_DIR"/build.log "$REPORT_DIR"
    cp "$WORK_DIR"/src_sbom.json "$REPORT_DIR"
  fi
  Clean_Up_Everything
  exit $rc 
}

#
Clean_Up_Everything() {
  # Remove Working Directorys
  rm -rf "$WORK_DIR/compare"
  rm -rf "$WORK_DIR/temurin-build"
  rm -rf "$BOOTJDK_HOME"
}

# Begin Main Script Here
echo "---------------------------------------------"
echo "Begining Reproducible Mac Build From SBOM"
echo "---------------------------------------------"
echo "Checking Environment And Parameters"
echo "---------------------------------------------"
Create_WorkDir
echo "---------------------------------------------"
Check_Parameters
echo "---------------------------------------------"
Install_PreReqs
echo "---------------------------------------------"
Get_SBOM_Values
echo "---------------------------------------------"
Check_Architecture
echo "---------------------------------------------"
Check_Compiler_Versions
echo "---------------------------------------------"
echo "All Validation Checks Passed - Proceeding To Build"
echo "---------------------------------------------"
Check_And_Install_Ant
echo "---------------------------------------------"
Check_And_Install_BootJDK
echo "---------------------------------------------"
Clone_Build_Repo
echo "---------------------------------------------"
Prepare_Env_For_Build
echo "---------------------------------------------"
Build_JDK
echo "---------------------------------------------"
Compare_JDK
