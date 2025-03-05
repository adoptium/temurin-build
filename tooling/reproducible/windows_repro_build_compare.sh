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

# This script examines the given SBOM metadata file, and then builds the exact same binary
# and then compares with the Temurin JDK for the same build version, or the optionally supplied TARBALL_URL.
# Requires Cygwin & Powershell Installed On Windows To Run

set -e

# Check All 3 Params Are Supplied
if [ "$#" -lt 3 ]; then
  echo "Usage: $0 SBOM_URL/SBOM_PATH JDKZIP_URL/JDKZIP_PATH REPORT_DIR"
  echo ""
  echo "1. SBOM_URL/SBOM_PATH - should be the FULL path OR a URL to a Temurin JDK SBOM JSON file in CycloneDX Format"
  echo "    eg. https://github.com/adoptium/temurin21-binaries/releases/download/jdk-21.0.2%2B13/OpenJDK21U-sbom_x64_windows_hotspot_21.0.2_13.json"
  echo ""
  echo "2. JDKZIP_URL/JDKZIP_PATH - should be the FULL path OR a URL to a Temurin Windows JDK Zip file"
  echo "    eg. https://github.com/adoptium/temurin21-binaries/releases/download/jdk-21.0.2%2B13/OpenJDK21U-jdk_x64_windows_hotspot_21.0.2_13.zip"
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
# The Defaults Below Are Suitable For An Adoptium Windows Build Environment
# Which Has Been Created Via The Ansible Infrastructure Playbooks
WORK_DIR="/cygdrive/c/comp-jdk-build"
ANT_VERSION_ALLOWED="1.10"
ANT_VERSION_REQUIRED="1.10.15"
ANT_CONTRIB_VERSION="1.0b3"
ANT_BASE_PATH="/cygdrive/c/apache-ant"
CW_VS_BASE_DRV="c"
CW_VS_BASE_PATH64="/cygdrive/$CW_VS_BASE_DRV/Program Files/Microsoft Visual Studio"
CW_VS_BASE_PATH32="/cygdrive/$CW_VS_BASE_DRV/Program Files (x86)/Microsoft Visual Studio"
C_COMPILER_EXE="cl.exe"
CPP_COMPILER_EXE="cl.exe"
# The Below Path Is The Default & Should Be Updated
# If the windows SDKs are not installed in default paths
WIN_URCT_BASE="C:/Program Files (x86)/Windows Kits/10/Redist"
SIGNTOOL_BASE="C:/Program Files (x86)/Windows Kits/10"

