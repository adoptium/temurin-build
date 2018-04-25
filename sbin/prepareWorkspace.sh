#!/usr/bin/env bash

#
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
#


# set -x # TODO remove once we've finished debugging
set -ex

# i.e. Where we are
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# TODO refactor this for SRP
checkoutAndCloneOpenJDKGitRepo()
{
  # Check that we have a git repo of a valid openjdk version on our local file system
  if [ -d "${BUILD_CONFIG[OPENJDK_SOURCE_DIR]}/.git" ] && ( [ "${BUILD_CONFIG[OPENJDK_CORE_VERSION]}" == "jdk8" ] || [ "${BUILD_CONFIG[OPENJDK_CORE_VERSION]}" == "jdk9" ] || [ "${BUILD_CONFIG[OPENJDK_CORE_VERSION]}" == "jdk10" ]) ; then
    local openjdk_git_repo_owner=$(git --git-dir "${BUILD_CONFIG[OPENJDK_SOURCE_DIR]}/.git" remote -v | grep "${BUILD_CONFIG[OPENJDK_CORE_VERSION]}")

    # If the local copy of the git source repo is valid then we reset appropriately
    if [ "${openjdk_git_repo_owner}" ]; then
      cd "${BUILD_CONFIG[OPENJDK_SOURCE_DIR]}" || return
      echo "${info}Resetting the git openjdk source repository at $PWD in 10 seconds...${normal}"
      sleep 10
      echo "${git}Pulling latest changes from git openjdk source repository${normal}"

      showShallowCloningMessage "fetch"
      git fetch --all ${BUILD_CONFIG[SHALLOW_CLONE_OPTION]}
      git reset --hard origin/${BUILD_CONFIG[BRANCH]}
      if [ ! -z "${BUILD_CONFIG[TAG]}" ]; then
        git checkout "${BUILD_CONFIG[TAG]}"
      fi
      git clean -fdx
    else
      echo "Incorrect Source Code for ${BUILD_CONFIG[OPENJDK_FOREST_NAME]}.  This is an error, please check what is in $PWD and manually remove, exiting..."
      exit 1
    fi
    pwd
    ls -alh
    cd "${BUILD_CONFIG[WORKING_DIR]}" || return
  elif [ ! -d "${BUILD_CONFIG[OPENJDK_SOURCE_DIR]}/.git" ] ; then
    # If it doesn't exist, clone it
    echo "${info}Didn't find any existing openjdk repository at $(pwd)/${BUILD_CONFIG[WORKING_DIR]} so cloning the source to openjdk${normal}"
    cloneOpenJDKGitRepo
  fi

}

cloneOpenJDKGitRepo()
{
  echo "${git}"
  local git_remote_repo_address;
  if [[ "${BUILD_CONFIG[USE_SSH]}" == "true" ]] ; then
     git_remote_repo_address="git@github.com:${BUILD_CONFIG[REPOSITORY]}.git"
  else
     git_remote_repo_address="https://github.com/${BUILD_CONFIG[REPOSITORY]}.git"
  fi

  showShallowCloningMessage "cloning"
  local git_clone_arguments=(${BUILD_CONFIG[SHALLOW_CLONE_OPTION]} '-b' "${BUILD_CONFIG[BRANCH]}" "$git_remote_repo_address" "${BUILD_CONFIG[WORKING_DIR]}/${BUILD_CONFIG[OPENJDK_SOURCE_DIR]}")

  echo "git clone ${git_clone_arguments[*]}"
  git clone "${git_clone_arguments[@]}"
  if [ ! -z "${BUILD_CONFIG[TAG]}" ]; then
    cd "${BUILD_CONFIG[WORKING_DIR]}/${BUILD_CONFIG[OPENJDK_SOURCE_DIR]}" || exit 1
    git checkout "${BUILD_CONFIG[TAG]}"
  fi

  # TODO extract this to its own function
  # Building OpenJDK with OpenJ9 must run get_source.sh to clone openj9 and openj9-omr repositories
  if [ "${BUILD_CONFIG[BUILD_VARIANT]}" == "openj9" ]; then
    cd "${BUILD_CONFIG[WORKING_DIR]}/${BUILD_CONFIG[OPENJDK_SOURCE_DIR]}" || return
    bash get_source.sh
  fi
}

