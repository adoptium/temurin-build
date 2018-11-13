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

################################################################################
#
# This script prepares the workspace to build (Adopt) OpenJDK.
# See the configureWorkspace function for details
# It is sourced by build.sh
#
################################################################################

set -eu


SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# shellcheck source=sbin/common/constants.sh
source "$SCRIPT_DIR/common/constants.sh"

# Set default versions for 3 libraries that OpenJDK relies on to build
ALSA_LIB_VERSION=${ALSA_LIB_VERSION:-1.1.6}
FREETYPE_FONT_SHARED_OBJECT_FILENAME="libfreetype.so*"
FREEMARKER_LIB_VERSION=${FREEMARKER_LIB_VERSION:-2.3.28}

# Create a new clone or update the existing clone of the OpenJDK source repo
# TODO refactor this for SRP
checkoutAndCloneOpenJDKGitRepo()
{

  cd "${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[WORKING_DIR]}"

  # Check that we have a git repo of a valid openjdk version on our local file system
  if [ -d "${BUILD_CONFIG[OPENJDK_SOURCE_DIR]}/.git" ] && ( [ "${BUILD_CONFIG[OPENJDK_CORE_VERSION]}" == "${JDK8_CORE_VERSION}" ] || [ "${BUILD_CONFIG[OPENJDK_CORE_VERSION]}" == "${JDK9_CORE_VERSION}" ] || [ "${BUILD_CONFIG[OPENJDK_CORE_VERSION]}" == "${JDK10_CORE_VERSION}" ] || [ "${BUILD_CONFIG[OPENJDK_CORE_VERSION]}" == "${JDK11_CORE_VERSION}" ]) ; then
    set +e
    git --git-dir "${BUILD_CONFIG[OPENJDK_SOURCE_DIR]}/.git" remote -v
    echo "${BUILD_CONFIG[OPENJDK_CORE_VERSION]}"
    git --git-dir "${BUILD_CONFIG[OPENJDK_SOURCE_DIR]}/.git" remote -v | grep "origin.*fetch" | grep "${BUILD_CONFIG[OPENJDK_CORE_VERSION]}" | grep --quiet "${BUILD_CONFIG[REPOSITORY]}"
    local isCorrectGitRepo=$?
    set -e

    # If the local copy of the git source repo is valid then we reset appropriately
    if [ "${isCorrectGitRepo}" == "0" ]; then
      cd "${BUILD_CONFIG[OPENJDK_SOURCE_DIR]}" || return
      echo "Resetting the git openjdk source repository at $PWD in 10 seconds..."
      sleep 10
      echo "Pulling latest changes from git openjdk source repository"
    elif [ "${BUILD_CONFIG[CLEAN_GIT_REPO]}" == "true" ]; then
      echo "Removing current git repo as it is the wrong type"
      rm -rf "${BUILD_CONFIG[WORKSPACE_DIR]:?}/${BUILD_CONFIG[WORKING_DIR]}/${BUILD_CONFIG[OPENJDK_SOURCE_DIR]}"
      cloneOpenJDKGitRepo
    else
      echo "Incorrect Source Code for ${BUILD_CONFIG[OPENJDK_FOREST_NAME]}.  This is an error, please check what is in $PWD and manually remove, exiting..."
      echo "If this is inside a docker you can purge the existing source by passing --clean-docker-build"
      exit 1
    fi
  elif [ ! -d "${BUILD_CONFIG[OPENJDK_SOURCE_DIR]}/.git" ] ; then
    # If it doesn't exist, clone it
    echo "Didn't find any existing openjdk repository at $(pwd)/${BUILD_CONFIG[WORKING_DIR]} so cloning the source to openjdk"
    cloneOpenJDKGitRepo
  fi

  cd "${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[WORKING_DIR]}/${BUILD_CONFIG[OPENJDK_SOURCE_DIR]}"
  git remote set-branches --add origin "${BUILD_CONFIG[BRANCH]}"
  git fetch --all ${BUILD_CONFIG[SHALLOW_CLONE_OPTION]}
  git reset --hard "origin/${BUILD_CONFIG[BRANCH]}"

  # Openj9 does not release from git tags
  if [ ! -z "${BUILD_CONFIG[TAG]}" ] && [ "${BUILD_CONFIG[BUILD_VARIANT]}" != "openj9" ]; then
    git fetch origin "refs/tags/${BUILD_CONFIG[TAG]}:refs/tags/${BUILD_CONFIG[TAG]}"
    git checkout "${BUILD_CONFIG[TAG]}"
    git reset --hard
  fi
  git clean -ffdx

  updateOpenj9Sources

  cd "${BUILD_CONFIG[WORKSPACE_DIR]}"
}

