#!/bin/bash

################################################################################
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

# shellcheck disable=SC2153
function setOpenJdkVersion() {
  local forest_name=$1

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
    # Use Adopt API to get the JDK Head number
    echo "This appears to be JDK Head. Querying the Adopt API to get the JDK HEAD Number (https://api.adoptopenjdk.net/v3/info/available_releases)..."
    local featureNumber=$(curl https://api.adoptopenjdk.net/v3/info/available_releases | awk '/tip_version/{print$2}')
    
    # Checks the api request was successfull and the return value is a number
    if [ -z "${featureNumber}" ] || ! [[ "${featureNumber}" -gt 0 ]]
    then
        echo "Failed to query or parse the adopt api. Dumping headers via curl -v https://api.adoptopenjdk.net/v3/info/available_releases..."
        curl -v https://api.adoptopenjdk.net/v3/info/available_releases
        exit 1
    fi
    echo "featureNumber is $featureNumber"
  fi

  # feature number e.g. 11
  BUILD_CONFIG[OPENJDK_FEATURE_NUMBER]=${featureNumber}

}

function crossPlatformRealPath() {
  local target=$1

  local currentDir="$PWD"

  if [[ -d $target ]]; then
    cd "$target"
    local name=""
  elif [[ -f $target ]]; then
    cd "$(dirname $target)"
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
  echo "Archiving the build OpenJDK image and compressing with $COMPRESS"

  EXT=$(getArchiveExtension)

  local fullPath
  if [[ "${BUILD_CONFIG[OS_KERNEL_NAME]}" != "darwin" ]]; then
    fullPath=$(crossPlatformRealPath $repoDir)
    if [[ "$fullPath" != "${BUILD_CONFIG[WORKSPACE_DIR]}"* ]]; then
      echo "Requested to archive a dir outside of workspace"
      exit 1
    fi
  fi


  if [[ "${BUILD_CONFIG[OS_KERNEL_NAME]}" = *"cygwin"* ]]; then
      zip -r -q "${fileName}.zip" ./"${repoDir}"
  else
      # Create archive with UID/GID 0 for root if using GNU tar
      if tar --version 2>&1 | grep GNU > /dev/null; then
          tar -cf - --owner=root --group=root "${repoDir}"/ | GZIP=-9 $COMPRESS -c > $fileName.tar.gz
      else
          tar -cf - "${repoDir}"/ | GZIP=-9 $COMPRESS -c > $fileName.tar.gz
      fi
  fi
}

function setBootJdk() {
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
    echo "If this is incorrect explicitly configure JDK_BOOT_DIR"
  else
    echo "Overriding JDK_BOOT_DIR, set to ${BUILD_CONFIG[JDK_BOOT_DIR]}"
  fi

  echo "Boot dir set to ${BUILD_CONFIG[JDK_BOOT_DIR]}"
}

# A function that returns true if the variant is based on HotSpot and should
# be treated as such by the build scripts
function isHotSpot() {
  [ "${BUILD_CONFIG[BUILD_VARIANT]}" == "${BUILD_VARIANT_HOTSPOT}" ] ||
  [ "${BUILD_CONFIG[BUILD_VARIANT]}" == "${BUILD_VARIANT_HOTSPOT_JFR}" ] ||
  [ "${BUILD_CONFIG[BUILD_VARIANT]}" == "${BUILD_VARIANT_SAP}" ] ||
  [ "${BUILD_CONFIG[BUILD_VARIANT]}" == "${BUILD_VARIANT_CORRETTO}" ]
}
