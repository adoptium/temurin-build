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

################################################################################
#
# This script deals with the configuration to build (Adoptium) OpenJDK in a docker
# container.
# It's sourced by the makejdk-any-platform.sh script.
#
################################################################################

# The ${BUILD_CONFIG[CONTAINER_AS_ROOT]} can not be quoted. It is sudo (or similar) or nothing. "" is not an option.
# Similarly for ${cpuset} and ${userns}.
# shellcheck disable=SC2206
# shellcheck disable=SC2046
# shellcheck disable=SC2086

set -eu

# Create a data volume called ${BUILD_CONFIG[DOCKER_SOURCE_VOLUME_NAME]}.
# This gets mounted at /openjdk/build inside the container and is persistent
# between builds/tests unless -c is passed to this script, in which case it is
# recreated using the source in the current ./openjdk directory on the host
# machine (outside the container).
createPersistentDockerDataVolume()
{
  set +e
  ${BUILD_CONFIG[CONTAINER_AS_ROOT]} "${BUILD_CONFIG[CONTAINER_COMMAND]}" volume inspect "${BUILD_CONFIG[DOCKER_SOURCE_VOLUME_NAME]}" > /dev/null 2>&1
  local data_volume_exists=$?
  set -e

  if [[ "${BUILD_CONFIG[CLEAN_DOCKER_BUILD]}" == "true" || "$data_volume_exists" != "0" ]]; then

    # shellcheck disable=SC2154
    echo "Removing old volumes and containers"
    ${BUILD_CONFIG[CONTAINER_AS_ROOT]} "${BUILD_CONFIG[CONTAINER_COMMAND]}" rm -f $(${BUILD_CONFIG[CONTAINER_AS_ROOT]} "${BUILD_CONFIG[CONTAINER_COMMAND]}" ps -a --no-trunc -q -f volume="${BUILD_CONFIG[DOCKER_SOURCE_VOLUME_NAME]}") || true
    ${BUILD_CONFIG[CONTAINER_AS_ROOT]} "${BUILD_CONFIG[CONTAINER_COMMAND]}" volume rm -f "${BUILD_CONFIG[DOCKER_SOURCE_VOLUME_NAME]}" || true

    # shellcheck disable=SC2154
    echo "Creating tmp container"
    if echo "${BUILD_CONFIG[CONTAINER_COMMAND]}" | grep docker ; then
      ${BUILD_CONFIG[CONTAINER_AS_ROOT]} "${BUILD_CONFIG[CONTAINER_COMMAND]}" volume create --name "${BUILD_CONFIG[DOCKER_SOURCE_VOLUME_NAME]}"
    else
      ${BUILD_CONFIG[CONTAINER_AS_ROOT]} "${BUILD_CONFIG[CONTAINER_COMMAND]}" volume create "${BUILD_CONFIG[DOCKER_SOURCE_VOLUME_NAME]}"
    fi
  fi
}

# Build the docker container.
buildDockerContainer()
{
  echo "Building docker container"

  local dockerFile="${BUILD_CONFIG[DOCKER_FILE_PATH]}/Dockerfile"

  if [[ "${BUILD_CONFIG[BUILD_VARIANT]}" != "" && -f "${BUILD_CONFIG[DOCKER_FILE_PATH]}/Dockerfile-${BUILD_CONFIG[BUILD_VARIANT]}" ]]; then
    # TODO dont modify config in build
    BUILD_CONFIG[CONTAINER_NAME]="${BUILD_CONFIG[CONTAINER_NAME]}-${BUILD_CONFIG[BUILD_VARIANT]}"
    echo "Building DockerFile variant ${BUILD_CONFIG[BUILD_VARIANT]}"
    dockerFile="${BUILD_CONFIG[DOCKER_FILE_PATH]}/Dockerfile-${BUILD_CONFIG[BUILD_VARIANT]}"
  fi

  writeConfigToFile

  ${BUILD_CONFIG[CONTAINER_AS_ROOT]} "${BUILD_CONFIG[CONTAINER_COMMAND]}" build -t "${BUILD_CONFIG[CONTAINER_NAME]}" -f "${dockerFile}" . --build-arg "OPENJDK_CORE_VERSION=${BUILD_CONFIG[OPENJDK_CORE_VERSION]}" --build-arg "HostUID=${UID}"
}