getOpenJDKUpdateAndBuildVersion()
{
  if [ -d "${BUILD_CONFIG[WORKING_DIR]}/${BUILD_CONFIG[OPENJDK_SOURCE_DIR]}/.git" ]; then

    local openjdk_repo_tag;
    # It does exist and it's a repo other than the AdoptOpenJDK one
    cd "${BUILD_CONFIG[WORKING_DIR]}/${BUILD_CONFIG[OPENJDK_SOURCE_DIR]}" || return
    echo "${git}Pulling latest tags and getting the latest update version using git fetch -q --tags ${BUILD_CONFIG[SHALLOW_CLONE_OPTION]}"
    git fetch -q --tags "${BUILD_CONFIG[SHALLOW_CLONE_OPTION]}"
    openjdk_repo_tag=${TAG:-$(getFirstTagFromOpenJDKGitRepo)} # getFirstTagFromOpenJDKGitRepo resides in sbin/common-functions.sh
    if [[ "${openjdk_repo_tag}" == "" ]] ; then
     echo "${error}Unable to detect git tag, exiting..."
     exit 1
    else
     echo "OpenJDK repo tag is $openjdk_repo_tag"
    fi

     local openjdk_update_version=$(echo "${openjdk_repo_tag}" | cut -d'u' -f 2 | cut -d'-' -f 1)

     # TODO dont modify config in build script
    BUILD_CONFIG[OPENJDK_BUILD_NUMBER]=$(echo "${openjdk_repo_tag}" | cut -d'b' -f 2 | cut -d'-' -f 1)
    echo "Version: ${BUILD_CONFIG[openjdk_update_version]} ${BUILD_CONFIG[OPENJDK_BUILD_NUMBER]}"
    cd "${BUILD_CONFIG[WORKING_DIR]}" || return

  fi

  echo "${normal}"
}

showShallowCloningMessage()
{
    mode=$1
    if [[ "${BUILD_CONFIG[SHALLOW_CLONE_OPTION]}" == "" ]]; then
        echo "${info}Git repo ${mode} mode: deep (preserves commit history)${normal}"
    else
        echo "${info}Git repo ${mode} mode: shallow (DOES NOT contain commit history)${normal}"
    fi
}

testOpenJDKViaDocker()
{
  if [[ "${BUILD_CONFIG[JTREG]}" == "true" ]]; then
    mkdir -p "${BUILD_CONFIG[WORKING_DIR]}/target"
    ${BUILD_CONFIG[DOCKER]} run \
    -v "${BUILD_CONFIG[DOCKER_SOURCE_VOLUME_NAME]}:/openjdk/build" \
    -v "${BUILD_CONFIG[WORKING_DIR]}/target:${BUILD_CONFIG[TARGET_DIR_IN_THE_CONTAINER]}" \
    --entrypoint /openjdk/sbin/jtreg.sh "${BUILD_CONFIG[CONTAINER_NAME]}"
  fi
}