# Addiitonal Working Variables Defined For Use By This Script
SBOMLocalPath="$WORK_DIR/src_sbom.json"
DISTLocalPath="$WORK_DIR/src_jdk_dist.zip"
ScriptPath=$(dirname "$(realpath "$0")")
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
  # Check For JQ & Install Apt-Cyg & JQ Where Not Available
  if ! command -v jq &> /dev/null; then
      echo "WARNING: JQ is not installed. Attempting To Install Via Apt-Cyg"
      echo "Checking If Apt-Cyg Is Already Installed"
      if [ -f /usr/local/bin/apt-cyg ]; then
        echo "Skipping apt-cyg Install"
        APTCYG_INSTALLED="True"
      else
        echo "Installing apt-cyg"
        APTCYG_INSTALLED="False"
        wget -q -O "./apt-cyg" "https://raw.githubusercontent.com/transcode-open/apt-cyg/master/apt-cyg"
        ACTSHASUM=$(sha256sum "apt-cyg" | awk '{print $1}')
        EXPSHASUM="d020050e2cb56fec990f16fd10695e153afd064cb0839ba935247b5a9e4c29a0"
        if [ "$ACTSHASUM" == "$EXPSHASUM" ]; then
          chmod +x apt-cyg
          mv apt-cyg /usr/local/bin
        else
          echo "Checksum Is Not OK - Exiting"
          exit 1
        fi
      fi

      echo "Checking If JQ Is Already Installed"
      if [ -f /usr/local/bin/jq ]; then
        echo "Skipping JQ Install"
        APTJQ_INSTALLED="True"
      else
        echo "Installing JQ via APTCYG"
        APTJQ_INSTALLED="False"
        apt-cyg install jq libjq1 libonig5
      fi
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
  msvsWindowsCompiler=$(echo "$sbomContent" | jq -r '.metadata.tools.components[] | select(.name == "MSVS Windows Compiler Version").version')
  msvsCCompiler=$(echo "$sbomContent" | jq -r '.metadata.tools.components[] | select(.name == "MSVS C Compiler Version").version')
  msvsCppCompiler=$(echo "$sbomContent" | jq -r '.metadata.tools.components[] | select(.name == "MSVS C++ Compiler Version").version')
  msvsSDKver=$(echo "$sbomContent" | jq -r '.metadata.tools.components[] | select(.name == "MS Windows SDK Version").version')
  bootJDK=$(echo "$sbomContent" | jq -r '.metadata.tools.components[] | select(.name == "BOOTJDK").version' | sed -e 's#-LTS$##')
  buildArch=$(echo "$sbomContent" | jq -r '.metadata.properties[] | select(.name == "OS architecture").value')
  buildSHA=$(echo "$sbomContent" | jq -r '.components[0].properties[] | select(.name == "Temurin Build Ref").value' | awk -F'/' '{print $NF}')
  buildStamp=$(echo "$sbomContent" | jq -r '.components[0].properties[] | select(.name == "Build Timestamp").value')
  buildVersion=$(echo "$sbomContent" | jq -r '.metadata.component.version')
  buildArgs=$(echo "$sbomContent" | jq -r '.components[0].properties[] | select(.name == "makejdk_any_platform_args").value')

  # Check if the tool was found
  if [ -n "$msvsWindowsCompiler" ]; then
      echo "MSVS Windows Compiler Version: $msvsWindowsCompiler"
      export msvsWindowsCompiler
  else
      echo "ERROR: MSVS Windows Compiler Version not found in the SBOM."
      echo "This Is A Mandatory Element"
      exit 1
  fi
  if [ -n "$msvsCCompiler" ]; then
      echo "MSVS C Compiler Version: $msvsCCompiler"
      export msvsCCompiler
  else
      echo "ERROR: MSVS C Compiler Version not found in the SBOM."
      echo "This Is A Mandatory Element"
      exit 1
  fi
  if [ -n "$msvsCppCompiler" ]; then
      echo "MSVS C++ Compiler Version: $msvsCppCompiler"
      export msvsCppCompiler
  else
      echo "ERROR: MSVS C++ Compiler Version not found in the SBOM."
      echo "This Is A Mandatory Element"
      exit 1
  fi
  if [ -n "$msvsSDKver" ]; then
      echo "MS Windows SDK Version: $msvsSDKver"
      export msvsSDKver
  else
      echo "WARNING: MS Windows SDK Version not found in the SBOM. - Will Derive From Source JDK"
      msvsSDKver=0
      export msvsSDKver
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
  if [[ $systemArchitecture == *64* ]]; then
    echo "System Architecture: 64-bit (Intel)"
    sysArch="x64"
    msvsArch="x64"
  elif [[ $systemArchitecture == *86* ]]; then
    echo "System Architecture: 32-bit (Intel)"
    sysArch="x86"
    msvsArch="x86"
  elif [[ $systemArchitecture == *arm64* ]]; then
    echo "System Architecture: 64-bit (ARM)"
    sysArch="Arm64"
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

