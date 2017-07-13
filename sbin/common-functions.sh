#!/bin/bash
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

# Common functions to be used in scripts

ALSA_LIB_VERSION=${ALSA_LIB_VERSION:-1.0.27.2}
FREETYPE_FONT_SHARED_OBJECT_FILENAME=libfreetype.so.6.5.0
FREETYPE_FONT_VERSION=${FREETYPE_FONT_VERSION:-2.4.0}

determineBuildProperties() {

    export OS_KERNEL_NAME=""
    OS_KERNEL_NAME=$(uname | awk '{print tolower($0)}')
    export OS_MACHINE_NAME=""
    OS_MACHINE_NAME=$(uname -m)

    JVM_VARIANT=${JVM_VARIANT:-server}

    BUILD_TYPE=normal
    DEFAULT_BUILD_FULL_NAME=${OS_KERNEL_NAME}-${OS_MACHINE_NAME}-${BUILD_TYPE}-${JVM_VARIANT}-release
    export BUILD_FULL_NAME=${BUILD_FULL_NAME:-"$DEFAULT_BUILD_FULL_NAME"}
}

# ALSA first for sound
checkingAndDownloadingAlsa()
{
  echo "Checking for ALSA"

  FOUND_ALSA=$(find "${WORKING_DIR}" -name "alsa-lib-${ALSA_LIB_VERSION}")

  if [[ ! -z "$FOUND_ALSA" ]] ; then
    echo "Skipping ALSA download"
  else
    wget -nc ftp://ftp.alsa-project.org/pub/lib/alsa-lib-"${ALSA_LIB_VERSION}".tar.bz2
    if [[ ${OS_KERNEL_NAME} == "aix" ]] ; then
      bzip2 -d alsa-lib-"${ALSA_LIB_VERSION}".tar.bz2
      tar xf alsa-lib-"${ALSA_LIB_VERSION}".tar
      rm alsa-lib-"${ALSA_LIB_VERSION}".tar
    else
      tar xf alsa-lib-"${ALSA_LIB_VERSION}".tar.bz2
      rm alsa-lib-"${ALSA_LIB_VERSION}".tar.bz2
    fi
  fi
}

checkingAndDownloadingFreeType()
{
  echo "Checking for freetype $WORKING_DIR $OPENJDK_REPO_NAME "

  FOUND_FREETYPE=$(find "$WORKING_DIR/$OPENJDK_REPO_NAME/installedfreetype/lib" -name "${FREETYPE_FONT_SHARED_OBJECT_FILENAME}")

  if [[ ! -z "$FOUND_FREETYPE" ]] ; then
    echo "Skipping FreeType download"
  else
    # Then FreeType for fonts: make it and use
    wget -nc http://ftp.acc.umu.se/mirror/gnu.org/savannah/freetype/freetype-"$FREETYPE_FONT_VERSION".tar.gz
    if [[ ${OS_KERNEL_NAME} == "aix" ]] ; then
      gunzip xf freetype-"$FREETYPE_FONT_VERSION".tar.gz
      tar xf freetype-"$FREETYPE_FONT_VERSION".tar
      rm freetype-"$FREETYPE_FONT_VERSION".tar
      MAKE=gmake
    else
      tar xf freetype-"$FREETYPE_FONT_VERSION".tar.gz
      rm freetype-"$FREETYPE_FONT_VERSION".tar.gz
      MAKE=make
    fi

    cd freetype-"$FREETYPE_FONT_VERSION" || exit

    # We get the files we need at $WORKING_DIR/installedfreetype
    # shellcheck disable=SC2046
    if [ $(bash ./configure --prefix="${WORKING_DIR}"/"${OPENJDK_REPO_NAME}"/installedfreetype "${FREETYPE_FONT_BUILD_TYPE_PARAM}" && $MAKE all && $MAKE install) -ne 0 ]; then
      # shellcheck disable=SC2154
      echo "${error}Failed to configure and build libfreetype, exiting"
      exit;
    else
      # shellcheck disable=SC2154
      echo "${good}Successfully configured OpenJDK with the FreeType library (libfreetype)!"
    fi
    # shellcheck disable=SC2154
    echo "${normal}"
  fi
}

checkingAndDownloadCaCerts()
{
  cd "$WORKING_DIR" || exit

  echo "Retrieving cacerts file"

  # Ensure it's the latest we pull in
  rm -rf "${WORKING_DIR}/cacerts_area"

  git clone https://github.com/AdoptOpenJDK/openjdk-build.git cacerts_area
  echo "cacerts should be here..."
  # shellcheck disable=SC2046
  if [ $(file "${WORKING_DIR}/cacerts_area/security/cacerts") -ne 0 ]; then
    echo "Failed to retrieve the cacerts file, exiting..."
    exit;
  else
    echo "${good}Successfully retrieved the cacerts file!"
  fi
}

downloadingRequiredDependencies()
{
  if [[ "$OSTYPE" == "cygwin" ]] || [[ "$OSTYPE" == "msys" ]] ; then
     echo "Windows or Windows-like environment detected, skipping downloading of dependencies...: Alsa, Freetype, and CaCerts."
  else
     echo "Downloading required dependencies...: Alsa, Freetype, and CaCerts."
     time (
        echo "Checking and download Alsa dependency"
        checkingAndDownloadingAlsa
     )

     if [[ -z "${FREETYPE}" ]] ; then
       if [[ -z "$FREETYPE_DIRECTORY" ]]; then
          time (
            echo "Checking and download FreeType Font dependency"
            checkingAndDownloadingFreeType
          )
       else
           echo ""
           echo "---> Skipping the process of checking and downloading the FreeType Font dependency, a pre-built version provided at $FREETYPE_DIRECTORY <---"
           echo ""
       fi
     else
        echo "Skipping Freetype"
     fi
     time (
        echo "Checking and download CaCerts dependency"
        checkingAndDownloadCaCerts
     )
  fi
}

getFirstTagFromOpenJDKGitRepo()
{
    justOneFromTheRevList=$(git rev-list --tags --max-count=1)
    tagNameFromRepo=$(git describe --tags "$justOneFromTheRevList")
    echo "$tagNameFromRepo"
}