# Set the git clone arguments
setGitCloneArguments() {
  cd "${BUILD_CONFIG[WORKSPACE_DIR]}"
  local git_remote_repo_address="${BUILD_CONFIG[REPOSITORY]}.git"

  GIT_CLONE_ARGUMENTS=(${BUILD_CONFIG[SHALLOW_CLONE_OPTION]} '-b' "${BUILD_CONFIG[BRANCH]}" "$git_remote_repo_address" "${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[WORKING_DIR]}/${BUILD_CONFIG[OPENJDK_SOURCE_DIR]}")
}

updateOpenj9Sources() {
  # Building OpenJDK with OpenJ9 must run get_source.sh to clone openj9 and openj9-omr repositories
  if [ "${BUILD_CONFIG[BUILD_VARIANT]}" == "openj9" ]; then
    cd "${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[WORKING_DIR]}/${BUILD_CONFIG[OPENJDK_SOURCE_DIR]}" || return
    if [ "${BUILD_CONFIG[OPENJDK_CORE_VERSION]}" == "${JDK8_CORE_VERSION}" ]; then
      bash get_source.sh --openssl-version=1.1.1
    else
      bash get_source.sh
    fi
    cd "${BUILD_CONFIG[WORKSPACE_DIR]}"
  fi
}
# Clone the git repo
cloneOpenJDKGitRepo()
{
  setGitCloneArguments

  echo "git clone ${GIT_CLONE_ARGUMENTS[*]}"
  git clone "${GIT_CLONE_ARGUMENTS[@]}"
}

# Create the workspace
createWorkspace()
{
   mkdir -p "${BUILD_CONFIG[WORKSPACE_DIR]}" || exit
   mkdir -p "${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[WORKING_DIR]}" || exit
}

# ALSA first for sound
checkingAndDownloadingAlsa()
{
  cd "${BUILD_CONFIG[WORKSPACE_DIR]}/libs/" || exit

  echo "Checking for ALSA"

  FOUND_ALSA=$(find "${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[WORKING_DIR]}/" -name "installedalsa")

  mkdir -p "${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[WORKING_DIR]}/installedalsa/" || exit

  if [[ ! -z "$FOUND_ALSA" ]]
  then
    echo "Skipping ALSA download"
  else
    # TODO Holy security problem Batman!
    #wget -nc ftp://ftp.alsa-project.org/pub/lib/alsa-lib-"${ALSA_LIB_VERSION}".tar.bz2
    wget -nc https://ftp.osuosl.org/pub/blfs/conglomeration/alsa-lib/alsa-lib-"${ALSA_LIB_VERSION}".tar.bz2
    if [[ "${BUILD_CONFIG[OS_KERNEL_NAME]}" == "aix" ]] ; then
      bzip2 -d alsa-lib-"${ALSA_LIB_VERSION}".tar.bz2
      tar -xf alsa-lib-"${ALSA_LIB_VERSION}".tar --strip-components=1 -C "${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[WORKING_DIR]}/installedalsa/"
      rm alsa-lib-"${ALSA_LIB_VERSION}".tar
    else
      tar -xf alsa-lib-"${ALSA_LIB_VERSION}".tar.bz2 --strip-components=1 -C "${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[WORKING_DIR]}/installedalsa/"
      rm alsa-lib-"${ALSA_LIB_VERSION}".tar.bz2
    fi
  fi
}

# Freemarker for OpenJ9
checkingAndDownloadingFreemarker()
{
  echo "Checking for FREEMARKER"

  cd "${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[WORKING_DIR]}/" || exit
  FOUND_FREEMARKER=$(find "." -type d -name "freemarker-${FREEMARKER_LIB_VERSION}")

  if [[ ! -z "$FOUND_FREEMARKER" ]] ; then
    echo "Skipping FREEMARKER download"
  else

    wget -nc --no-check-certificate "https://www.mirrorservice.org/sites/ftp.apache.org/freemarker/engine/${FREEMARKER_LIB_VERSION}/binaries/apache-freemarker-${FREEMARKER_LIB_VERSION}-bin.tar.gz"
    mkdir -p "${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[WORKING_DIR]}/freemarker-${FREEMARKER_LIB_VERSION}/" || exit
    tar -xzf "apache-freemarker-${FREEMARKER_LIB_VERSION}-bin.tar.gz" --strip-components=1 -C "${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[WORKING_DIR]}/freemarker-${FREEMARKER_LIB_VERSION}/"
    rm "apache-freemarker-${FREEMARKER_LIB_VERSION}-bin.tar.gz"
  fi
}