Check_VS_Versions() {
  echo "Checking Visual Studio Version Retrieved From SBOM : $msvsWindowsCompiler"
  if [[ $msvsWindowsCompiler =~ ([0-9]{4}) ]]; then
    # The matched value will be stored in the BASH_REMATCH array
    visualStudioVersion=${BASH_REMATCH[1]}
    # Display the result
    echo "Visual Studio Version: $visualStudioVersion"
  else
    echo "No version information found in the string."
    exit 1
  fi

  if [[ $visualStudioVersion =~ "2022" ]]; then
    MSVS_SEARCH_PATH="$CW_VS_BASE_PATH64/2022"
  elif [[ $visualStudioVersion =~ "2019" ]]; then
    MSVS_SEARCH_PATH=$CW_VS_BASE_PATH32/2019
  elif [[ $visualStudioVersion =~ "2017" ]]; then
    MSVS_SEARCH_PATH=$CW_VS_BASE_PATH32/2017
  else
    echo "ERROR - Unsupported Visual Studio Version"
    echo "This Script Only Supports versions 2017, 2019 & 2022"
    echo "Exiting"
    echo ""
    exit 1
  fi
  echo "Visual Studio Base Path = $MSVS_SEARCH_PATH"

  # Add Host Architecture To Exe name
  C_COMPILER_PATH="Host$msvsArch/$msvsArch"
  CPP_COMPILER_PATH="Host$msvsArch/$msvsArch"

  # Define Search Path For C Compilers
  echo ""
  echo "Checking For C & C++ VS Compilers In : $MSVS_SEARCH_PATH/"

  C_CL_PATHS=$(find "$MSVS_SEARCH_PATH" -type f -name "$C_COMPILER_EXE" | grep $C_COMPILER_PATH)
  CPP_CL_PATHS=$(find "$MSVS_SEARCH_PATH" -type f -name "$CPP_COMPILER_EXE" | grep $CPP_COMPILER_PATH)

  if [ -z "$C_CL_PATHS" ] ; then
    echo "ERROR - No MSVS C Compilers Found - Exiting"
    exit 1
  fi

  if [ -z "$CPP_CL_PATHS" ] ; then
    echo "ERROR - No MSVS C++ Compilers Found - Exiting"
    exit 1
  fi

  # Set File Seperator For Handling Windows Paths
  IFS=$'\n'
  # Search For C Compilers & Check Version Against SBOM
  c_comp_count=0
  for C_COMPILER_FOUND in $C_CL_PATHS; do
    C_COMPILER_VERSION_OUTPUT=$("$C_COMPILER_FOUND" 2>&1 1>/dev/null | head -n 1 | tr -d '\r' | awk '{print $7}')
    echo "Found C Compiler : $C_COMPILER_FOUND : Version : $C_COMPILER_VERSION_OUTPUT"
    if [ "$msvsCCompiler" = "$C_COMPILER_VERSION_OUTPUT" ] ; then
      c_comp_count=$((c_comp_count + 1))
      found_c_compiler="$C_COMPILER_FOUND"
    fi
  done

  # Search For C++ Compilers
  cpp_comp_count=0
  for CPP_COMPILER_FOUND in $CPP_CL_PATHS; do
    CPP_COMPILER_VERSION_OUTPUT=$("$CPP_COMPILER_FOUND" 2>&1 1>/dev/null | head -n 1 | tr -d '\r' | awk '{print $7}')
    echo "Found C++ Compiler : $CPP_COMPILER_FOUND : Version : $CPP_COMPILER_VERSION_OUTPUT"
    if [ "$msvsCppCompiler" = "$CPP_COMPILER_VERSION_OUTPUT" ] ; then
      cpp_comp_count=$((cpp_comp_count + 1))
      found_cpp_compiler="$CPP_COMPILER_FOUND"
    fi
  done

  if [ $c_comp_count -eq 1 ] ; then
    single_c_compiler=$found_c_compiler
    export single_c_compiler
  fi

  if [ $cpp_comp_count -eq 1 ] ; then
    single_cpp_compiler=$found_cpp_compiler
    export single_cpp_compiler
  fi

  # Exit If Either Compiler Is At The Wrong Versions Or Multiple Compilers Are Detected As That Shouldnt Happen!
  if [ $c_comp_count -eq 0 ] || [ $cpp_comp_count -eq 0 ] ; then
    "ERROR - A C or C++ Compiler Matching The Version In The SBOM Could Not Be Found - Exiting"
    exit 1
  fi

  if [ $c_comp_count -gt 1 ] || [ $cpp_comp_count -gt 1 ] ; then
    "ERROR - Multiple C or C++ Compilers Matching The Version In The SBOM Were Found - Exiting"
    exit 1
  fi
}

Get_SRC_UCRT_Version() {
# Extract The ucrtbase.dll from the SRC JDK Zip File
# Requires A Jump Out To Powershell To Extract File Version From DLL
mkdir "$WORK_DIR/temp"
unzip -j -o -q "$DISTLocalPath" -d "$WORK_DIR/temp"
UCRT_FILE=$(cygpath -m "$WORK_DIR/temp/ucrtbase.dll")
SRC_UCRT_VERSION=$(powershell.exe "(Get-Command $UCRT_FILE).FileVersionInfo.FileVersion")
rm -rf "$WORK_DIR/temp"
}

