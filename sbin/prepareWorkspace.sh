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
set -eux

source "$SCRIPT_DIR/common-functions.sh"

# i.e. Where we are
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# TODO refactor this for SRP
checkoutAndCloneOpenJDKGitRepo()
{

  cd "${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[WORKING_DIR]}"

  # Check that we have a git repo of a valid openjdk version on our local file system
  if [ -d "${BUILD_CONFIG[OPENJDK_SOURCE_DIR]}/.git" ] && ( [ "${BUILD_CONFIG[OPENJDK_CORE_VERSION]}" == "jdk8" ] || [ "${BUILD_CONFIG[OPENJDK_CORE_VERSION]}" == "jdk9" ] || [ "${BUILD_CONFIG[OPENJDK_CORE_VERSION]}" == "jdk10" ]) ; then

    set +e
    git --git-dir "${BUILD_CONFIG[OPENJDK_SOURCE_DIR]}/.git" remote -v
    echo "${BUILD_CONFIG[OPENJDK_CORE_VERSION]}"
    git --git-dir "${BUILD_CONFIG[OPENJDK_SOURCE_DIR]}/.git" remote -v | grep --quiet "${BUILD_CONFIG[OPENJDK_CORE_VERSION]}"
    local isCorrectGitRepo=$?
    set -e


    # If the local copy of the git source repo is valid then we reset appropriately
    if [ "${isCorrectGitRepo}" == "0" ]; then
      cd "${BUILD_CONFIG[OPENJDK_SOURCE_DIR]}" || return
      echo "${info}Resetting the git openjdk source repository at $PWD in 10 seconds...${normal}"
      sleep 10
      echo "${git_colour}Pulling latest changes from git openjdk source repository${normal}"

      git fetch --all "${BUILD_CONFIG[SHALLOW_CLONE_OPTION]}"
      git reset --hard "origin/${BUILD_CONFIG[BRANCH]}"
      if [ ! -z "${BUILD_CONFIG[TAG]}" ]; then
        git checkout "${BUILD_CONFIG[TAG]}"
      fi
      git clean -fdx
    else
      echo "Incorrect Source Code for ${BUILD_CONFIG[OPENJDK_FOREST_NAME]}.  This is an error, please check what is in $PWD and manually remove, exiting..."
      exit 1
    fi
  elif [ ! -d "${BUILD_CONFIG[OPENJDK_SOURCE_DIR]}/.git" ] ; then
    # If it doesn't exist, clone it
    echo "${info}Didn't find any existing openjdk repository at $(pwd)/${BUILD_CONFIG[WORKING_DIR]} so cloning the source to openjdk${normal}"
    cloneOpenJDKGitRepo
  fi

  cd "${BUILD_CONFIG[WORKSPACE_DIR]}"
}

setGitCloneArguments() {
  cd "${BUILD_CONFIG[WORKSPACE_DIR]}"
  local git_remote_repo_address;
  if [[ "${BUILD_CONFIG[USE_SSH]}" == "true" ]] ; then
     git_remote_repo_address="git@github.com:${BUILD_CONFIG[REPOSITORY]}.git"
  else
     git_remote_repo_address="https://github.com/${BUILD_CONFIG[REPOSITORY]}.git"
  fi

  GIT_CLONE_ARGUMENTS=(${BUILD_CONFIG[SHALLOW_CLONE_OPTION]} '-b' "${BUILD_CONFIG[BRANCH]}" "$git_remote_repo_address" "${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[WORKING_DIR]}/${BUILD_CONFIG[OPENJDK_SOURCE_DIR]}")
}

cloneOpenJDKGitRepo()
{
  setGitCloneArguments

  echo "git clone ${GIT_CLONE_ARGUMENTS[*]}"
  git clone "${GIT_CLONE_ARGUMENTS[@]}"
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
  cd "${BUILD_CONFIG[WORKSPACE_DIR]}"
}
createWorkspace()
{
   mkdir -p "${BUILD_CONFIG[WORKSPACE_DIR]}" || exit
   mkdir -p "${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[WORKING_DIR]}" || exit
}


function moveTmpToWorkspaceLocation {
  if [ ! -z "${TMP_WORKSPACE}" ]; then
    rm -rf "${ORIGINAL_WORKSPACE}"
    mv "${TMP_WORKSPACE}/workspace" "${ORIGINAL_WORKSPACE}"
  fi
}

relocateToTmpIfNeeded()
{
   if [ "${BUILD_CONFIG[TMP_SPACE_BUILD]}" == "true" ]
   then
     local tmpdir=`mktemp -d 2>/dev/null || mktemp -d -t 'tmpdir'`
     export TMP_WORKSPACE="${tmpdir}"
     export ORIGINAL_WORKSPACE="${BUILD_CONFIG[WORKSPACE_DIR]}"

     if [ -d "${ORIGINAL_WORKSPACE}" ]
     then
        cp -r "${BUILD_CONFIG[WORKSPACE_DIR]}" "${TMP_WORKSPACE}/workspace"
     fi
     BUILD_CONFIG[WORKSPACE_DIR]="${TMP_WORKSPACE}/workspace"

     trap moveTmpToWorkspaceLocation EXIT
   fi
}

##################################################################

function configureWorkspace() {
    relocateToTmpIfNeeded
    createWorkspace
    checkoutAndCloneOpenJDKGitRepo
    downloadingRequiredDependencies
}

