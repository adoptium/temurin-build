#!/bin/bash

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

################################################################################
#
# Common functions to be used in scripts
#
################################################################################

# TODO Remove the x once we're done
set -eux

# Set default versions for 3 libraries that OpenJDK relies on to build
# TODO Can we bump ALSA?
#ALSA_LIB_VERSION=${ALSA_LIB_VERSION:-1.0.27.2}
ALSA_LIB_VERSION=${ALSA_LIB_VERSION:-1.1.6}
FREETYPE_FONT_SHARED_OBJECT_FILENAME=libfreetype.so*
#FREEMARKER_LIB_VERSION=${FREEMARKER_LIB_VERSION:-2.3.8}
FREEMARKER_LIB_VERSION=${FREEMARKER_LIB_VERSION:-2.3.28}

# Parse the configuration args from the CL, please keep this in alpha order
parseConfigurationArguments() {

    while [[ $# -gt 0 ]] && [[ ."$1" = .-* ]] ; do
      opt="$1";
      shift;
      case "$opt" in
        "--" ) break 2;;

        "--build-number"  | "-b" )
        BUILD_CONFIG[OPENJDK_BUILD_NUMBER]="$1"; shift;;

        "--branch" | "-B" )
        BUILD_CONFIG[BRANCH]="$1"; shift;;

        "--configure-args"  | "-C" )
        BUILD_CONFIG[USER_SUPPLIED_CONFIGURE_ARGS]="$1"; shift;;

        "--clean-docker-build" | "-c" )
        BUILD_CONFIG[CLEAN_DOCKER_BUILD]=true;;

        "--destination" | "-d" )
        BUILD_CONFIG[TARGET_DIR]="$1"; shift;;

        "--docker" | "-D" )
        BUILD_CONFIG[USE_DOCKER]="true";;

        "--disable-shallow-git-clone" )
        BUILD_CONFIG[SHALLOW_CLONE_OPTION]=""; shift;;

        "--freetype-dir" | "-f" )
        BUILD_CONFIG[FREETYPE_DIRECTORY]="$1"; shift;;

        "--skip-freetype" | "-F" )
        BUILD_CONFIG[FREETYPE]=false;;

        "--ignore-container" | "-i" )
        BUILD_CONFIG[REUSE_CONTAINER]=false;;

        "--jdk-boot-dir" | "-J" )
        BUILD_CONFIG[JDK_BOOT_DIR]="$1";shift;;

        "--keep" | "-k" )
        BUILD_CONFIG[KEEP_CONTAINER]=true;;

        "--no-colour" | "-n" )
        BUILD_CONFIG[COLOUR]=false;;

        "--repository" | "-r" )
        BUILD_CONFIG[REPOSITORY]="$1"; shift;;

        "--repository-tag"  | "-R" )
        OPENJDK_REPO_TAG="$1"; shift;;

        "--source" | "-s" )
        BUILD_CONFIG[WORKING_DIR]="$1"; shift;;

        "--ssh" | "-S" )
        BUILD_CONFIG[USE_SSH]=true;;

        "--sign" )
        BUILD_CONFIG[SIGN]=true; BUILD_CONFIG[CERTIFICATE]="$1"; shift;;

        "--sudo" )
        BUILD_CONFIG[DOCKER]="sudo docker";;

        "--tag" | "-t" )
        BUILD_CONFIG[TAG]="$1"; BUILD_CONFIG[SHALLOW_CLONE_OPTION]=""; shift;;

        "--update-version"  | "-u" )
        BUILD_CONFIG[OPENJDK_UPDATE_VERSION]="$1"; shift;;

        "--build-variant"  | "-v" )
        BUILD_CONFIG[BUILD_VARIANT]="$1"; shift;;

        "--jvm-variant"  | "-V" )
        BUILD_CONFIG[JVM_VARIANT]="$1"; shift;;

        *) echo >&2 "${error}Invalid option: ${opt}${normal}"; exit 1;;
      esac
    done
}