Check_UCRT_Location() {
  # Check SBOM Against Version Derived From JDK
  if [ "$SRC_UCRT_VERSION" = "$msvsSDKver" ] ; then
    echo "JDK & SBOM Match"
    REQ_UCRT_VERSION="$msvsSDKver"
  else
    echo "No Match - Set To Derived Version"
    REQ_UCRT_VERSION="$SRC_UCRT_VERSION"
  fi

  if [ -z "$REQ_UCRT_VERSION" ] && [ ! -v "$REQ_UCRT_VERSION" ]; then
    echo "ERROR - No UCRT DLL Information Could Be Obtained"
    exit 1
  else
    echo "REQ UCRT = $REQ_UCRT_VERSION"
  fi

  echo "Check For UCRT DLL In : $WIN_URCT_BASE"
  URCT_CYGPATH=$(cygpath -u "$WIN_URCT_BASE")
  WIN_URCT_PATH="$URCT_CYGPATH"
  # Only Search For DLLs for the correct architecture
  UCRTCOUNT=$(find "$WIN_URCT_PATH" | grep $msvsArch | grep -ic ucrtbase.dll)
  if [ "$UCRTCOUNT" -eq 0 ] ; then
    echo "ERROR - NO ucrtbase.dll Could Be Found For The Base Path Specified - Exiting"
    exit 1
  else
    UCRT_FOUND=0
    dll_paths=$(find "$WIN_URCT_PATH" -name 'ucrtbase.dll' | grep $msvsArch 2>/dev/null)
    for dll in $dll_paths ; do
      dllpath=$(cygpath -s -m "$dll")
      # Check The Version Of Each
      FND_UCRT_VERSION=$(powershell.exe "(Get-Command $dllpath).FileVersionInfo.FileVersion")
      # If A Version Matches Required - Set Permanently
        if [ "$FND_UCRT_VERSION" = "$REQ_UCRT_VERSION" ] ; then
          UCRT_FOUND=1
          UCRT_PATH=$dllpath
        fi
      done

      if [ $UCRT_FOUND -ne 1 ] ; then
        echo "ERROR - A Version Of ucrtbase.dll matching $REQ_UCRT_VERSION was not found on this system - Exiting"
        exit 1
      fi
    fi
  # Convert The Location Of The UCRT DLL To Be A Path Parameter
  UCRT_PARAM_PATH=$(dirname "$UCRT_PATH")
  echo ""
  echo "UCRT_PATH To Be Used For Build = $UCRT_PARAM_PATH"
}

