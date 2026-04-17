#!/bin/bash
# shellcheck disable=SC2129
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

# Shellcheck SC2129 disabled, as per line echo is more readable

# This script examines the given sbom metadata file, and then builds the exact same binary
# and then compares with the temurin jdk for the same build version, or the optionally supplied tarball_url.
# Usage Notes:
# 1. For MacOS, jq must be installed, and the architecture to be built must match the system this script is being executed on.
# 2. This script will only work with xcode, and the executing user must have sudo permissions to run xcode-select -s

set -e

# Adoptium's public GPG key used for GPG signatures
ADOPTIUM_PUBLIC_GPG_KEY="0x3B04D753C9050D9A5D343F39843C48A565F8F04B"

# Read Parameters
SBOM_URL=""
TARBALL_URL=""
REPRODUCIBLE_VERIFICATION=false
BUILD_WORKSPACE=""

ScriptPath=$(dirname "$(realpath "$0")")
      
while [[ $# -gt 0 ]] ; do
  opt="$1";
  shift; 
        
  echo "Parsing opt: ${opt}"
  case "$opt" in
    "--sbom-url" )
    SBOM_URL="$1"; shift;;
    
    "--jdk-url" )
    TARBALL_URL="$1"; shift;;

    "--reproducible-verification" ) 
    REPRODUCIBLE_VERIFICATION=true;;
          
    "--build-workspace" )
    BUILD_WORKSPACE="$1"; shift;;
        
    *) echo >&2 "Invalid option: ${opt}"; exit 1;;
  esac    
done    
      
# Check All Required Params Are Supplied
if [ -z "$SBOM_URL" ] || [ -z "$TARBALL_URL" ]; then
  echo "Usage: macos_repro_build_compare.sh [Params]"
  echo "Parameters:"
  echo "  Required:"
  echo "    --sbom-url [SBOM_URL/SBOM_PATH] : should be the FULL path OR a URL to a Temurin JDK SBOM JSON file in CycloneDX Format"
  echo "    --jdk-url [JDK_URL/JDK_PATH] : should be the FULL path OR a URL to a Temurin MacOS JDK tarball file"
  echo "  Optional:"
  echo "    --reproducible-verification : Enables Reproducible Verification mode, where native OpenJDK source and make used rather than temurin-build scripts"
  echo "    --build-workspace : FULL path to the location to perform the reproducible build within"
  exit 1
fi

# Constants Required By This Script
# These Values Should Be Updated To Reflect The Build Environment
# The Defaults Below Are Suitable For An Adoptium Mac OS X Build Environment
# Which Has Been Created Via The Ansible Infrastructure Playbooks

MAC_COMPILER_BASE=/Applications
MAC_COMPILER_APP_PREFIX=Xcode
XCODE_PATH_FOUND=""
XCODE_SYSROOT=""

# These variables relate to the pre-requisite ant installation
ANT_VERSION="1.10.5"
ANT_CONTRIB_VERSION="1.0b3"
ANT_BASE_PATH="/usr/local/bin"

# Addiitonal Working Variables Defined For Use By This Script
SBOMLocalPath="$PWD/src_sbom.json"
DISTLocalPath="$PWD/src_jdk_dist.tar.gz"
JDK_TAR_HASH=""
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
    echo "JDK TARBALL Is URL - Downloading"
    if wget --spider --server-response "$TARBALL_URL" 2>&1 | grep -q "404 Not Found"; then
      echo "Error: JDK URL Not Found"
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
  JDK_TAR_HASH=$(shasum -a 256 "$DISTLocalPath" | cut -d' ' -f1)
}