# ALSA for sound
checkingAndDownloadingAlsa()
{
  cd "${BUILD_CONFIG[WORKSPACE_DIR]}/libs/" || exit

  echo "Checking for ALSA"

  FOUND_ALSA=$(find "${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[WORKING_DIR]}/" -name "installedalsa")

  if [[ ! -z "$FOUND_ALSA" ]] ; then
    echo "Skipping ALSA download"
  else
    # TODO Holy security problem Batman!
    wget -nc ftp://ftp.alsa-project.org/pub/lib/alsa-lib-"${ALSA_LIB_VERSION}".tar.bz2
    if [[ "${BUILD_CONFIG[OS_KERNEL_NAME]}" == "aix" ]] ; then
      bzip2 -d alsa-lib-"${ALSA_LIB_VERSION}".tar.bz2
      tar xf alsa-lib-"${ALSA_LIB_VERSION}".tar
      rm alsa-lib-"${ALSA_LIB_VERSION}".tar
    else
      tar xf alsa-lib-"${ALSA_LIB_VERSION}".tar.bz2
      rm alsa-lib-"${ALSA_LIB_VERSION}".tar.bz2
    fi

    cd ${BUILD_CONFIG[WORKSPACE_DIR]}/libs/alsa-lib*/

    if ! (./configure --prefix="${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[WORKING_DIR]}"/installedalsa && ${BUILD_CONFIG[MAKE_COMMAND_NAME]} && ${BUILD_CONFIG[MAKE_COMMAND_NAME]} install); then
      # shellcheck disable=SC2154
      echo "${error}Failed to configure and build alsa, exiting"
      exit;
    fi
  fi
}

# Freemarker for OpenJ9
checkingAndDownloadingFreemarker()
{
  echo "Checking for FREEMARKER"

  cd "${BUILD_CONFIG[WORKSPACE_DIR]}/libs/" || exit
  FOUND_FREEMARKER=$(find "." -type d -name "freemarker-${FREEMARKER_LIB_VERSION}")

  if [[ ! -z "$FOUND_FREEMARKER" ]] ; then
    echo "Skipping FREEMARKER download"
  else
    # wget --no-check-certificate "https://sourceforge.net/projects/freemarker/files/freemarker/${FREEMARKER_LIB_VERSION}/freemarker-${FREEMARKER_LIB_VERSION}.tar.gz/download" -O "freemarker-${FREEMARKER_LIB_VERSION}.tar.gz"
    # Temp fix as sourceforge is broken
    wget -nc --no-check-certificate http://www.mirrorservice.org/sites/ftp.apache.org/freemarker/engine/${FREEMARKER_LIB_VERSION}/binaries/apache-freemarker-${FREEMARKER_LIB_VERSION}-bin.tar.gz
    tar -xzf "apache-freemarker-${FREEMARKER_LIB_VERSION}-bin.tar.gz"
    rm "apache-freemarker-${FREEMARKER_LIB_VERSION}-bin.tar.gz"
  fi
}