Check_And_Install_Ant() {
  # Check For Existence Of Required Version Of Ant
  ant_found=false
  for ant_path in "${ANT_BASE_PATH}/apache-ant-${ANT_VERSION}"*/bin/ant; do
      if [ -r "$ant_path" ]; then
          ant_found=true
          break
      fi
  done
  if [ "${ant_found}" != true ]; then
      echo "Ant Doesn't Exist At The Correct Version - Installing"
      # Ant Version Not Found... Check And Create Paths
      echo "Downloading ant for SBOM creation:"
      curl -o "/tmp/apache-ant-${ANT_VERSION}-bin.zip" "https://archive.apache.org/dist/ant/binaries/apache-ant-${ANT_VERSION_REQUIRED}-bin.zip"
      (cd /usr/local && unzip -qn "/tmp/apache-ant-${ANT_VERSION_REQUIRED}-bin.zip")
      rm "/tmp/apache-ant-${ANT_VERSION_REQUIRED}-bin.zip"
      echo "Downloading ant-contrib-${ANT_CONTRIB_VERSION}:"
      curl -L -o "/tmp/ant-contrib-${ANT_CONTRIB_VERSION}-bin.zip" "https://sourceforge.net/projects/ant-contrib/files/ant-contrib/${ANT_CONTRIB_VERSION}/ant-contrib-${ANT_CONTRIB_VERSION}-bin.zip"
      (unzip -qnj "/tmp/ant-contrib-${ANT_CONTRIB_VERSION}-bin.zip" "ant-contrib/ant-contrib-${ANT_CONTRIB_VERSION}.jar" -d "/usr/local/apache-ant-${ANT_VERSION}/lib")
      rm "/tmp/ant-contrib-${ANT_CONTRIB_VERSION}-bin.zip"
  else
      echo "Ant Version: ${ANT_VERSION_ALLOWED}.X Already Installed"
  fi
  echo ""
  # Check For Existence Of Required Version Of Ant-Contrib For Existing Ant
  echo "Checking For Installation Of Ant Contrib Version $ANT_CONTRIB_VERSION "
  if [ -r "${ANT_BASE_PATH}/apache-ant-${ANT_VERSION}/bin/ant" ] && [ ! -r "${ANT_BASE_PATH}/apache-ant-${ANT_VERSION}/lib/ant-contrib.jar" ]; then
    echo "But Ant-Contrib Is Missing - Installing"
    # Ant Version Not Found... Check And Create Paths
    echo Downloading ant-contrib-${ANT_CONTRIB_VERSION}:
    curl -L https://sourceforge.net/projects/ant-contrib/files/ant-contrib/${ANT_CONTRIB_VERSION}/ant-contrib-${ANT_CONTRIB_VERSION}-bin.zip > /tmp/ant-contrib-${ANT_CONTRIB_VERSION}-bin.zip
    (unzip -qnj "/tmp/ant-contrib-${ANT_CONTRIB_VERSION}-bin.zip" "ant-contrib/ant-contrib-${ANT_CONTRIB_VERSION}.jar" -d "${ANT_BASE_PATH}/apache-ant-${ANT_VERSION}/lib")
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

    echo "https://api.adoptium.net/v3/binary/version/jdk-${bootJDK}/windows/${NATIVE_API_ARCH}/jdk/hotspot/normal/eclipse?project=jdk"
    echo "Downloading & Extracting.. Boot JDK Version : $bootJDK"
    curl -s -L "https://api.adoptium.net/v3/binary/version/jdk-${bootJDK}/windows/${NATIVE_API_ARCH}/jdk/hotspot/normal/eclipse?project=jdk" --output "$WORK_DIR/bootjdk.zip"
    unzip -q "$WORK_DIR/bootjdk.zip" -d "$WORK_DIR"
    rm -rf "$WORK_DIR/bootjdk.zip"
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
  export BOOTJDK_HOME=$WORK_DIR/jdk-${bootJDK}

  # set --build-reproducible-date if not yet
  if [[ "${buildArgs}" != *"--build-reproducible-date"* ]]; then
    buildArgs="--build-reproducible-date \"${buildStamp}\" ${buildArgs}"
  fi
  # reset --jdk-boot-dir
  # shellcheck disable=SC2001
  buildArgs="$(echo "$buildArgs" | sed -e "s|--jdk-boot-dir [^ ]*|--jdk-boot-dir ${BOOTJDK_HOME}|")"
  # shellcheck disable=SC2001
  buildArgs="$(echo "$buildArgs" | sed -e "s|--with-toolchain-version [^ ]*|with-toolchain-version ${visualStudioVersion}|")"
  # shellcheck disable=SC2001
  buildArgs="$(echo "$buildArgs" | sed -e "s|--with-ucrt-dll-dir=[^ ]*|--with-ucrt-dll-dir=temporary_speech_mark_placeholder${UCRT_PARAM_PATH}temporary_speech_mark_placeholder|")"
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
  cp "${WORK_DIR}"/temurin-build/workspace/target/OpenJDK*-jdk_*.zip "$WORK_DIR/reproJDK.zip"
  cp "${WORK_DIR}"/temurin-build/build.log "$WORK_DIR/build.log"
}