Check_PreReqs() {
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
  macOSSDK=$(echo "$sbomContent" | jq -r '.metadata.tools.components[] | select(.name == "MacOS SDK Version").version')
  BOOTJDK_VERSION=$(echo "$sbomContent" | jq -r '.metadata.tools.components[] | select(.name == "BOOTJDK").version' | sed -e 's/-LTS$//')
  buildArch=$(echo "$sbomContent" | jq -r '.metadata.properties[] | select(.name == "OS architecture").value')
  TEMURIN_BUILD_REF=$(echo "$sbomContent" | jq -r '.components[0].properties[] | select(.name == "Temurin Build Ref").value')
  TEMURIN_BUILD_REPO="${TEMURIN_BUILD_REF%/commit/*}"
  TEMURIN_BUILD_SHA=$(basename "$TEMURIN_BUILD_REF")
  TEMURIN_COMPONENT_VERSION=$(echo "$sbomContent" | jq -r '.metadata.component.version')
  TEMURIN_VERSION="jdk-"$(echo "$sbomContent" | jq -r '.metadata.component.version' | sed 's/-beta//' | cut -f1 -d"-")
  buildStamp=$(echo "$sbomContent" | jq -r '.components[0].properties[] | select(.name == "Build Timestamp").value')
  TEMURIN_BUILD_ARGS=$(echo "$sbomContent" | jq -r '.components[0].properties[] | select(.name == "makejdk_any_platform_args").value')
  BUILD_WORKSPACE_DIRECTORY=$(echo "$sbomContent" | jq -r '.components[0] | .properties[] | select (.name == "Build Workspace Directory") | .value')
  BUILD_SCM_REF=$(echo "$sbomContent" | jq -r '.components[0].properties[] | select(.name == "SCM Ref") | .value')

  # Temurin beta-ea builds have release tags ending "-ea-beta"
  if [[ "$TEMURIN_COMPONENT_VERSION" == *-beta*-ea ]]; then
    TEMURIN_VERSION="${TEMURIN_VERSION}-ea-beta"
  fi

  if [ "$REPRODUCIBLE_VERIFICATION" == true ]; then
    adoptiumSrcCommitUrl=$(echo "$sbomContent" | jq -r '.components[0].properties[] | select(.name == "OpenJDK Source Commit") | .value')
    adoptiumConfigureArgs=$(echo "$sbomContent" | jq -r '.components[0].properties[] | select(.name == "configure_args") | .value')
  
    # Check if the adoptiumSrcCommitUrl and configure_args were found
    if [ -n "$adoptiumSrcCommitUrl" ] && [ -n "$adoptiumConfigureArgs" ]; then
      adoptiumRepo="${adoptiumSrcCommitUrl%/commit/*}"
      adoptiumBuildCommitSHA=$(basename "$adoptiumSrcCommitUrl")
      openjdkSourceRepo="${adoptiumRepo/adoptium/openjdk}"
      openjdkSourceCommitSHA=$(getUpstreamOpenJDKCommitSHA "$adoptiumRepo" "$openjdkSourceRepo" "$adoptiumBuildCommitSHA")
  
      echo "Performing a Reproducible Verification Build from $openjdkSourceRepo with commit SHA $openjdkSourceCommitSHA"
      echo "Adoptium OpenJDK configure argmuents from original Temurin build:"
      echo "    $adoptiumConfigureArgs"
      echo ""
      export openjdkSourceRepo
      export openjdkSourceCommitSHA
      export adoptiumConfigureArgs
    else
      echo "ERROR: Adoptium OpenJDK Source Commit, SCM Ref and configure_args must be specified in the SBOM."
      echo "These Are Mandatory Elements"
      exit 1
    fi
  fi

  # Remove any --with-jobs, let local user system determine
  # Remove any --user-openjdk-build-root-directory as that will be local to original system
  # shellcheck disable=SC2001
  TEMURIN_BUILD_ARGS=$(echo "$TEMURIN_BUILD_ARGS" | sed -e "s/--with-jobs=[0-9]*//g" | sed -e "s/--user-openjdk-build-root-directory[ ]*[^ ]*//g")

  # Check if the tool was found
  if [ -n "$macOSCompiler" ]; then
      echo "MacOS Compiler Version: $macOSCompiler"
      export macOSCompiler
  else
      echo "ERROR: MACOS Compiler Version not found in the SBOM."
      echo "This Is A Mandatory Element"
      exit 1
  fi

  # Check if the SDK was found
  if [ -n "$macOSSDK" ]; then
      echo "MacOS SDK Version: $macOSSDK"
      export macOSSDK
  else
      echo "WARNING: MACOS SDK Version not found in the SBOM."
      macOSSDK=""
      export macOSSDK
  fi

  if [ -n "$BOOTJDK_VERSION" ]; then
      echo "SBOM Boot JDK Version: $BOOTJDK_VERSION"
      export BOOTJDK_VERSION
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
  if [ -n "$TEMURIN_BUILD_REPO" ]; then
      echo "TEMURIN_BUILD_REPO: $TEMURIN_BUILD_REPO"
      export TEMURIN_BUILD_REPO
  else
      echo "ERROR: Temurin Build Ref not found in the SBOM."
      echo "This Is A Mandatory Element"
      exit 1
  fi
  if [ -n "$TEMURIN_BUILD_SHA" ]; then
      echo "TEMURIN_BUILD_SHA: $TEMURIN_BUILD_SHA"
      export TEMURIN_BUILD_SHA
  else
      echo "ERROR: Temurin Build Ref not found in the SBOM."
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
  if [ -n "$TEMURIN_VERSION" ]; then
      echo "Temurin Build Version: $TEMURIN_VERSION"
      export TEMURIN_VERSION
  else
      echo "ERROR: Temurin Build Version not found in the SBOM."
      echo "This Is A Mandatory Element"
      exit 1
  fi
  if [ -n "$TEMURIN_BUILD_ARGS" ]; then
      echo "SBOM Temurin Build Arguments: $TEMURIN_BUILD_ARGS"
      export TEMURIN_BUILD_ARGS
  else
      echo "ERROR: Temurin Build Arguments not found in the SBOM."
      echo "This Is A Mandatory Element"
      exit 1
  fi
  echo ""
}

