#!/bin/bash
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
################################################################################

# This script examines the given SBOM metadata file, and then builds the exact same binary
# and then compares with the Temurin JDK for the same build version, or the optionally supplied TARBALL_URL.
# Requires Cygwin & Powershell Installed On Windows To Run

set -e

# Check All 3 Params Are Supplied
if [ "$#" -lt 2 ]; then
  echo "Usage: $0 SBOM_URL/SBOM_PATH JDKZIP_URL/JDKZIP_PATH"
  echo ""
  echo "1. SBOM_URL/SBOM_PATH - should be the FULL path OR a URL to a Temurin JDK SBOM JSON file in CycloneDX Format"
  echo "    eg. https://github.com/adoptium/temurin21-binaries/releases/download/jdk-21.0.2%2B13/OpenJDK21U-sbom_x64_windows_hotspot_21.0.2_13.json"
  echo ""
  echo "2. JDKZIP_URL/JDKZIP_PATH - should be the FULL path OR a URL to a Temurin Windows JDK Zip file"
  echo "    eg. https://github.com/adoptium/temurin21-binaries/releases/download/jdk-21.0.2%2B13/OpenJDK21U-jdk_x64_windows_hotspot_21.0.2_13.zip"
  echo ""
  exit 1
fi

# Read Parameters
SBOM_URL="$1"
TARBALL_URL="$2"

# Constants Required By This Script
# These Values Should Be Updated To Reflect The Build Environment
# The Defaults Below Are Suitable For An Adoptium Windows Build Environment
# Which Has Been Created Via The Ansible Infrastructure Playbooks
CURR_DIR=$(pwd)
WORK_DIR="$CURR_DIR/cmp$(date +%Y%m%d%H%M%S)"
ANT_VERSION="1.10.5"
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

# Define What Are Configure Args & Redundant Args
# This MAY Need Updating If Additional Configure Args Are Passed
CONFIG_ARGS=("--disable-warnings-as-errors" "--disable-ccache" "--with-toolchain-version" "--with-ucrt-dll-dir" "--with-version-opt")
NOTUSE_ARGS=("--assemble-exploded-image" "--configure-args")

# Addiitonal Working Variables Defined For Use By This Script
SBOMLocalPath="$WORK_DIR/src_sbom.json"
DISTLocalPath="$WORK_DIR/src_jdk_dist.zip"