# Execute the (Adoptium) OpenJDK build inside the Docker Container.
buildOpenJDKViaDocker()
{
  local hostDir
  hostDir="$(pwd)"
  local pipelinesdir="${hostDir}"/workspace/pipelines
  local workspacedir="${hostDir}"/workspace # we must ensure build user have correct permissions here
  local targetdir="${hostDir}"/workspace/target
  local targetbuilddir="${hostDir}"/workspace/build
  local configdir="${hostDir}"/workspace/config
  local localsourcesdir=

  if [ "${BUILD_CONFIG[OPENJDK_LOCAL_SOURCE_ARCHIVE]}" = "true" ] ; then
    # OPENJDK_LOCAL_SOURCE_ARCHIVE_ABSPATH can be file, you can not mount file.
    localsourcesdir=$(dirname "${BUILD_CONFIG[OPENJDK_LOCAL_SOURCE_ARCHIVE_ABSPATH]}")
  fi

  # TODO This could be extracted overridden by the user if we support more
  # architectures going forwards.
  local container_architecture
  container_architecture="$(uname -m)/${BUILD_CONFIG[CONTAINER_IMAGE]//:*/}"
  local build_variant_flag=""
  BUILD_CONFIG[DOCKER_FILE_PATH]="docker/${BUILD_CONFIG[OPENJDK_CORE_VERSION]}/$container_architecture"

  if [ "${BUILD_CONFIG[BUILD_VARIANT]}" == "openj9" ]; then
    build_variant_flag="--openj9"
  fi
  docker/dockerfile-generator.sh --version "${BUILD_CONFIG[OPENJDK_FEATURE_NUMBER]}" --path "${BUILD_CONFIG[DOCKER_FILE_PATH]}" "$build_variant_flag" --base-image "${BUILD_CONFIG[CONTAINER_IMAGE]}" \
     --dirs "${workspacedir} ${targetdir} ${targetbuilddir} ${configdir} ${localsourcesdir}" --command "${BUILD_CONFIG[CONTAINER_AS_ROOT]} ${BUILD_CONFIG[CONTAINER_COMMAND]}"

  # shellcheck disable=SC1090,SC1091
  source "${BUILD_CONFIG[DOCKER_FILE_PATH]}/dockerConfiguration.sh"

    local openjdk_core_version=${BUILD_CONFIG[OPENJDK_CORE_VERSION]}
    # test-image, debug-image and static-libs-image targets are optional - build scripts check whether the directories exist
    local openjdk_test_image_path="test"
    local openjdk_debug_image_path="debug-image"
    local jdk_directory=""
    local jre_directory=""
    # JDK 22+ uses static-libs-graal-image target, using static-libs-graal
    # folder.
    if [ "${BUILD_CONFIG[OPENJDK_FEATURE_NUMBER]}" -ge 22 ]; then
      local static_libs_dir="static-libs-graal"
    else
      local static_libs_dir="static-libs"
    fi

    if [ "$openjdk_core_version" == "${JDK8_CORE_VERSION}" ]; then
      case "${BUILD_CONFIG[OS_KERNEL_NAME]}" in
      "darwin")
        jdk_directory="j2sdk-bundle/jdk*.jdk"
        jre_directory="j2re-bundle/jre*.jre"
      ;;
      *)
        jdk_directory="j2sdk-image"
        jre_directory="j2re-image"
      ;;
      esac
    else
      case "${BUILD_CONFIG[OS_KERNEL_NAME]}" in
      "darwin")
        jdk_directory="jdk-bundle/jdk-*.jdk"
        jre_directory="jre-bundle/jre-*.jre"
      ;;
      *)
        jdk_directory="jdk"
        jre_directory="jre"
      ;;
      esac
    fi

    BUILD_CONFIG[JDK_PATH]=$jdk_directory
    BUILD_CONFIG[JRE_PATH]=$jre_directory
    BUILD_CONFIG[TEST_IMAGE_PATH]=$openjdk_test_image_path
    BUILD_CONFIG[DEBUG_IMAGE_PATH]=$openjdk_debug_image_path
    BUILD_CONFIG[STATIC_LIBS_IMAGE_PATH]=$static_libs_dir

  if [ -z "$(command -v "${BUILD_CONFIG[CONTAINER_COMMAND]}")" ]; then
    # shellcheck disable=SC2154
    echo "Error, please install docker and ensure that it is in your path and running!"
    exit
  fi

  echo "Using Docker to build the JDK"

  createPersistentDockerDataVolume

  # If keep is true then use the existing container (or build a new one if we
  # can't find it).
  if [[ "${BUILD_CONFIG[REUSE_CONTAINER]}" == "true" ]] ; then
     # shellcheck disable=SC2086
     # If we can't find the previous Docker container then build a new one.
     if [ "$(${BUILD_CONFIG[CONTAINER_AS_ROOT]} ${BUILD_CONFIG[CONTAINER_COMMAND]} ps -a | grep -c \"${BUILD_CONFIG[CONTAINER_NAME]}\")" == 0 ]; then
         echo "No docker container for reuse was found, so creating '${BUILD_CONFIG[CONTAINER_NAME]}'"
         buildDockerContainer
     fi
  else
     # shellcheck disable=SC2154
     echo "Since you specified --ignore-container, we are removing the existing container (if it exists) and building you a new one{$good}"
     # Find the previous Docker container and remove it (if it exists).
     ${BUILD_CONFIG[CONTAINER_AS_ROOT]} "${BUILD_CONFIG[CONTAINER_COMMAND]}" ps -a | awk '{ print $1,$2 }' | grep "${BUILD_CONFIG[CONTAINER_NAME]}" | awk '{print $1 }' | xargs -I {} ${BUILD_CONFIG[CONTAINER_AS_ROOT]} "${BUILD_CONFIG[CONTAINER_COMMAND]}" rm -f {}

     # Build a new container.
     buildDockerContainer
  fi

  # Show the user all of the config before we build.
  displayParams

  echo "Target binary directory on host machine: ${hostDir}/target"
  mkdir -p "${hostDir}/workspace/target"

  local cpuSet
  cpuSet="0-$((BUILD_CONFIG[NUM_PROCESSORS] - 1))"

  local gitSshAccess=()
  if [[ "${BUILD_CONFIG[USE_SSH]}" == "true" ]] ; then
     gitSshAccess=(-v "${HOME}/.ssh:/home/build/.ssh" -v "${SSH_AUTH_SOCK}:/build-ssh-agent" -e "SSH_AUTH_SOCK=/build-ssh-agent")
  fi

  local dockerMode=()
  local dockerEntrypoint=(--entrypoint /openjdk/sbin/build.sh "${BUILD_CONFIG[CONTAINER_NAME]}")
  if [[ "${BUILD_CONFIG[DEBUG_DOCKER]}" == "true" ]] ; then
     dockerMode=(-t -i)
     dockerEntrypoint=(--entrypoint "/bin/sh" "${BUILD_CONFIG[CONTAINER_NAME]}" -c "/bin/bash")
  fi

  # Command without gitSshAccess or dockerMode arrays.
  if [ -e "${hostDir}"/pipelines ] ; then
    local pipelinesdir="${hostDir}"/pipelines
  else
    mkdir -p "${pipelinesdir}"
  fi
  if echo "${BUILD_CONFIG[CONTAINER_COMMAND]}" | grep docker ; then
    local cpuset="--cpuset-cpus=${cpuSet}"
  else
    local cpuset=""
  fi
  if echo "${BUILD_CONFIG[CONTAINER_COMMAND]}" | grep podman ; then
    local userns="--userns=keep-id"
  else
    local userns=""
  fi
  local mountflag=Z #rw? Maybe this should be bound to root/rootless content of BUILD_CONFIG[CONTAINER_AS_ROOT] rather then just podman/docker in USE_DOCKER?
  mkdir -p "${hostDir}"/workspace/build  # Shouldn't be already there?
  local localsourcesdirmount=""
  if [ -n "${localsourcesdir}" ] ; then
    localsourcesdirmount="-v ${localsourcesdir}:${localsourcesdir}:${mountflag}" # read only? Is copied anyway.
  fi
  echo "If you get permissions denied on ${targetdir} or ${pipelinesdir} try to turn off selinux"
  local commandString=(
         ${cpuset}
         ${userns}
         ${localsourcesdirmount}
         -v "${BUILD_CONFIG[DOCKER_SOURCE_VOLUME_NAME]}:/openjdk/build"
         -v "${targetdir}":/"${BUILD_CONFIG[WORKSPACE_DIR]}"/"${BUILD_CONFIG[TARGET_DIR]}":"${mountflag}"
         -v "${pipelinesdir}":/openjdk/pipelines:"${mountflag}"
         -v "${configdir}":/"${BUILD_CONFIG[WORKSPACE_DIR]}"/"config":"${mountflag}"
         -e "DEBUG_DOCKER_FLAG=${BUILD_CONFIG[DEBUG_DOCKER]}"
         -e "BUILD_VARIANT=${BUILD_CONFIG[BUILD_VARIANT]}"
          "${dockerEntrypoint[@]:+${dockerEntrypoint[@]}}")

  # If build specifies --ssh, add array to the command string.
  if [[ "${BUILD_CONFIG[USE_SSH]}" == "true" ]] ; then
        commandString=("${gitSshAccess[@]:+${gitSshAccess[@]}}" "${commandString[@]}")
  fi

  # If build specifies --debug-docker, add array to the command string.
  if [[ "${BUILD_CONFIG[DEBUG_DOCKER]}" == "true" ]] ; then
        commandString=("${dockerMode[@]:+${dockerMode[@]}}" "${commandString[@]}")
        echo "DEBUG DOCKER MODE. To build jdk run /openjdk/sbin/build.sh"
  fi

  # Run the command string in Docker.
  ${BUILD_CONFIG[CONTAINER_AS_ROOT]} "${BUILD_CONFIG[CONTAINER_COMMAND]}" run --name "${BUILD_CONFIG[OPENJDK_CORE_VERSION]}-${BUILD_CONFIG[BUILD_VARIANT]}" "${commandString[@]}"

  # Tell user where the resulting binary can be found on the host system.
  echo "The finished image can be found in ${targetdir} on the host system"

  # If we didn't specify to keep the container then remove it.
  if [[ "${BUILD_CONFIG[KEEP_CONTAINER]}" == "false" ]] ; then
      echo "Removing container ${BUILD_CONFIG[OPENJDK_CORE_VERSION]}-${BUILD_CONFIG[BUILD_VARIANT]}"
      ${BUILD_CONFIG[CONTAINER_AS_ROOT]} "${BUILD_CONFIG[CONTAINER_COMMAND]}" ps -a | awk '{ print $1,$(NF) }' | grep "${BUILD_CONFIG[OPENJDK_CORE_VERSION]}-${BUILD_CONFIG[BUILD_VARIANT]}" | awk '{print $1 }' | xargs -I {} ${BUILD_CONFIG[CONTAINER_AS_ROOT]} ${BUILD_CONFIG[CONTAINER_COMMAND]} rm {}
  fi
}