checkingAndDownloadingFreeType()
{

  cd "${BUILD_CONFIG[WORKSPACE_DIR]}/libs/" || exit
  echo "Checking for freetype at ${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[WORKING_DIR]}"

  FOUND_FREETYPE=$(find "${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[WORKING_DIR]}/installedfreetype/lib" -name "${FREETYPE_FONT_SHARED_OBJECT_FILENAME}" || true)

  if [[ ! -z "$FOUND_FREETYPE" ]] ; then
    echo "Skipping FreeType download"
  else
    # Then FreeType for fonts: make it and use
    wget -nc --no-check-certificate https://ftp.acc.umu.se/mirror/gnu.org/savannah/freetype/freetype-"${BUILD_CONFIG[FREETYPE_FONT_VERSION]}".tar.gz
    if [[ "${BUILD_CONFIG[OS_KERNEL_NAME]}" == "aix" ]] ; then
      gunzip xf freetype-"${BUILD_CONFIG[FREETYPE_FONT_VERSION]}".tar.gz
      tar xf freetype-"${BUILD_CONFIG[FREETYPE_FONT_VERSION]}".tar
      rm freetype-"${BUILD_CONFIG[FREETYPE_FONT_VERSION]}".tar
    else
      tar xf freetype-"${BUILD_CONFIG[FREETYPE_FONT_VERSION]}".tar.gz
      rm freetype-"${BUILD_CONFIG[FREETYPE_FONT_VERSION]}".tar.gz
    fi

    cd freetype-"${BUILD_CONFIG[FREETYPE_FONT_VERSION]}" || exit

    # We get the files we need at $WORKING_DIR/installedfreetype
    # shellcheck disable=SC2046
    if ! (bash ./configure --prefix="${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[WORKING_DIR]}"/installedfreetype "${BUILD_CONFIG[FREETYPE_FONT_BUILD_TYPE_PARAM]}" && ${BUILD_CONFIG[MAKE_COMMAND_NAME]} all && ${BUILD_CONFIG[MAKE_COMMAND_NAME]} install); then
      # shellcheck disable=SC2154
      echo "${error}Failed to configure and build libfreetype, exiting"
      exit;
    else
      # shellcheck disable=SC2154
      echo "${good}Successfully configured OpenJDK with the FreeType library (libfreetype)!"

     if [[ ${OS_KERNEL_NAME} == "darwin" ]] ; then
        TARGET_DYNAMIC_LIB_DIR="${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[WORKING_DIR]}"/installedfreetype/lib/
        TARGET_DYNAMIC_LIB="${TARGET_DYNAMIC_LIB_DIR}"/libfreetype.6.dylib
        echo ""
        echo "Listing the contents of ${TARGET_DYNAMIC_LIB_DIR} to see if the dynamic library 'libfreetype.6.dylib' has been created..."
        ls "${TARGET_DYNAMIC_LIB_DIR}"

        echo ""
        echo "Releasing the runpath dependency of the dynamic library ${TARGET_DYNAMIC_LIB}"
        set -x
        install_name_tool -id @rpath/libfreetype.6.dylib "${TARGET_DYNAMIC_LIB}"
        set +x

        # shellcheck disable=SC2181
        if [[ $? == 0 ]]; then
          echo "Successfully released the runpath dependency of the dynamic library ${TARGET_DYNAMIC_LIB}"
        else
          echo "Failed to release the runpath dependency of the dynamic library ${TARGET_DYNAMIC_LIB}"
        fi
      fi
    fi
    # shellcheck disable=SC2154
    echo "${normal}"
  fi
}

checkingAndDownloadCaCerts()
{
  cd "${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[WORKING_DIR]}" || exit

  echo "Retrieving cacerts file"

  # Ensure it's the latest we pull in
  rm -rf "cacerts_area"
  mkdir "cacerts_area" || exit
  cd "cacerts_area" || exit

  git init
  git remote add origin -f https://github.com/AdoptOpenJDK/openjdk-build.git
  git config core.sparsecheckout true
  echo "security/*" >> .git/info/sparse-checkout
  git pull origin master

  echo "cacerts should be here..."

  # shellcheck disable=SC2046
  if ! [ -r "security/cacerts" ]; then
    echo "Failed to retrieve the cacerts file, exiting..."
    exit;
  else
    echo "${good}Successfully retrieved the cacerts file!"
  fi
  cd "${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[WORKING_DIR]}" || exit
}

downloadingRequiredDependencies()
{
  mkdir -p "${BUILD_CONFIG[WORKSPACE_DIR]}/libs/" || exit
  cd "${BUILD_CONFIG[WORKSPACE_DIR]}/libs/" || exit

  if [[ "$OSTYPE" == "cygwin" ]] || [[ "$OSTYPE" == "msys" ]] ; then
     echo "Windows or Windows-like environment detected, skipping downloading of dependencies...: Alsa, Freetype, and CaCerts."
  else
     echo "Downloading required dependencies...: Alsa, Freetype, Freemarker, and CaCerts."
        echo "Checking and download Alsa dependency"
        checkingAndDownloadingAlsa

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
     if [[ "${BUILD_CONFIG[BUILD_VARIANT]}" == "openj9" ]]; then
           echo "Checking and download Freemarker dependency"
           checkingAndDownloadingFreemarker
     fi
      echo "Checking and download CaCerts dependency"
      checkingAndDownloadCaCerts
  fi
}

getFirstTagFromOpenJDKGitRepo()
{
    git fetch --tags "${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[WORKING_DIR]}/${BUILD_CONFIG[OPENJDK_SOURCE_DIR]}"
    justOneFromTheRevList=$(git rev-list --tags --max-count=1)
    tagNameFromRepo=$(git describe --tags "$justOneFromTheRevList")
    echo "$tagNameFromRepo"
}