Compare_JDK() {
  echo "Comparing JDKs"
  mkdir "$WORK_DIR/compare"
  cp "$WORK_DIR/src_jdk_dist.zip" "$WORK_DIR/compare"
  cp "$WORK_DIR/reproJDK.zip" "$WORK_DIR/compare"
  cd "$WORK_DIR/compare"

  # Unzip And Rename The Source JDK
  echo "Unzip Source"
  unzip -q -o src_jdk_dist.zip
  original_directory_name=$(find . -maxdepth 1 -type d | tail -1)
  mv "$original_directory_name" src_jdk

  #Unzip And Rename The Target JDK
  echo "Unzip Target"
  unzip -q -o reproJDK.zip
  original_directory_name=$(find . -maxdepth 1 -type d | grep -v src_jdk | tail -1)
  mv "$original_directory_name" tar_jdk

  # Ensure Signtool Is In The Path
  TOOLCOUNT=$(find "$SIGNTOOL_BASE" | grep $msvsArch | grep -ic "signtool.exe$")

  if [ "$TOOLCOUNT" -eq 0 ]; then
    echo "Error - Signtool Could Not Be Found In The Base Path: $SIGNTOOL_BASE - Exiting"
    exit 1
  elif [ "$TOOLCOUNT" -eq 1 ]; then
    SIGNTOOL=$(find "$SIGNTOOL_BASE" | grep $msvsArch | grep -i "signtool.exe$")
    SIGNPATHWIN=$(dirname "$SIGNTOOL")
  else
    SIGNVER=$(echo "$REQ_UCRT_VERSION" | awk -F'[ .]' '{print $3}')
    TOOLVERCOUNT=$(find "$SIGNTOOL_BASE" | grep "$msvsArch" | grep "$SIGNVER" | grep -ic "signtool.exe$")
    if [ "$TOOLVERCOUNT" -eq 0 ]; then
      echo "Error - Signtool Could Not Be Found In The Base Path: $SIGNTOOL_BASE - Exiting"
      exit 1
    elif [ "$TOOLVERCOUNT" -eq 1 ]; then
      SIGNTOOL=$(find "$SIGNTOOL_BASE" | grep "$msvsArch" | grep "$SIGNVER" | grep -i "signtool.exe$")
      SIGNPATHWIN=$(dirname "$SIGNTOOL")
    else
      # Choose The First
      SIGNTOOL=$(find "$SIGNTOOL_BASE" | grep "$msvsArch" | grep "$SIGNVER" | grep -i "signtool.exe$" | head -1)
      SIGNPATHWIN=$(dirname "$SIGNTOOL")
    fi
  fi

  # Ensure Java Home Is Set
  export JAVA_HOME=$BOOTJDK_HOME
  export PATH=$JAVA_HOME/bin:$PATH

  CPW=$(cygpath -u "$SIGNPATHWIN")
  export PATH="$PATH:$CPW"

  # Run Comparison Script
  set +e
  cd "$ScriptPath" || exit 1
  ./repro_compare.sh temurin $WORK_DIR/compare/src_jdk temurin $WORK_DIR/compare/tar_jdk CYGWIN 2>&1 &
  pid=$!
  wait $pid

  rc=$?
  set -e
  cd "$WORK_DIR"
  # Display The Content Of reprotest.diff
  echo ""
  echo "---------------------------------------------"
  echo "Output From JDK Comparison Script"
  echo "---------------------------------------------"
  cat "$ScriptPath/reprotest.diff"
  echo ""
  echo "---------------------------------------------"

  if [ -n "$REPORT_DIR" ]; then
    echo "Copying Output To $REPORT_DIR"
    cp "$ScriptPath/reprotest.diff" "$REPORT_DIR"
    cp "$WORK_DIR/reproJDK.zip" "$REPORT_DIR"
    cp "$WORK_DIR/src_sbom.json" "$REPORT_DIR"
    cp "$WORK_DIR/build.log" "$REPORT_DIR"
  fi
}

Clean_Up_Everything() {
  if [ "$APTJQ_INSTALLED" == "False" ];
  then
    if [ -f /usr/bin/jq ]; then apt-cyg remove jq libjq1 libonig5 ; fi
  fi

  if [ "$APTCYG_INSTALLED" == "False" ];
  then
    if [ -f /usr/local/bin/apt-cyg ]; then rm -f /usr/local/bin/apt-cyg ; fi
  fi
  # Remove Working Directorys
  rm -rf "$WORK_DIR/compare"
  rm -rf "$WORK_DIR/temurin-build"
  rm -rf "$BOOTJDK_HOME"
}

# Begin Main Script Here
echo "---------------------------------------------"
echo "Begining Reproducible Windows Build From SBOM"
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
Check_VS_Versions
echo "---------------------------------------------"
if [[ "${buildArgs}" != *"--use-adoptium-devkit"* ]]; then
  Get_SRC_UCRT_Version
  echo "---------------------------------------------"
  Check_UCRT_Location
  echo "---------------------------------------------"
fi
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
echo "---------------------------------------------"
Clean_Up_Everything
exit $rc