# Function to check if a string is a valid URL
is_url() {
  local url=$1
  if [[ $url =~ ^https?:// ]]; then
    return 0  # URL
  else
    return 1  # Not a URL
  fi
}

# Function to check if a value is in the array
containsElement () {
  local e
  for e in "${@:2}"; do
    if [ "$e" == "$1" ]; then
      return 0  # Match found
    fi
  done
  return 1  # No match found
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
  mkdir "$WORK_DIR"
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

  # Install JQ Where Not Already Installed

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
  if [ -z "$sbomContent" ] || [ "$(echo "$sbomContent" | jq -r '.metadata.tools')" == "null" ]; then
    echo "Invalid SBOM format. Unable to extract Data."
    exit 1
  else
    echo "SBOM Is Structurally Sound.. Extracting Values:"
    echo ""
  fi

  # Extract All Required Fields From The SBOM Content
  msvsWindowsCompiler=$(echo "$sbomContent" | jq -r '.metadata.tools[] | select(.name == "MSVS Windows Compiler Version").version')
  msvsCCompiler=$(echo "$sbomContent" | jq -r '.metadata.tools[] | select(.name == "MSVS C Compiler Version").version')
  msvsCppCompiler=$(echo "$sbomContent" | jq -r '.metadata.tools[] | select(.name == "MSVS C++ Compiler Version").version')
  msvsSDKver=$(echo "$sbomContent" | jq -r '.metadata.tools[] | select(.name == "MS Windows SDK Version").version')
  bootJDK=$(echo "$sbomContent" | jq -r '.metadata.tools[] | select(.name == "BOOTJDK").version')
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
  echo "Checking For Installation Of Ant Version $ANT_VERSION "
  if [ ! -r ${ANT_BASE_PATH}/apache-ant-${ANT_VERSION}/bin/ant ]; then
    echo "Ant Doesnt Exist At The Correct Version - Installing"
    # Ant Version Not Found... Check And Create Paths
    echo Downloading ant for SBOM creation:
    curl https://archive.apache.org/dist/ant/binaries/apache-ant-${ANT_VERSION}-bin.zip > /tmp/apache-ant-${ANT_VERSION}-bin.zip
    (cd /usr/local && unzip -qn /tmp/apache-ant-${ANT_VERSION}-bin.zip)
    rm /tmp/apache-ant-${ANT_VERSION}-bin.zip
    echo Downloading ant-contrib-${ANT_CONTRIB_VERSION}:
    curl -L https://sourceforge.net/projects/ant-contrib/files/ant-contrib/${ANT_CONTRIB_VERSION}/ant-contrib-${ANT_CONTRIB_VERSION}-bin.zip > /tmp/ant-contrib-${ANT_CONTRIB_VERSION}-bin.zip
    (unzip -qnj /tmp/ant-contrib-${ANT_CONTRIB_VERSION}-bin.zip ant-contrib/ant-contrib-${ANT_CONTRIB_VERSION}.jar -d /usr/local/apache-ant-${ANT_VERSION}/lib)
    rm /tmp/ant-contrib-${ANT_CONTRIB_VERSION}-bin.zip
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

  echo "Parsing Make JDK Any Platform ARGS For Build"
  # Split the string into an array of words
  IFS=' ' read -ra words <<< "$buildArgs"

  # Add The Build Time Stamp In Case It Wasnt In The SBOM ARGS
  words+=( "--build-reproducible-date \"$buildStamp\"" )

  # Initialize variables
  param=""
  value=""
  params=()

  # Loop through the words
  for word in "${words[@]}"; do
    # Check if the word starts with '--'
    if [[ $word == --* ]] || [[ $word == -b* ]]; then
      # If a parameter already exists, store it in the params array
      if [[ -n $param ]]; then
        params+=("$param=$value")
      fi
      # Reset variables for the new parameter
      param="$word"
      value=""
    else
      value+=" $word"
    fi
  done

    # Add the last parameter to the array
  params+=("$param = $value")

  # Read the separated parameters and values into a new array
  export fixed_param=""
  export fixed_value=""
  export fixed_params=()
  export new_params=""
  CONFIG_ARRAY=()
  BUILD_ARRAY=()
  IGNORED_ARRAY=()

  for p in "${params[@]}"; do
    IFS='=' read -ra parts <<< "$p"
    prefixed_param=${parts[0]}
    fixed_param="${prefixed_param%%[[:space:]]}"
    prepped_value=${parts[1]}
    fixed_value=$(echo "$prepped_value" | awk '{$1=$1};1')

    # Handle Special parameters
    if [ "$fixed_param" == "-b" ]; then fixed_value="$fixed_value " ; fi
    if [ "$fixed_param" == "--jdk-boot-dir" ]; then fixed_value="$BOOTJDK_HOME " ; fi
    if [ "$fixed_param" == "--freetype-dir" ]; then fixed_value="$fixed_value " ; fi
    if [ "$fixed_param" == "--with-toolchain-version" ]; then fixed_value="$visualStudioVersion " ; fi
    if [ "$fixed_param" == "--with-ucrt-dll-dir" ]; then fixed_value="temporary_speech_mark_placeholder${UCRT_PARAM_PATH}temporary_speech_mark_placeholder " ; fi
    if [ "$fixed_param" == "--target-file-name" ]; then target_file="$fixed_value" ; fixed_value="$fixed_value " ; fi
    if [ "$fixed_param" == "--tag" ]; then fixed_value="$fixed_value " ; fi


    # Fix Build Variant Parameter To Strip JDK Version

    if [ "$fixed_param" == "--build-variant" ] ; then
      # Remove Leading White Space
      trimmed_value=$(echo "$prepped_value" | awk '{$1=$1};1')
      IFS=' ' read -r variant jdk <<< "$trimmed_value"
      if [[ $jdk == jdk* ]]; then
        variant="$variant "
      else
        temp="$variant "
        variant="$jdk"
        jdk="$temp"
      fi
      fixed_value=$variant
    fi

    # Check if fixed_param is in CONFIG_ARGS
    if containsElement "$fixed_param" "${CONFIG_ARGS[@]}"; then
      # Add Config Arg To New Array

      # Handle Windows Param Names In Config Args (Replace Space with =)
      if [ "$fixed_param" == "--with-toolchain-version" ] || [ "$fixed_param" == "--with-ucrt-dll-dir" ] ||  [ "$fixed_param" == "--with-version-opt" ] ; then
        STRINGTOADD="$fixed_param=$fixed_value"
        CONFIG_ARRAY+=("$STRINGTOADD")
      else
        STRINGTOADD="$fixed_param $fixed_value"
        CONFIG_ARRAY+=("$STRINGTOADD")
      fi
    elif containsElement "$fixed_param" "${NOTUSE_ARGS[@]}"; then
      # Strip Parameters To Be Ignored
      STRINGTOADD="$fixed_param $fixed_value"
      IGNORED_ARRAY+=("$STRINGTOADD")
    else
      # Not A Config Param Nor Should Be Ignored, So Add To Build Array
      STRINGTOADD="$fixed_param $fixed_value"
      BUILD_ARRAY+=("$STRINGTOADD")
    fi
  done

  for element in "${BUILD_ARRAY[@]}"; do
    build_string+="$element"
  done

  for element in "${CONFIG_ARRAY[@]}"; do
    config_string+="$element"
  done

  final_params="$build_string--configure-args \"$config_string\" $jdk"

  echo "Make JDK Any Platform Argument List = "
  echo "$final_params"
  echo ""
  echo "Parameters Parsed Successfully"
}

Build_JDK() {
  echo "Building JDK..."

  # Trigger Build
  cd "$WORK_DIR"
  echo "cd temurin-build && ./makejdk-any-platform.sh $final_params 2>&1 | tee build.$$.log" | sh
  # Copy The Built JDK To The Working Directory
  cp "$WORK_DIR/temurin-build/workspace/target/$target_file" "$WORK_DIR/built_jdk.zip"
}

Compare_JDK() {
  echo "Comparing JDKs"
  echo ""
  cd "$WORK_DIR"
  mkdir "$WORK_DIR/compare"
  cp "$WORK_DIR/src_jdk_dist.zip" "$WORK_DIR/compare"
  cp "$WORK_DIR/built_jdk.zip" "$WORK_DIR/compare"

  # Get The Current Versions Of The Reproducible Build Scripts
  wget -O "$WORK_DIR/compare/repro_common.sh" "https://raw.githubusercontent.com/adoptium/temurin-build/master/tooling/reproducible/repro_common.sh"
  wget -O "$WORK_DIR/compare/repro_compare.sh" "https://raw.githubusercontent.com/adoptium/temurin-build/master/tooling/reproducible/repro_compare.sh"
  wget -O "$WORK_DIR/compare/repro_process.sh" "https://raw.githubusercontent.com/adoptium/temurin-build/master/tooling/reproducible/repro_process.sh"

  # Set Permissions
  chmod +x "$WORK_DIR/compare/"*sh
  cd "$WORK_DIR/compare"

  # Unzip And Rename The Source JDK
  echo "Unzip Source"
  unzip -q -o src_jdk_dist.zip
  original_directory_name=$(find . -maxdepth 1 -type d | tail -1)
  mv "$original_directory_name" src_jdk

  #Unzip And Rename The Target JDK
  echo "Unzip Target"
  unzip -q -o built_jdk.zip
  original_directory_name=$(find . -maxdepth 1 -type d | grep -v src_jdk | tail -1)
  mv "$original_directory_name" tar_jdk

  # These Two Files Are Generate Classes And Should Be Removed Prior To Running The Comparison
  # jdk/bin/server/classes.jsa & jdk/bin/server/classes_nocoops.jsa

  if [ -f "$WORK_DIR/compare/src_jdk/bin/server/classes.jsa" ] ; then
    rm -rf "$WORK_DIR/compare/src_jdk/bin/server/classes.jsa"
  fi

  if [ -f "$WORK_DIR/compare/tar_jdk/bin/server/classes.jsa" ] ; then
    rm -rf "$WORK_DIR/compare/tar_jdk/bin/server/classes.jsa"
  fi

  if [ -f "$WORK_DIR/compare/src_jdk/bin/server/classes_nocoops.jsa" ] ; then
    rm -rf "$WORK_DIR/compare/src_jdk/bin/server/classes_nocoops.jsa"
  fi

  if [ -f "$WORK_DIR/compare/tar_jdk/bin/server/classes_nocoops.jsa" ] ; then
    rm -rf "$WORK_DIR/compare/tar_jdk/bin/server/classes_nocoops.jsa"
  fi

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

  # Run Comparison Script
  cd "$WORK_DIR/compare"

  CPW=$(cygpath -u "$SIGNPATHWIN")
  export PATH="$PATH:$CPW"

  # Run Comparison Script
  cd "$WORK_DIR/compare"
  ./repro_compare.sh temurin src_jdk temurin tar_jdk CYGWIN

  # Display The Content Of repro_diff.out
  echo ""
  echo "---------------------------------------------"
  echo "Output From JDK Comparison Script"
  echo "---------------------------------------------"
  cat "$WORK_DIR/compare/repro_diff.out"
  echo ""
  echo "---------------------------------------------"
  mv "$WORK_DIR/compare/repro_diff.out" "$WORK_DIR"
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
Get_SRC_UCRT_Version
echo "---------------------------------------------"
Check_UCRT_Location
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
echo "---------------------------------------------"
Clean_Up_Everything
