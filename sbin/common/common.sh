#!/bin/bash
# ********************************************************************************
# Copyright (c) 2018 Contributors to the Eclipse Foundation
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

# shellcheck disable=SC2155
# shellcheck disable=SC2153
function setOpenJdkVersion() {
  # forest_name represents the JDK version with "u" suffix for an "update version"
  #
  # It no longer relates directly to the openjdk repository name, as the jdk(head) repository
  # now has version branches for jdk-23+
  #
  # Format: jdkNN[u]
  #
  local forest_name="${1}"

  echo "Setting version based on forest_name=${forest_name}"
  forest_name_check=0
  checkOpenJdkVersion "${forest_name}" || forest_name_check=$?
  if [ ${forest_name_check} -ne 0 ] ; then
    echo "The mandatory repo argument has a very strict format 'jdk[0-9]{1,3}[u]{0,1}' or just plain 'jdk' for tip. '$forest_name' does not match."
    echo "This can be worked around by using '--version jdkXYu'. If set (and matching) then the main argument can have any value."
    exit 1
  fi

  # Derive the openjdk_core_version from the forest name.
  local openjdk_core_version=${forest_name}
  if [[ ${forest_name} == *u ]]; then
    openjdk_core_version=${forest_name%?}
  fi

  BUILD_CONFIG[OPENJDK_CORE_VERSION]=$openjdk_core_version;
  BUILD_CONFIG[OPENJDK_FOREST_NAME]=$forest_name;

  # 'u' means it's an update repo, e.g. jdk8u
  if [[ ${BUILD_CONFIG[OPENJDK_FOREST_NAME]} == *u ]]; then
    BUILD_CONFIG[OPENJDK_CORE_VERSION]=${BUILD_CONFIG[OPENJDK_FOREST_NAME]%?}
  fi

  local featureNumber=$(echo "${BUILD_CONFIG[OPENJDK_CORE_VERSION]}" | tr -d "[:alpha:]")

  if [ -z "${featureNumber}" ]
  then
    retryCount=1
    retryMax=5
    until [ "$retryCount" -ge "$retryMax" ]
    do
        # Use Adoptium API to get the JDK Head number
        echo "This appears to be JDK Head. Querying the Adoptium API to get the JDK HEAD Number (https://api.adoptium.net/v3/info/available_releases)..."
        local featureNumber=$(curl -q https://api.adoptium.net/v3/info/available_releases | awk '/tip_version/{print$2}')
        
        # Checks the api request was successful and the return value is a number
        if [ -z "${featureNumber}" ] || ! [[ "${featureNumber}" -gt 0 ]]
        then
            echo "RETRYWARNING: Query ${retryCount} failed. Retrying in 30 seconds (max retries = ${retryMax})..."
            retryCount=$((retryCount+1)) 
            sleep 30
        else
            echo "featureNumber FOUND: ${featureNumber}" && break
        fi
    done

    # Fail build if we still can't find the head number
    if [ -z "${featureNumber}" ] || ! [[ "${featureNumber}" -gt 0 ]]
    then
        echo "Failed ${retryCount} times to query or parse the adopt api. Dumping headers via curl -v https://api.adoptium.net/v3/info/available_releases and exiting..."
        curl -v https://api.adoptium.net/v3/info/available_releases
        echo curl returned RC $? in common.sh
        exit 1
    fi
  fi

  # feature number e.g. 11
  BUILD_CONFIG[OPENJDK_FEATURE_NUMBER]=${featureNumber}

  # Set default branch based on JDK forest and feature number
  setBranch
}

function checkOpenJdkVersion() {
  local forest_name="${1}"
  # The argument passed here has a very strict format of jdk8, jdk8u..., jdk
  # the build may fail later if this is not honoured.
  # If your repository has a different name, you can use --version or build from a dir/snapshot
  local forest_name_check1=0
  local forest_name_check2=0
  # This two returns condition is there to make grep on solaris happy. -e, -q and  \( and \| do not work on that platform
  echo "$forest_name" | grep "^jdk[0-9]\\{1,3\\}[u]\\{0,1\\}$" >/dev/null || forest_name_check1=$?
  echo "$forest_name" | grep "^jdk$" >/dev/null || forest_name_check2=$?
  if [ ${forest_name_check1} -ne 0 ] && [ ${forest_name_check2} -ne 0 ]; then
    return 1
  else
    return 0
  fi
}

# Set the default BUILD_CONFIG[BRANCH] for the jdk version being built
# For "hotspot" and "Temurin" builds of non-"u" jdk-23+ the branch is dev_<version>
function setBranch() {

  # Which repo branch to build, e.g. dev by default for temurin, "openj9" for openj9
  local branch="master"
  local adoptium_mirror_branch="dev"

  # non-u (and non-tip) jdk-23+ hotspot and adoptium version source is within a "version" branch in the "jdk" repository
  if [[ ${BUILD_CONFIG[OPENJDK_FOREST_NAME]} != *u ]] && [[ ${BUILD_CONFIG[OPENJDK_FOREST_NAME]} != "jdk" ]] && [[ "${BUILD_CONFIG[OPENJDK_FEATURE_NUMBER]}" -ge 23 ]]; then
    branch="jdk${BUILD_CONFIG[OPENJDK_FEATURE_NUMBER]}"
    adoptium_mirror_branch="dev_jdk${BUILD_CONFIG[OPENJDK_FEATURE_NUMBER]}"
  fi

  if [ "${BUILD_CONFIG[BUILD_VARIANT]}" == "${BUILD_VARIANT_TEMURIN}" ]; then
    branch="${adoptium_mirror_branch}"
  elif [ "${BUILD_CONFIG[BUILD_VARIANT]}" == "${BUILD_VARIANT_OPENJ9}" ]; then
    branch="openj9";
  elif [ "${BUILD_CONFIG[BUILD_VARIANT]}" == "${BUILD_VARIANT_DRAGONWELL}" ]; then
    branch="master";
  elif [ "${BUILD_CONFIG[BUILD_VARIANT]}" == "${BUILD_VARIANT_FAST_STARTUP}" ]; then
    branch="master";
  elif [ "${BUILD_CONFIG[BUILD_VARIANT]}" == "${BUILD_VARIANT_CORRETTO}" ]; then
    branch="develop";
  elif [ "${BUILD_CONFIG[BUILD_VARIANT]}" == "${BUILD_VARIANT_BISHENG}" ]; then
    if [ "${BUILD_CONFIG[OS_ARCHITECTURE]}" == "riscv64" ] ; then
      branch="risc-v"
    else
      branch="master"
    fi
  fi

  BUILD_CONFIG[BRANCH]=${BUILD_CONFIG[BRANCH]:-$branch}

  echo "Default branch set to BUILD_CONFIG[BRANCH]=${BUILD_CONFIG[BRANCH]}"
}

function crossPlatformRealPath() {
  local target=$1

  local currentDir="$PWD"

  if [[ -d $target ]]; then
    cd "$target"
    local name=""
  elif [[ -f $target ]]; then
    cd "$(dirname "$target")"
    local name=$(basename "$target")
  fi

  local fullPath="$PWD/${name:+${name}}"
  cd "$currentDir"
  echo "$fullPath"
}

function setDockerVolumeSuffix() {
  local suffix="$1-${BUILD_CONFIG[BUILD_VARIANT]}"
  if [[ "${BUILD_CONFIG[DOCKER_SOURCE_VOLUME_NAME]}" != *"-${suffix}" ]]; then
    BUILD_CONFIG[DOCKER_SOURCE_VOLUME_NAME]="${BUILD_CONFIG[DOCKER_SOURCE_VOLUME_NAME]}-${suffix}"
  fi
}

# Joins multiple parts to a valid file path for the current OS
function joinPathOS() {
  local path=$(echo "/${*}" | tr ' ' / | tr -s /)
  if [[ "$OSTYPE" == "cygwin" ]] || [[ "$OSTYPE" == "msys" ]]; then
      path=$(cygpath -w "${path}")
  fi
  echo "${path}"
}

# Joins multiple parts to a valid file path using slashes
function joinPath() {
  local path=$(echo "/${*}" | tr ' ' / | tr -s /)
  echo "${path}"
}

# Create a Tar ball
getArchiveExtension()
{
  if [[ "${BUILD_CONFIG[OS_KERNEL_NAME]}" = *"cygwin"* ]]; then
      EXT=".zip"
  else
      EXT=".tar.gz"
  fi

  echo "${EXT}"
}

# Create a Tar ball
createOpenJDKArchive()
{
  local repoDir="$1"
  local fileName="$2"


  if [ -z "$repoDir" ]; then
     echo "Empty dir passed to be archived"
     exit 1
  fi

  if [[ "$repoDir" = "/"* ]]; then
     echo "Absolute directory passed to archive"
     exit 1
  fi

  COMPRESS=gzip
  if which pigz > /dev/null 2>&1; then
    COMPRESS=pigz
  fi

  echo "Archiving and compressing with $COMPRESS"

  EXT=$(getArchiveExtension)

  if [[ ! -z "${BUILD_CONFIG[HSWAP_AGENT_DOWNLOAD_URL]}" ]]; then
      local hotswapAgentDir=${repoDir}
      case "${BUILD_CONFIG[OS_KERNEL_NAME]}" in
          "darwin") hotswapAgentDir="${repoDir}/Contents/Home" ;;
      esac
      echo "Downloading HotswapAgent from ${BUILD_CONFIG[HSWAP_AGENT_DOWNLOAD_URL]}"
      mkdir -p "${hotswapAgentDir}/lib/hotswap"
      wget -q -O "${hotswapAgentDir}/lib/hotswap/hotswap-agent.jar" "${BUILD_CONFIG[HSWAP_AGENT_DOWNLOAD_URL]}"
      if [[ ! -z "${BUILD_CONFIG[HSWAP_AGENT_CORE_DOWNLOAD_URL]}" ]]; then
          wget -q -O "${hotswapAgentDir}/lib/hotswap/hotswap-agent-core.jar" "${BUILD_CONFIG[HSWAP_AGENT_CORE_DOWNLOAD_URL]}"
      fi
  fi

  local fullPath
  if [[ "${BUILD_CONFIG[OS_KERNEL_NAME]}" != "darwin" ]]; then
    fullPath=$(crossPlatformRealPath "$repoDir")
    if [[ "$fullPath" != "${BUILD_CONFIG[WORKSPACE_DIR]}"* ]] && { [[ -z "${BUILD_CONFIG[USER_OPENJDK_BUILD_ROOT_DIRECTORY]}" ]] || [[ "$fullPath" != "${BUILD_CONFIG[USER_OPENJDK_BUILD_ROOT_DIRECTORY]}"* ]]; }; then
      echo "Requested to archive a dir outside of workspace"
      exit 1
    fi
  fi


  if [[ "${BUILD_CONFIG[OS_KERNEL_NAME]}" = *"cygwin"* ]]; then
      zip -r -q "${fileName}.zip" ./"${repoDir}"
  else
      # Create archive with UID/GID 0 for root if using GNU tar
      if tar --version 2>&1 | grep GNU > /dev/null; then
          time tar -cf - --owner=root --group=root "${repoDir}"/ | GZIP=-9 $COMPRESS -c > "$fileName.tar.gz"
      else
          time tar -cf - "${repoDir}"/ | GZIP=-9 $COMPRESS -c > "$fileName.tar.gz"
      fi
  fi
}