# Get Freetype
checkingAndDownloadingFreeType()
{
  cd "${BUILD_CONFIG[WORKSPACE_DIR]}/libs/" || exit
  echo "Checking for freetype at ${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[WORKING_DIR]}"

  FOUND_FREETYPE=$(find "${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[WORKING_DIR]}/installedfreetype/lib" -name "${FREETYPE_FONT_SHARED_OBJECT_FILENAME}" || true)

  if [[ ! -z "$FOUND_FREETYPE" ]] ; then
    echo "Skipping FreeType download"
  else
    # Temporary fudge as curl on my windows boxes is exiting with RC=127
    if [[ "$OSTYPE" == "cygwin" ]] || [[ "$OSTYPE" == "msys" ]] ; then
      wget -O "freetype.tar.gz" "https://download.savannah.gnu.org/releases/freetype/freetype-${BUILD_CONFIG[FREETYPE_FONT_VERSION]}.tar.gz"
    else
      curl -L -o "freetype.tar.gz" "https://download.savannah.gnu.org/releases/freetype/freetype-${BUILD_CONFIG[FREETYPE_FONT_VERSION]}.tar.gz"
    fi

    rm -rf "./freetype" || true
    mkdir -p "freetype" || true
    tar xpzf freetype.tar.gz --strip-components=1 -C "freetype"
    rm freetype.tar.gz

    if [[ "$OSTYPE" == "cygwin" ]] || [[ "$OSTYPE" == "msys" ]] ; then
       return;
    fi

    cd freetype || exit


    # We get the files we need at $WORKING_DIR/installedfreetype
    # shellcheck disable=SC2046
    if ! (bash ./configure --prefix="${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[WORKING_DIR]}"/installedfreetype "${BUILD_CONFIG[FREETYPE_FONT_BUILD_TYPE_PARAM]}" && ${BUILD_CONFIG[MAKE_COMMAND_NAME]} all && ${BUILD_CONFIG[MAKE_COMMAND_NAME]} install); then
      # shellcheck disable=SC2154
      echo "Failed to configure and build libfreetype, exiting"
      exit;
    else
      # shellcheck disable=SC2154
      echo "Successfully configured OpenJDK with the FreeType library (libfreetype)!"

     if [ -d "${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[WORKING_DIR]}/installedfreetype/include/freetype2/freetype" ]; then
        echo "Relocating freetype headers"
        # Later freetype nests its header files
        cp -r "${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[WORKING_DIR]}/installedfreetype/include/freetype2/ft2build.h" "${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[WORKING_DIR]}/installedfreetype/include/"
        cp -r "${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[WORKING_DIR]}/installedfreetype/include/freetype2/freetype/"* "${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[WORKING_DIR]}/installedfreetype/include/"
     fi

     if [[ ${BUILD_CONFIG[OS_KERNEL_NAME]} == "darwin" ]] ; then
        TARGET_DYNAMIC_LIB_DIR="${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[WORKING_DIR]}"/installedfreetype/lib/
        TARGET_DYNAMIC_LIB="${TARGET_DYNAMIC_LIB_DIR}"/libfreetype.6.dylib

        echo "Listing the contents of ${TARGET_DYNAMIC_LIB_DIR} to see if the dynamic library 'libfreetype.6.dylib' has been created..."
        ls "${TARGET_DYNAMIC_LIB_DIR}"

        echo "Releasing the runpath dependency of the dynamic library ${TARGET_DYNAMIC_LIB}"
        install_name_tool -id @rpath/libfreetype.6.dylib "${TARGET_DYNAMIC_LIB}"

        # shellcheck disable=SC2181
        if [[ $? == 0 ]]; then
          echo "Successfully released the runpath dependency of the dynamic library ${TARGET_DYNAMIC_LIB}"
        else
          echo "Failed to release the runpath dependency of the dynamic library ${TARGET_DYNAMIC_LIB}"
        fi
      fi
    fi
  fi
}

# Certificate Authority Certs (CA Certs)
checkingAndDownloadCaCerts()
{
  cd "${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[WORKING_DIR]}" || exit

  echo "Retrieving cacerts file"
  # Ensure it's the latest we pull in
  rm -rf "cacerts_area"
  mkdir "cacerts_area" || exit
  cd "cacerts_area" || exit

  if [ "${BUILD_CONFIG[USE_JEP319_CERTS]}" == "true" ];
  then
    if [ "${BUILD_CONFIG[OPENJDK_CORE_VERSION]}" == "${JDK8_CORE_VERSION}" ] || [ "${BUILD_CONFIG[OPENJDK_CORE_VERSION]}" == "${JDK9_CORE_VERSION}" ]
    then
      echo "Requested use of JEP319 certs"
      local caLink="https://github.com/AdoptOpenJDK/openjdk-jdk11u/blob/dev/src/java.base/share/lib/security/cacerts?raw=true";
      mkdir -p "security"
      # Temporary fudge as curl on my windows boxes is exiting with RC=127
      if [[ "$OSTYPE" == "cygwin" ]] || [[ "$OSTYPE" == "msys" ]] ; then
         wget -O "./security/cacerts" "${caLink}"
      else
         curl -L -o "./security/cacerts" "${caLink}"
      fi
    fi
  else
    git init
    git remote add origin -f https://github.com/AdoptOpenJDK/openjdk-build.git
    git config core.sparsecheckout true
    echo "security/*" >> .git/info/sparse-checkout
    git pull origin master
  fi

  cd "${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[WORKING_DIR]}" || exit
}