getUpstreamOpenJDKCommitSHA() {
  local adoptiumMirrorRepo="$1"
  local openjdkSourceRepo="$2"
  local adoptiumBuildCommitSHA="$3"

  # Shallow clone commit history only
  git clone --filter=tree:0 "$adoptiumMirrorRepo" adoptium_mirror_repo

  # Find upstream OpenJDK commit SHA, which is the first non-merge commit from the adoptiumBuildCommitSHA
  openjdkCommitSHA=$(cd adoptium_mirror_repo && git log --no-merges -1 "$adoptiumBuildCommitSHA" --format=%H)

  rm -rf adoptium_mirror_repo

  echo "$openjdkCommitSHA"
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
  XCODE_PATHS=()
  while IFS= read -r line; do
    XCODE_PATHS+=("$line")
  done < <(find "$MAC_COMPILER_BASE" -maxdepth 1 -type d -name "$MAC_COMPILER_APP_PREFIX*")
  XCODE_COUNT=${#XCODE_PATHS[@]}

  if  [ "$XCODE_COUNT" -eq 0 ] ; then
    echo "Error - An Xcode Installaton Could Not Be Found In The Default Path : $MAC_COMPILER_BASE / $MAC_COMPILER_APP_PREFIX "
    exit 1
  else
    echo "At Least One Xcode Installation Was Found ... Checking Versions"
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
          break
        fi
      fi
    done
  fi
  if [ -z "$found_xcode_ver" ]; then
    echo "ERROR - No Xcode Installation Matching $sbom_xcode_version Could Be Identified"
    exit 1
  fi

  echo "Found required XCode version $found_xcode_ver, at $found_xcode_path"

  # Switch To Found Xcode Version
  sudo xcode-select -s "$found_xcode_path"
  XCODE_PATH_FOUND="$found_xcode_path"

  if [ -n "$macOSSDK" ]; then
    echo "Searching for installed MacOS SDK of required version to match original build: ${macOSSDK}"

    SDK_PATHS=()
    while IFS= read -r line; do
      SDK_PATHS+=("$line")
    done < <(find "$XCODE_PATH_FOUND/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs" -mindepth 1 -maxdepth 1 -type d -name "*")

    # Check Each Version Of Xcode SDKs against The SBOM
    for SDK_PATH in "${SDK_PATHS[@]}"; do
      echo "Checking SDK version for : $SDK_PATH"
      local sdk_version
      sdk_version="$(plutil -p "${SDK_PATH}/SDKSettings.plist" | grep '"Version"')"
      local macx_sdk_version
      macx_sdk_version="$(echo "${sdk_version}" | awk -F'"' '{print $4}')"

      if [ -n "$macx_sdk_version" ] && [ "$macx_sdk_version" == "$macOSSDK" ]; then
        XCODE_SYSROOT="$SDK_PATH"
        echo "Found required MacOS SDK version '${macOSSDK}' in path '${SDK_PATH}'"
        break
      else
        echo "${SDK_PATH} SDK version ${macx_sdk_version} does not match required: ${macOSSDK}"
      fi
    done

    if [ -z "$XCODE_SYSROOT" ]; then
      echo "WARNING: No matching MacOS SDK version (${macOSSDK}) available in ${XCODE_PATH_FOUND}/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs, OpenJDK configure will find most suitable, which may not necessarily match for reproducibility."
    fi
  else
    echo "WARNING: No SBOM MacOS SDK version available, OpenJDK configure will find most suitable, which may not necessarily match for reproducibility."
  fi

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
    curl https://archive.apache.org/dist/ant/binaries/apache-ant-${ANT_VERSION}-bin.zip > apache-ant-${ANT_VERSION}-bin.zip
    (unzip -qn ./apache-ant-${ANT_VERSION}-bin.zip)
    rm apache-ant-${ANT_VERSION}-bin.zip
    echo Downloading ant-contrib-${ANT_CONTRIB_VERSION}:
    curl -L https://sourceforge.net/projects/ant-contrib/files/ant-contrib/${ANT_CONTRIB_VERSION}/ant-contrib-${ANT_CONTRIB_VERSION}-bin.zip > ant-contrib-${ANT_CONTRIB_VERSION}-bin.zip
    (unzip -qnj ant-contrib-${ANT_CONTRIB_VERSION}-bin.zip ant-contrib/ant-contrib-${ANT_CONTRIB_VERSION}.jar -d apache-ant-${ANT_VERSION}/lib)
    rm ant-contrib-${ANT_CONTRIB_VERSION}-bin.zip
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

Install_BootJDK() {
  # Adjust Sys Arch For API
  if [ $msvsArch = "arm64" ] ; then NATIVE_API_ARCH="aarch64" ; fi
  if [ $msvsArch = "x64" ] ; then NATIVE_API_ARCH="x64" ; fi
  if [ $msvsArch = "x86" ] ; then NATIVE_API_ARCH="x86" ; fi

  local api_query="https://api.adoptium.net/v3/binary/version/jdk-${BOOTJDK_VERSION}/mac/${NATIVE_API_ARCH}/jdk/hotspot/normal/eclipse?project=jdk"
  local sig_query=""
  echo "Trying to get BootJDK jdk-${BOOTJDK_VERSION} from ${api_query}"
  if ! curl --fail -L -o bootjdk.tar.gz "${api_query}"; then
    echo "Unable to download BootJDK version jdk-${BOOTJDK_VERSION} from ${api_query}"
    local major_version
    major_version=$(echo "${BOOTJDK_VERSION}" | cut -d'.' -f1)
    api_query="https://api.adoptium.net/v3/binary/latest/${major_version}/ga/mac/${NATIVE_API_ARCH}/jdk/hotspot/normal/eclipse"
    echo "Trying to get latest GA for version ${major_version} from ${api_query}"
    if ! curl --fail -L -o bootjdk.tar.gz "${api_query}"; then
      echo "Unable to download BootJDK version jdk-${BOOTJDK_VERSION} from ${api_query}"
      api_query="https://api.adoptium.net/v3/assets/feature_releases/${major_version}/ea?architecture=${NATIVE_API_ARCH}&image_type=jdk&jvm_impl=hotspot&os=mac&page=0&page_size=10&project=jdk&sort_method=DATE&sort_order=DESC&vendor=eclipse"
      rm -f ea_assets.json
      if curl --fail -L -o ea_assets.json "${api_query}"; then
        api_query=$(jq -r '.[0] | .binaries[0] | .package | .link' "ea_assets.json")
        sig_query=$(jq -r '.[0] | .binaries[0] | .package | .signature_link' "ea_assets.json")
        echo "Trying to get latest EA for version ${major_version} from ${api_query}"
        if ! curl --fail -L -o bootjdk.tar.gz "${api_query}"; then
          echo "Unable to download BootJDK from ${api_query}"
          exit 2
        fi
      else
        echo "Unable to query BootJDK from ${api_query}"
        exit 2
      fi
    fi 
  fi
  # Update BOOTJDK_VERSION with actual one downloaded
  BOOTJDK_VERSION=$(tar -tf bootjdk.tar.gz | cut -d/ -f1 | head -n 1 | sed 's/^jdk-//')
  if [ -z "$sig_query" ]; then
    sig_query="https://api.adoptium.net/v3/signature/version/jdk-${BOOTJDK_VERSION}/mac/${NATIVE_API_ARCH}/jdk/hotspot/normal/eclipse?project=jdk"
  fi
  
  echo "Downloading gpg signature for ${BOOTJDK_VERSION}.."
  if ! curl --fail -L -o bootjdk.tar.gz.sig "${sig_query}"; then
    echo "Unable to download BootJDK gpg signature for jdk-${BOOTJDK_VERSION} from ${sig_query}"
    exit 2
  fi
  
  echo "Obtaining Adoptium's public GPG key.."
  curl -sSL "https://keyserver.ubuntu.com/pks/lookup?op=get&search=${ADOPTIUM_PUBLIC_GPG_KEY}" --output "adoptium.gpg.key"
  gpg --import "adoptium.gpg.key" 
  rm "adoptium.gpg.key"
  if ! gpg --verify "bootjdk.tar.gz.sig" "bootjdk.tar.gz"; then
    echo "GPG Verify of bootjdk.tar.gz failed"
    exit 1
  fi
  
  echo "Using downloaded BOOTJDK_VERSION=${BOOTJDK_VERSION}"
  mkdir -p "$PWD/bootjdk" && tar -xzf bootjdk.tar.gz -C "$PWD/bootjdk"
  export PATH=$PWD/bootjdk/jdk-${BOOTJDK_VERSION}/bin:$PATH
  export BOOTJDK_HOME=$PWD/bootjdk/jdk-${BOOTJDK_VERSION}/Contents/Home
  rm bootjdk.tar.gz
  rm bootjdk.tar.gz.sig
}

# Generated-by: IBM Bob
# resolve_path() - Canonicalize a file path by resolving . and .. components
#
# This function performs logical path resolution (string manipulation) without
# checking if the path exists in the filesystem. It mimics the behavior of
# GNU coreutils 'realpath -m' command, which is not available on macOS.
#
# Features:
#   - Converts relative paths to absolute paths
#   - Resolves '.' (current directory) references
#   - Resolves '..' (parent directory) references
#   - Works with non-existent paths
#   - Compatible with bash 3.2+ (macOS default)
#
# Usage:
#   canonical_path=$(resolve_path "$path")
#
resolve_path() {
    local path="$1"
    
    # Make absolute
    [[ "$path" != /* ]] && path="$PWD/$path"
    
    # Process path components
    local -a parts resolved=()
    IFS='/' read -ra parts <<< "$path"
    
    for part in "${parts[@]}"; do
        case "$part" in
            ""|".") continue ;;
            "..") 
                # Remove last element (bash 3.2+ compatible)
                if [[ ${#resolved[@]} -gt 0 ]]; then
                    unset "resolved[${#resolved[@]}-1]"
                fi
                ;;
            *) resolved+=("$part") ;;
        esac
    done
    
    # Reconstruct path
    printf "/%s" "${resolved[@]}" | sed 's|/$||; s|^$|/|'
}

# Pad the BUILD_DIR/BUILD_FOLDER to the same length as TARGET_BUILD_DIR_TO_MATCH.
# Necessary to avoid potential non-determinstic classes.jsa on Linux and binary differences on Mac
padBuildDirToSameLength() {
  local TARGET_BUILD_DIR_TO_MATCH
  TARGET_BUILD_DIR_TO_MATCH=$(resolve_path "$1")
  local WS_BUILD_DIR
  WS_BUILD_DIR=$(resolve_path "$2")
  local WS_BUILD_FOLDER="$3"

  local WS_DIR="${WS_BUILD_DIR}/${WS_BUILD_FOLDER}"

  local padding_length=$((${#TARGET_BUILD_DIR_TO_MATCH} - ${#WS_DIR}))
  if [[ "$padding_length" -eq 0 ]]; then
    echo "Warning: $TARGET_BUILD_DIR_TO_MATCH and $WS_DIR are already same length" 1>&2
    echo ""
  elif [[ "$padding_length" -lt 0 ]] || [[ "$padding_length" -eq 1 ]]; then
    echo "Warning: Unable to pad $WS_DIR to necessary length of $TARGET_BUILD_DIR_TO_MATCH, padding required: $padding_length" 1>&2
    echo ""
  else
    padding_length=$((padding_length - 1))
    local padding
    padding=$(printf "P%.0s" $(seq 1 $padding_length))
    local padded="${WS_BUILD_DIR}/${padding}"
    echo "Padded $WS_BUILD_DIR with sub-folder to $padded" 1>&2
    echo "${padded}"
  fi
}

# Construct "build dir" from current/workspace directory plus BUILD_FOLDER
# Padding to BUILD_WORKSPACE_DIRECTORY length if known
setupBuildDir() {
  if [[ -n "$BUILD_WORKSPACE" ]]; then
    BUILD_DIR="$BUILD_WORKSPACE"
  else
    BUILD_DIR="$PWD/build"
  fi

  # If we have the original build workspace folder, create padded sub-folder to match to help
  # ensure deterministic classes.jsa
  if [[ -n "$BUILD_WORKSPACE_DIRECTORY" ]]; then
    local PADDED_BUILD_DIR
    PADDED_BUILD_DIR=$(padBuildDirToSameLength "$BUILD_WORKSPACE_DIRECTORY" "$BUILD_DIR" "$BUILD_FOLDER")
    if [[ -n "$PADDED_BUILD_DIR" ]]; then
      BUILD_DIR="$PADDED_BUILD_DIR"
    fi
  fi

  # Create build dir
  mkdir -p "$BUILD_DIR" || exit 1
}

setTemurinBuildArgs() {
  echo "Setting Variables"

  # set --build-reproducible-date if not yet
  if [[ "${TEMURIN_BUILD_ARGS}" != *"--build-reproducible-date"* ]]; then
    TEMURIN_BUILD_ARGS="--build-reproducible-date \"${buildStamp}\" ${TEMURIN_BUILD_ARGS}" 
  fi
  # reset --jdk-boot-dir
  # shellcheck disable=SC2001
  TEMURIN_BUILD_ARGS="$(echo "$TEMURIN_BUILD_ARGS" | sed -e "s|--jdk-boot-dir [^ ]*|--jdk-boot-dir ${BOOTJDK_HOME}|")"
  # remove ingored options
  TEMURIN_BUILD_ARGS=${TEMURIN_BUILD_ARGS/--assemble-exploded-image /}
  TEMURIN_BUILD_ARGS=${TEMURIN_BUILD_ARGS/--enable-sbom-strace /}

  # Specific commit sha to clone
  TEMURIN_BUILD_ARGS="--branch ${BUILD_SCM_REF} $TEMURIN_BUILD_ARGS"

  # Must do full clone to be able to build from commit sha
  TEMURIN_BUILD_ARGS="--disable-shallow-git-clone $TEMURIN_BUILD_ARGS"

  echo ""
  echo "Make JDK Any Platform Argument List = "
  echo "$TEMURIN_BUILD_ARGS"
  echo ""
  echo "Parameters Parsed Successfully"
}

buildUsingTemurinBuild() {
  echo "Building JDK using temurin-build scripts..."
  
  # Build folder must match temurin-build "workspace/build/src"
  BUILD_FOLDER="workspace/build/src"
  setupBuildDir
  echo "  building within workspace folder: $BUILD_DIR/$BUILD_FOLDER"

  # Checkout required temurin-build SHA into BUILD_DIR
  (cd "$BUILD_DIR" && git init . && git remote add origin "$TEMURIN_BUILD_REPO" && git fetch --depth 1 --filter=blob:none origin "$TEMURIN_BUILD_SHA" && git checkout FETCH_HEAD)
  
  echo "Rebuild args for makejdk_any_platform.sh are: $TEMURIN_BUILD_ARGS"
  if ! echo "cd $BUILD_DIR && TZ=UTC ./makejdk-any-platform.sh $TEMURIN_BUILD_ARGS > build.log 2>&1" | sh; then
   SBOMLocalPath # Echo build.log
    cat "$BUILD_DIR/build.log" || true
    echo "makejdk-any-platform.sh build failure, exiting"
    exit 1
  fi
  
  # Echo build.log
  cat "$BUILD_DIR/build.log"

  cp "$BUILD_DIR"/workspace/target/OpenJDK*-jdk_*tar.gz reproJDK.tar.gz

  mkdir reproJDK && tar xpfz reproJDK.tar.gz -C reproJDK
  cp "$BUILD_DIR/build.log" build.log
  cp "$SBOMLocalPath" SBOM.json
} 

setOpenJDKConfigureArgs() {
  # reset --jdk-boot-dir and remove --with-cacerts-src
  # shellcheck disable=SC2001
  adoptiumConfigureArgs="$(echo "$adoptiumConfigureArgs" | sed -e "s|--with-boot-jdk=[^ ]*|--with-boot-jdk=${BOOTJDK_HOME}|")"
  # shellcheck disable=SC2001
  adoptiumConfigureArgs="$(echo "$adoptiumConfigureArgs" | sed -e "s|--with-cacerts-src=[^ ]*||")"

  # replace --with-sysrootwith found local one, or remove if one not found
  if [ -n "$XCODE_SYSROOT" ]; then
    # shellcheck disable=SC2001
    adoptiumConfigureArgs="$(echo "$adoptiumConfigureArgs" | sed -e "s|--with-sysroot=[^ ]*|--with-sysroot=${XCODE_SYSROOT}|")"
  else
    # shellcheck disable=SC2001
    adoptiumConfigureArgs="$(echo "$adoptiumConfigureArgs" | sed -e "s|--with-sysroot=[^ ]*||")"
  fi

  echo ""
  echo "OpenJDK Configure Argument List = "
  echo "$adoptiumConfigureArgs"
  echo ""
}

attestationBuildUsingOpenJDK() {
  echo "Building JDK using OpenJDK configure and make..."
  
  local CURRENT_PWD="$PWD"
  
  BUILD_FOLDER="src"
  setupBuildDir
  mkdir -p "$BUILD_DIR/$BUILD_FOLDER"
  echo "  building within workspace folder: $BUILD_DIR/$BUILD_FOLDER"
  
  echo "Cloning OpenJDK source Repository: $openjdkSourceRepo commit SHA $openjdkSourceCommitSHA into $BUILD_DIR/$BUILD_FOLDER"
  (cd "$BUILD_DIR/$BUILD_FOLDER" && git init . && git remote add origin "$openjdkSourceRepo" && git fetch --depth 1 --filter=blob:none origin "$openjdkSourceCommitSHA" && git checkout FETCH_HEAD)

  echo "Executing: bash ./configure $adoptiumConfigureArgs"
  if ! echo "cd $BUILD_DIR/$BUILD_FOLDER && TZ=UTC bash ./configure $adoptiumConfigureArgs > repro_configure.log 2>&1" | sh; then
    cat "$BUILD_DIR/$BUILD_FOLDER/repro_configure.log" || true
    echo "OpenJDK configure failure, exiting"
    exit 1
  fi

  cat "$BUILD_DIR/$BUILD_FOLDER/repro_configure.log"

  echo "Executing: make images"
  if ! echo "cd $BUILD_DIR/$BUILD_FOLDER/build/* && TZ=UTC make images > ../../repro_build.log 2>&1" | sh; then
    cat "$BUILD_DIR/$BUILD_FOLDER/repro_build.log" || true
    echo "OpenJDK make images failure, exiting"
    exit 1
  fi 

  cat "$BUILD_DIR/$BUILD_FOLDER/repro_build.log"

  mv "$BUILD_DIR/$BUILD_FOLDER"/build/*/images/jdk-bundle/jdk-*.jdk "$BUILD_DIR/$BUILD_FOLDER/build/$TEMURIN_VERSION"
  (cd "$BUILD_DIR/$BUILD_FOLDER/build" && tar -czf "${CURRENT_PWD}/reproJDK.tar.gz" "$TEMURIN_VERSION")

  mkdir reproJDK && tar xpfz reproJDK.tar.gz -C reproJDK
  cp  "$BUILD_DIR/$BUILD_FOLDER/repro_configure.log" build.log
  cat "$BUILD_DIR/$BUILD_FOLDER/repro_build.log"  >> build.log
  cp "$SBOMLocalPath" SBOM.json
}

Compare_JDK() {
  echo Comparing ...
  cp "$ScriptPath"/repro_*.sh "$PWD"
  chmod +x "$PWD"/repro_*.sh

  sourceJDK="${TEMURIN_VERSION}"
  mkdir "${sourceJDK}"
  tar xpfz "$DISTLocalPath" --strip-components=1 -C "$PWD/${TEMURIN_VERSION}"

  export JAVA_HOME=$BOOTJDK_HOME
  export PATH=$JAVA_HOME/bin:$PATH

  set +e
  if [ "$REPRODUCIBLE_VERIFICATION" == true ]; then
    ./repro_compare.sh temurin "$sourceJDK" openjdk "reproJDK/$TEMURIN_VERSION" Darwin 2>&1 || rc=$?
  else
    ./repro_compare.sh temurin "$sourceJDK" temurin "reproJDK/$TEMURIN_VERSION" Darwin 2>&1 || rc=$?
  fi
  set -e

  if [ "$REPRODUCIBLE_VERIFICATION" == true ]; then
    EVIDENCE_LOG="$PWD/reproducible_evidence.log"
    if [ $rc -eq 0 ]; then
      echo "Successful 100% Reproducible Verification" >> "${EVIDENCE_LOG}"
      echo "Eclipse Temurin version: ${TEMURIN_VERSION}" >> "${EVIDENCE_LOG}"
      echo "                   arch: ${NATIVE_API_ARCH}" >> "${EVIDENCE_LOG}"
      echo "                     os: mac" >> "${EVIDENCE_LOG}"
      echo "                 sha256: ${JDK_TAR_HASH}" >> "${EVIDENCE_LOG}"
    else
      echo "Reproducible Verification not identical" >> "${EVIDENCE_LOG}"
      echo "Refer to guide for diagnosis and reporting: https://github.com/adoptium/temurin-build/wiki/Temurin-3rd-Party-Reproducible-Verification-Guides" >> "${EVIDENCE_LOG}"
    fi
    echo
    echo "Reproducible Verification evidence written to file: ${EVIDENCE_LOG}"
    echo "Contents:"
    echo
    cat  "${EVIDENCE_LOG}"
    echo
    echo "Provide contents of evidence file as the CDXA evidence: ${EVIDENCE_LOG}"
    echo "For providing a 3rd party Reproducible Verification CDXA, see: https://github.com/adoptium/temurin-cdxa/blob/main/CONTRIBUTING.md"
    echo
  fi 

  if [ $rc -eq 0 ]; then
    echo "Compare identical !"
  else
    echo "Differences found..., logged in: reprotest.diff"
  fi

  exit $rc 
}

# Begin Main Script Here
echo "---------------------------------------------"
echo "Begining Reproducible Mac Build From SBOM"
echo "---------------------------------------------"
echo "Checking Environment And Parameters"
echo "---------------------------------------------"
Check_Parameters
echo "---------------------------------------------"
Check_PreReqs
echo "---------------------------------------------"
Get_SBOM_Values
echo "---------------------------------------------"
Check_Architecture
echo "---------------------------------------------"
Check_Compiler_Versions
echo "---------------------------------------------"
Install_BootJDK
echo "---------------------------------------------"
if [ "$REPRODUCIBLE_VERIFICATION" == true ]; then
  setOpenJDKConfigureArgs
else
  Check_And_Install_Ant
  setTemurinBuildArgs
fi
echo "---------------------------------------------"
if [ "$REPRODUCIBLE_VERIFICATION" == true ]; then
  attestationBuildUsingOpenJDK
else
  buildUsingTemurinBuild
fi
echo "---------------------------------------------"
Compare_JDK

