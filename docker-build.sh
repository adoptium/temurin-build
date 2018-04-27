#!/usr/bin/env bash



################################################################################
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
################################################################################



set -eux

# i.e. Where we are
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Load the common functions
# shellcheck source=sbin/common-functions.sh
#source "${SCRIPT_DIR}/sbin/common-functions.sh"

testOpenJDKViaDocker()
{
  if [[ "${BUILD_CONFIG[JTREG]}" == "true" ]]; then
    mkdir -p "${BUILD_CONFIG[WORKING_DIR]}/workspace/target"
    ${BUILD_CONFIG[DOCKER]} run \
    -v "${BUILD_CONFIG[DOCKER_SOURCE_VOLUME_NAME]}:/openjdk/build" \
    -v "${BUILD_CONFIG[WORKING_DIR]}/workspace/target:${BUILD_CONFIG[TARGET_DIR]}" \
    --entrypoint /openjdk/sbin/jtreg.sh "${BUILD_CONFIG[CONTAINER_NAME]}"
  fi
}

# Create a data volume called ${BUILD_CONFIG[DOCKER_SOURCE_VOLUME_NAME]},
# this gets mounted at /openjdk/build inside the container and is persistent
# between builds/tests unless -c is passed to this script, in which case it is
# recreated using the source in the current ./openjdk directory on the host
# machine (outside the container)
createPersistentDockerDataVolume()
{
  set +e
  ${BUILD_CONFIG[DOCKER]} volume inspect ${BUILD_CONFIG[DOCKER_SOURCE_VOLUME_NAME]} > /dev/null 2>&1
  local data_volume_exists=$?
  set -e

  if [[ "${BUILD_CONFIG[CLEAN_DOCKER_BUILD]}" == "true" || "$data_volume_exists" != "0" ]]; then

    echo "${info}Removing old volumes and containers${normal}"
    ${BUILD_CONFIG[DOCKER]} rm -f "$(${BUILD_CONFIG[DOCKER]} ps -a --no-trunc | grep ${BUILD_CONFIG[CONTAINER_NAME]} | cut -d' ' -f1)" || true
    ${BUILD_CONFIG[DOCKER]} volume rm "${BUILD_CONFIG[DOCKER_SOURCE_VOLUME_NAME]}" || true

    echo "${info}Creating tmp container${normal}"
    ${BUILD_CONFIG[DOCKER]} volume create --name "${BUILD_CONFIG[DOCKER_SOURCE_VOLUME_NAME]}"
  fi
}

# TODO I think we have a few bugs here - if you're passing a variant you
# override? the hotspot version
buildDockerContainer()
{
  echo "Building docker container"

  local dockerFile="${BUILD_CONFIG[DOCKER_BUILD_PATH]}/Dockerfile"

  if [[ "${BUILD_CONFIG[BUILD_VARIANT]}" != "" && -f "${BUILD_CONFIG[DOCKER_BUILD_PATH]}/Dockerfile-${BUILD_CONFIG[BUILD_VARIANT]}" ]]; then
    #TODO dont modify config in build
    BUILD_CONFIG[CONTAINER_NAME]="${BUILD_CONFIG[CONTAINER_NAME]}-${BUILD_CONFIG[BUILD_VARIANT]}"
    echo "Building DockerFile variant ${BUILD_CONFIG[BUILD_VARIANT]}"
    dockerFile="${BUILD_CONFIG[DOCKER_BUILD_PATH]}/Dockerfile-${BUILD_CONFIG[BUILD_VARIANT]}"
  fi

  ${BUILD_CONFIG[DOCKER]} build -t "${BUILD_CONFIG[CONTAINER_NAME]}" -f "${dockerFile}" . --build-arg "OPENJDK_CORE_VERSION=${BUILD_CONFIG[OPENJDK_CORE_VERSION]}"
}

buildAndTestOpenJDKViaDocker()
{
  # This could be extracted overridden by the user if we support more
  # architectures going forwards
  local container_architecture="x86_64/ubuntu"

  #TODO dont modify config in build
  BUILD_CONFIG[DOCKER_BUILD_PATH]="docker/${BUILD_CONFIG[OPENJDK_CORE_VERSION]}/$container_architecture"

  if [ -z "$(which docker)" ]; then
    echo "${error}Error, please install docker and ensure that it is in your path and running!${normal}"
    exit
  fi

  echo "${info}Using Docker to build the JDK${normal}"

  createPersistentDockerDataVolume

  # If keep is true then use the existing container (or build a new one if we
  # can't find it)
  if [[ "${BUILD_CONFIG[KEEP]}" == "true" ]] ; then
     # shellcheck disable=SC2086
     # If we can't find the previous Docker container then build a new one
     if [ "$(${BUILD_CONFIG[DOCKER]} ps -a | grep -c \"${BUILD_CONFIG[CONTAINER_NAME]}\")" == 0 ]; then
         echo "${info}No docker container found so creating '${BUILD_CONFIG[CONTAINER_NAME]}' ${normal}"
         buildDockerContainer
     fi
  else
     echo "${info}Since you did not specify -k or --keep, we are removing the existing container (if it exists) and building you a new one"
     echo "$good"
     # Find the previous Docker container and remove it (if it exists)
     ${BUILD_CONFIG[DOCKER]} ps -a | awk '{ print $1,$2 }' | grep "${BUILD_CONFIG[CONTAINER_NAME]}" | awk '{print $1 }' | xargs -I {} ${BUILD_CONFIG[DOCKER]} rm -f {}

     # Build a new container
     buildDockerContainer
     echo "$normal"
  fi

  local hostDir="$(pwd)";

  echo "Target binary directory on host machine: ${hostDir}/target"
  mkdir -p "${hostDir}/target"

  ${BUILD_CONFIG[DOCKER]} run -lst \
      --cpuset-cpus="0-3" \
       -v "${BUILD_CONFIG[DOCKER_SOURCE_VOLUME_NAME]}:/openjdk/build" \
       -v "${hostDir}/target":/${BUILD_CONFIG[TARGET_DIR]} \
      -e BUILD_VARIANT="${BUILD_CONFIG[BUILD_VARIANT]}" \
      --entrypoint /openjdk/sbin/build.sh "${BUILD_CONFIG[CONTAINER_NAME]}"

exit
 testOpenJDKViaDocker

  # If we didn't specify to keep the container then remove it
  if [[ -z ${BUILD_CONFIG[KEEP]} ]] ; then
    ${BUILD_CONFIG[DOCKER]} ps -a | awk '{ print $1,$2 }' | grep "${BUILD_CONFIG[CONTAINER_NAME]}" | awk '{print $1 }' | xargs -I {} ${BUILD_CONFIG[DOCKER]} rm {}
  fi
}