# Download all of the dependencies for OpenJDK (Alsa, FreeType, CACerts et al)
downloadingRequiredDependencies()
{
  mkdir -p "${BUILD_CONFIG[WORKSPACE_DIR]}/libs/" || exit
  cd "${BUILD_CONFIG[WORKSPACE_DIR]}/libs/" || exit

  if [[ "$OSTYPE" == "cygwin" ]] || [[ "$OSTYPE" == "msys" ]] ; then
     echo "Windows or Windows-like environment detected, skipping downloading of dependencies...: Alsa."
  else
     echo "Downloading required dependencies...: Alsa, Freetype, Freemarker, and CaCerts."
        echo "Checking and download Alsa dependency"
        checkingAndDownloadingAlsa

     if [[ "${BUILD_CONFIG[BUILD_VARIANT]}" == "openj9" ]]; then
           echo "Checking and download Freemarker dependency"
           checkingAndDownloadingFreemarker
     fi
  fi

  if [[ "${BUILD_CONFIG[FREETYPE]}" == "true" ]] ; then
   if [ -z "${BUILD_CONFIG[FREETYPE_DIRECTORY]}" ]; then
     echo "Checking and download FreeType Font dependency"
     checkingAndDownloadingFreeType
   else
     echo ""
     echo "---> Skipping the process of checking and downloading the FreeType Font dependency, a pre-built version provided at ${BUILD_CONFIG[FREETYPE_DIRECTORY]} <---"
     echo ""
   fi
  else
    echo "Skipping Freetype"
  fi

  echo "Checking and download CaCerts dependency"
  checkingAndDownloadCaCerts

}

function moveTmpToWorkspaceLocation {
  if [ ! -z "${TMP_WORKSPACE}" ]; then

    echo "Relocating workspace from ${TMP_WORKSPACE} to ${ORIGINAL_WORKSPACE}"

    rsync -a --delete  "${TMP_WORKSPACE}/workspace/" "${ORIGINAL_WORKSPACE}/"
    echo "===${ORIGINAL_WORKSPACE}/======"
    ls -alh "${ORIGINAL_WORKSPACE}/" || true

    echo "===${ORIGINAL_WORKSPACE}/build======"
    ls -alh "${ORIGINAL_WORKSPACE}/build" || true
  fi
}


relocateToTmpIfNeeded()
{
   if [ "${BUILD_CONFIG[TMP_SPACE_BUILD]}" == "true" ]
   then
     jobName=$(echo "${JOB_NAME:-build-dir}" | egrep -o "[^/]+$")
     local tmpdir="/tmp/openjdk-${jobName}"
     mkdir -p "$tmpdir"

     export TMP_WORKSPACE="${tmpdir}"
     export ORIGINAL_WORKSPACE="${BUILD_CONFIG[WORKSPACE_DIR]}"

     trap moveTmpToWorkspaceLocation EXIT SIGINT SIGTERM

     if [ -d "${ORIGINAL_WORKSPACE}" ]
     then
        echo "${BUILD_CONFIG[WORKSPACE_DIR]}"
        rsync -a --delete "${BUILD_CONFIG[WORKSPACE_DIR]}" "${TMP_WORKSPACE}/"

        echo "===${TMP_WORKSPACE}/======"
        ls -alh "${TMP_WORKSPACE}/" || true

        echo "===${TMP_WORKSPACE}/workspace======"
        ls -alh "${TMP_WORKSPACE}/workspace" || true

        echo "===${TMP_WORKSPACE}/workspace/build======"
        ls -alh "${TMP_WORKSPACE}/workspace/build" || true
     fi
     BUILD_CONFIG[WORKSPACE_DIR]="${TMP_WORKSPACE}/workspace"

   fi
}

##################################################################

function configureWorkspace() {
    createWorkspace
    downloadingRequiredDependencies
    relocateToTmpIfNeeded
    checkoutAndCloneOpenJDKGitRepo
}