function setBootJdk() {
  # Stops setting the bootJDK on the host machine when running docker-build
  if [ "${BUILD_CONFIG[CONTAINER_AS_ROOT]}" == "false" ] || { [ "${BUILD_CONFIG[CONTAINER_AS_ROOT]}" != "false" ] && [ "${BUILD_CONFIG[DOCKER_FILE_PATH]}" != "" ]; } ; then
    if [ -z "${BUILD_CONFIG[JDK_BOOT_DIR]}" ] ; then
      echo "Searching for JDK_BOOT_DIR"

      # shellcheck disable=SC2046,SC2230
      if [[ "${BUILD_CONFIG[OS_KERNEL_NAME]}" == "darwin" ]]; then
        set +e
        BUILD_CONFIG[JDK_BOOT_DIR]="$(/usr/libexec/java_home)"
        local returnCode=$?
        set -e

        if [[ ${returnCode} -ne 0 ]]; then
          BUILD_CONFIG[JDK_BOOT_DIR]="$(dirname "$(dirname "$(greadlink -f "$(which javac)")")")"
        fi
      else
        BUILD_CONFIG[JDK_BOOT_DIR]="$(dirname "$(dirname "$(readlink -f "$(which javac)")")")"
      fi

      echo "Guessing JDK_BOOT_DIR: ${BUILD_CONFIG[JDK_BOOT_DIR]}"
      echo "If this is incorrect explicitly configure JDK_BOOT_DIR using --jdk-boot-dir"

      # Calculate version number of boot jdk. Output on Windows contains \r, hence gsub("\r", "", $3).
      export BOOT_JDK_VERSION_NUMBER=$("${BUILD_CONFIG[JDK_BOOT_DIR]}/bin/java" -XshowSettings:properties -version 2>&1 | awk '/java.specification.version/{gsub(/1\./,"",$3);gsub("\r", "", $3);print $3}')
      if [ -z "$BOOT_JDK_VERSION_NUMBER" ]; then
        echo "[ERROR] The BOOT_JDK_VERSION_NUMBER was not found. Likelihood is that the boot jdk settings properties don't contain a java.specification.version..."
        "${BUILD_CONFIG[JDK_BOOT_DIR]}/bin/java" -XshowSettings:properties -version 2>&1
        exit 2
      fi

      # If bootjdk isn't the same version and isn't a n-1 version, crash out with informational message
      export REQUIRED_BOOT_JDK=$(( BUILD_CONFIG[OPENJDK_FEATURE_NUMBER] - 1))

      if [ "${BUILD_CONFIG[OPENJDK_FEATURE_NUMBER]}" -ne "$BOOT_JDK_VERSION_NUMBER" ] && [ "$REQUIRED_BOOT_JDK" -ne "$BOOT_JDK_VERSION_NUMBER" ]; then
        echo "[ERROR] A JDK${BOOT_JDK_VERSION_NUMBER} boot jdk cannot build a JDK${BUILD_CONFIG[OPENJDK_FEATURE_NUMBER]} binary"
        echo "[ERROR] Please download a JDK${REQUIRED_BOOT_JDK} (preferable) OR JDK${BUILD_CONFIG[OPENJDK_FEATURE_NUMBER]} binary and pass it into this script using -J, --jdk-boot-dir"
        exit 2
      fi

    else
      echo "Overriding JDK_BOOT_DIR, set to ${BUILD_CONFIG[JDK_BOOT_DIR]}"
    fi

    echo "Boot dir set to ${BUILD_CONFIG[JDK_BOOT_DIR]}"
  else
    echo "Skipping setting boot JDK on docker host machine"
  fi
}

