#!/bin/bash


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


# Create a Tar ball
createOpenJDKArchive()
{
  local repoDir="$1"

  if [[ "${BUILD_CONFIG[OS_KERNEL_NAME]}" = *"cygwin"* ]]; then
      zip -r -q OpenJDK.zip ./"${repoDir}" 2>&1 > /dev/null
      EXT=".zip"
  elif [[ "${BUILD_CONFIG[OS_KERNEL_NAME]}" == "aix" ]]; then
      GZIP=-9 tar -cf - ./"${repoDir}"/ | gzip -c > OpenJDK.tar.gz 2>&1 > /dev/null
      EXT=".tar.gz"
  else
      GZIP=-9 tar -czf OpenJDK.tar.gz ./"${repoDir}" 2>&1 > /dev/null
      EXT=".tar.gz"
  fi

  echo "OpenJDK${EXT}"
}