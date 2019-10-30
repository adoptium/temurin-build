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

  # feature number e.g. 11
  BUILD_CONFIG[OPENJDK_FEATURE_NUMBER]=${featureNumber:-14}

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
  local suffix=$1
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
  if which pigz; then
    COMPRESS=pigz;
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
      tar -cf - "${repoDir}"/ | GZIP=-9 $COMPRESS -c > $fileName.tar.gz
  fi
}

function setBootJdk() {
  if [ -z "${BUILD_CONFIG[JDK_BOOT_DIR]}" ] ; then
    echo "Searching for JDK_BOOT_DIR"

    # shellcheck disable=SC2046,SC2230
    if [[ "${BUILD_CONFIG[OS_KERNEL_NAME]}" == "darwin" ]]; then
      BUILD_CONFIG[JDK_BOOT_DIR]="$(/usr/libexec/java_home)"
    else
      BUILD_CONFIG[JDK_BOOT_DIR]=$(dirname $(dirname $(readlink -f $(which javac))))
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