# A function that returns true if the variant is based on HotSpot and should
# be treated as such by the build scripts
# This is possibly only used in configureBuild.sh for arm32
# But should perhaps just be "if not openj9" to include Dragonwell/Bisheng
function isHotSpot() {
  [ "${BUILD_CONFIG[BUILD_VARIANT]}" == "${BUILD_VARIANT_HOTSPOT}" ] ||
  [ "${BUILD_CONFIG[BUILD_VARIANT]}" == "${BUILD_VARIANT_TEMURIN}" ] ||
  [ "${BUILD_CONFIG[BUILD_VARIANT]}" == "${BUILD_VARIANT_SAP}" ] ||
  [ "${BUILD_CONFIG[BUILD_VARIANT]}" == "${BUILD_VARIANT_CORRETTO}" ]
}

# A function that determines if the local date implementation is a GNU or BusyBox
# as opposed to BSD, so that the correct date syntax can be used
function isGnuCompatDate() {
  local isGnuCompatDate=$(date --version 2>&1 | grep "GNU\|BusyBox" || true)
  [ "x${isGnuCompatDate}" != "x" ]
}

# Returns true if the OPENJDK_FEATURE_NUMBER is an LTS version (every 2 years)
# from jdk-21 onwards
function isFromJdk21LTS() {
  [[ "${BUILD_CONFIG[OPENJDK_FEATURE_NUMBER]}" -ge 21 ]] && [[ $(((BUILD_CONFIG[OPENJDK_FEATURE_NUMBER]-21) % 4)) == 0 ]]
}

# Waits N seconds (10 by default), printing a countdown every second.
function verboseSleep() {
  if [[ -z "${1}" ]] ; then
    local i=10
  else
    local i="${1}"
  fi
  while [ "$i" -gt 0 ] ; do echo -n " $i " && sleep 1 && i=$((i-1)) ; done && echo " $i"
}

