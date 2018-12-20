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

  COMPRESS=gzip
  if which pigz; then
    COMPRESS=pigz;
  fi
  echo "Archiving the build OpenJDK image and compressing with $COMPRESS"

  EXT=$(getArchiveExtension)

  if [[ "${BUILD_CONFIG[OS_KERNEL_NAME]}" = *"cygwin"* ]]; then
      zip -r -q "${fileName}.zip" ./"${repoDir}"
  else
      tar -cf - "${repoDir}"/ | GZIP=-9 $COMPRESS -c > $fileName.tar.gz
  fi
}