buildAndTestOpenJDKViaDocker()
{
  # This could be extracted overridden by the user if we support more architectures going forwards
  local container_architecture="x86_64/ubuntu"

  #TODO dont modify config in build
  BUILD_CONFIG[DOCKER_BUILD_PATH]="docker/${BUILD_CONFIG[OPENJDK_CORE_VERSION]}/$container_architecture"

  if [ -z "$(which docker)" ]; then
    echo "${error}Error, please install docker and ensure that it is in your path and running!${normal}"
    exit
  fi

  echo "${info}Using Docker to build the JDK${normal}"

  createPersistentDockerDataVolume

  # Copy our scripts for usage inside of the container
  rm -r "${BUILD_CONFIG[DOCKER_BUILD_PATH]}/sbin"
  cp -r "${SCRIPT_DIR}/sbin" "${BUILD_CONFIG[DOCKER_BUILD_PATH]}/sbin" 2>/dev/null

  # If keep is true then use the existing container (or build a new one if we can't find it)
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
     ${BUILD_CONFIG[DOCKER]} ps -a | awk '{ print $1,$2 }' | grep "${BUILD_CONFIG[CONTAINER_NAME]}" | awk '{print $1 }' | xargs -I {} docker rm -f {}

     # Build a new container
     buildDockerContainer --build-arg "OPENJDK_CORE_VERSION=${BUILD_CONFIG[OPENJDK_CORE_VERSION]}"
     echo "$normal"
  fi

  mkdir -p "${BUILD_CONFIG[WORKING_DIR]}/target"

  ${BUILD_CONFIG[DOCKER]} run -t \
      -e BUILD_VARIANT="${BUILD_CONFIG[BUILD_VARIANT]}" \
      -v "${BUILD_CONFIG[DOCKER_SOURCE_VOLUME_NAME]}:/openjdk/build" \
      -v "${BUILD_CONFIG[WORKING_DIR]}/target":/${BUILD_CONFIG[TARGET_DIR_IN_THE_CONTAINER]} \
      --entrypoint /openjdk/sbin/build.sh "${BUILD_CONFIG[CONTAINER_NAME]}"

 testOpenJDKViaDocker

  # If we didn't specify to keep the container then remove it
  if [[ -z ${BUILD_CONFIG[KEEP]} ]] ; then
    ${BUILD_CONFIG[DOCKER]} ps -a | awk '{ print $1,$2 }' | grep "${BUILD_CONFIG[CONTAINER_NAME]}" | awk '{print $1 }' | xargs -I {} docker rm {}
  fi
}

testOpenJDKInNativeEnvironmentIfExpected()
{
  if [[ "${BUILD_CONFIG[JTREG]}" == "true" ]];
  then
      "${SCRIPT_DIR}"/sbin/jtreg.sh "${BUILD_CONFIG[WORKING_DIR]}" "${BUILD_CONFIG[OPENJDK_SOURCE_DIR]}" "${BUILD_CONFIG[BUILD_FULL_NAME]}" "${BUILD_CONFIG[JTREG_TEST_SUBSETS]}"
  fi
}

buildAndTestOpenJDKInNativeEnvironment()
{
  local build_arguments=""
  declare -a build_argument_names=("--source" "--destination" "--repository" "--variant" "--update-version" "--build-number" "--repository-tag" "--configure-args")
  declare -a build_argument_values=("${BUILD_CONFIG[WORKING_DIR]}" "${BUILD_CONFIG[TARGET_DIR]}" "${BUILD_CONFIG[OPENJDK_SOURCE_DIR]}" "${BUILD_CONFIG[JVM_VARIANT]}" "${BUILD_CONFIG[OPENJDK_UPDATE_VERSION]}" "${BUILD_CONFIG[OPENJDK_BUILD_NUMBER]}" "${BUILD_CONFIG[TAG]}" "${BUILD_CONFIG[USER_SUPPLIED_CONFIGURE_ARGS]}")

  local build_args_array_index=0
  while [[ ${build_args_array_index} < ${#build_argument_names[@]} ]]; do
    if [[ ${build_argument_values[${build_args_array_index}]} != "" ]];
    then
        build_arguments="${BUILD_CONFIG[BUILD_ARGUMENTS]}${BUILD_ARGUMENT_NAMES[${BUILD_CONFIG[BUILD_ARGS_ARRAY_INDEX]}]} ${BUILD_ARGUMENT_VALUES[${BUILD_CONFIG[BUILD_ARGS_ARRAY_INDEX]}]} "
    fi
    ((build_args_array_index++))
  done

  echo "Calling ${SCRIPT_DIR}/sbin/build.sh ${build_arguments}"
  # shellcheck disable=SC2086
  "${SCRIPT_DIR}"/sbin/build.sh ${build_arguments}

  testOpenJDKInNativeEnvironmentIfExpected
}

# TODO Refactor all Docker related functionality to its own script
buildAndTestOpenJDK()
{
  if [ "${BUILD_CONFIG[USE_DOCKER]}" == "true" ] ; then
    buildAndTestOpenJDKViaDocker
  else
    buildAndTestOpenJDKInNativeEnvironment
  fi
}

##################################################################

function configureWorkspace() {

  time (
    checkoutAndCloneOpenJDKGitRepo
  )

  #time (
  #  getOpenJDKUpdateAndBuildVersion
  #)

  #buildAndTestOpenJDK
}

