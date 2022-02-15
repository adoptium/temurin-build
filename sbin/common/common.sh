#!/bin/bash
# shellcheck disable=SC2155

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
    retryCount=1
    retryMax=5
    until [ "$retryCount" -ge "$retryMax" ]
    do
        # Use Adopt API to get the JDK Head number
        echo "This appears to be JDK Head. Querying the Adopt API to get the JDK HEAD Number (https://api.adoptium.net/v3/info/available_releases)..."
        local featureNumber=$(curl -q https://api.adoptium.net/v3/info/available_releases | awk '/tip_version/{print$2}')
        
        # Checks the api request was successful and the return value is a number
        if [ -z "${featureNumber}" ] || ! [[ "${featureNumber}" -gt 0 ]]
        then
            echo "RETRYWARNING: Query ${retryCount} failed. Retrying in 30 seconds (max retries = ${retryMax})..."
            retryCount=$((retryCount+1)) 
            sleep 30s
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
    fullPath=$(crossPlatformRealPath "$repoDir")
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
          time tar -cf - --owner=root --group=root "${repoDir}"/ | GZIP=-9 $COMPRESS -c > "$fileName.tar.gz"
      else
          time tar -cf - "${repoDir}"/ | GZIP=-9 $COMPRESS -c > "$fileName.tar.gz"
      fi
  fi
}

function setBootJdk() {
  # Stops setting the bootJDK on the host machine when running docker-build
  if [ "${BUILD_CONFIG[DOCKER]}" != "docker" ] || { [ "${BUILD_CONFIG[DOCKER]}" == "docker" ] && [ "${BUILD_CONFIG[DOCKER_FILE_PATH]}" != "" ]; } ; then
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
