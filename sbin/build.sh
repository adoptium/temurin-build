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
# Build OpenJDK - can be called directly but is typically called by
# docker-build.sh or native-build.sh.
#
# See bottom of the script for the call order and each function for further
# details.
#
# Calls 'configure' then 'make' in order to build OpenJDK
#
################################################################################

set -eu

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# shellcheck source=sbin/prepareWorkspace.sh
source "$SCRIPT_DIR/prepareWorkspace.sh"

# shellcheck source=sbin/common/config_init.sh
source "$SCRIPT_DIR/common/config_init.sh"

# shellcheck source=sbin/common/constants.sh
source "$SCRIPT_DIR/common/constants.sh"

# shellcheck source=sbin/common/common.sh
source "$SCRIPT_DIR/common/common.sh"

export OPENJDK_REPO_TAG
export OPENJDK_DIR
export JRE_TARGET_PATH
export CONFIGURE_ARGS=""
export MAKE_TEST_IMAGE=""
export GIT_CLONE_ARGUMENTS=()

# Parse the CL arguments, defers to the shared function in common-functions.sh
function parseArguments() {
    parseConfigurationArguments "$@"

    OPENJDK_DIR="${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[WORKING_DIR]}/${BUILD_CONFIG[OPENJDK_SOURCE_DIR]}"

    if [ "${BUILD_CONFIG[OPENJDK_CORE_VERSION]}" == "${JDK9_VERSION}" ]; then
        BUILD_CONFIG[COPY_MACOSX_FREE_FONT_LIB_FOR_JDK_FLAG]="true";
        BUILD_CONFIG[COPY_MACOSX_FREE_FONT_LIB_FOR_JRE_FLAG]="true";
    fi

    if [ "${BUILD_CONFIG[OPENJDK_CORE_VERSION]}" == "${JDK8_VERSION}" ]; then
        BUILD_CONFIG[COPY_MACOSX_FREE_FONT_LIB_FOR_JDK_FLAG]="false";
        BUILD_CONFIG[COPY_MACOSX_FREE_FONT_LIB_FOR_JRE_FLAG]="true";
    fi

    echo "JDK Image folder name: ${BUILD_CONFIG[JDK_PATH]}"
    echo "JRE Image folder name: ${BUILD_CONFIG[JRE_PATH]}"
    echo "[debug] COPY_MACOSX_FREE_FONT_LIB_FOR_JDK_FLAG=${BUILD_CONFIG[COPY_MACOSX_FREE_FONT_LIB_FOR_JDK_FLAG]}"
    echo "[debug] COPY_MACOSX_FREE_FONT_LIB_FOR_JRE_FLAG=${BUILD_CONFIG[COPY_MACOSX_FREE_FONT_LIB_FOR_JRE_FLAG]}"

    BUILD_CONFIG[MAKE_ARGS_FOR_ANY_PLATFORM]=${BUILD_CONFIG[MAKE_ARGS_FOR_ANY_PLATFORM]:-"images"}

    BUILD_CONFIG[CONFIGURE_ARGS_FOR_ANY_PLATFORM]=${BUILD_CONFIG[CONFIGURE_ARGS_FOR_ANY_PLATFORM]:-""}
}

# Add an argument to the configure call
addConfigureArg()
{
  # Only add an arg if it is not overridden by a user-specified arg.
  if [[ ${BUILD_CONFIG[CONFIGURE_ARGS_FOR_ANY_PLATFORM]} != *"$1"* ]] && [[ ${BUILD_CONFIG[USER_SUPPLIED_CONFIGURE_ARGS]} != *"$1"* ]]; then
    CONFIGURE_ARGS="${CONFIGURE_ARGS} ${1}${2}"
  fi
}

# Add an argument to the configure call (if it's not empty)
addConfigureArgIfValueIsNotEmpty()
{
  #Only try to add an arg if the second argument is not empty.
  if [ ! -z "$2" ]; then
    addConfigureArg "$1" "$2"
  fi
}

# Configure the boot JDK
configuringBootJDKConfigureParameter()
{

  if [ -z "${BUILD_CONFIG[JDK_BOOT_DIR]}" ] ; then
    echo "Searching for JDK_BOOT_DIR"

    # shellcheck disable=SC2046
    if [[ "${BUILD_CONFIG[OS_KERNEL_NAME]}" == "darwin" ]]; then
      BUILD_CONFIG[JDK_BOOT_DIR]=$(dirname $(dirname $(readlink $(which javac))))
    else
      BUILD_CONFIG[JDK_BOOT_DIR]=$(dirname $(dirname $(readlink -f $(which javac))))
    fi

    echo "Guessing JDK_BOOT_DIR: ${BUILD_CONFIG[JDK_BOOT_DIR]}"
    echo "If this is incorrect explicitly configure JDK_BOOT_DIR"
  else
    echo "Overriding JDK_BOOT_DIR, set to ${BUILD_CONFIG[JDK_BOOT_DIR]}"
  fi

  echo "Boot dir set to ${BUILD_CONFIG[JDK_BOOT_DIR]}"

  addConfigureArgIfValueIsNotEmpty "--with-boot-jdk=" "${BUILD_CONFIG[JDK_BOOT_DIR]}"
}

# Get the OpenJDK update version and build version
getOpenJDKUpdateAndBuildVersion()
{
  cd "${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[WORKING_DIR]}"

  if [ -d "${BUILD_CONFIG[OPENJDK_SOURCE_DIR]}/.git" ]; then

    # It does exist and it's a repo other than the AdoptOpenJDK one
    cd "${BUILD_CONFIG[OPENJDK_SOURCE_DIR]}" || return

    if [ -f ".git/shallow.lock" ]
    then
      echo "Detected lock file, assuming this is an error, removing"
      rm ".git/shallow.lock"
    fi

    # shellcheck disable=SC2154
    echo "Pulling latest tags and getting the latest update version using git fetch -q --tags ${BUILD_CONFIG[SHALLOW_CLONE_OPTION]}"
    # shellcheck disable=SC2154
    echo "NOTE: This can take quite some time!  Please be patient"
    git fetch -q --tags ${BUILD_CONFIG[SHALLOW_CLONE_OPTION]}
    OPENJDK_REPO_TAG=${BUILD_CONFIG[TAG]:-$(getFirstTagFromOpenJDKGitRepo)}
    if [[ "${OPENJDK_REPO_TAG}" == "" ]] ; then
     # shellcheck disable=SC2154
     echo "Unable to detect git tag, exiting..."
     exit 1
    else
     echo "OpenJDK repo tag is $OPENJDK_REPO_TAG"
    fi

    local openjdk_update_version;
    openjdk_update_version=$(echo "${OPENJDK_REPO_TAG}" | cut -d'u' -f 2 | cut -d'-' -f 1)

    # TODO dont modify config in build script
    echo "Version: ${openjdk_update_version} ${BUILD_CONFIG[OPENJDK_BUILD_NUMBER]}"
  fi

  cd "${BUILD_CONFIG[WORKSPACE_DIR]}"
}

# Ensure that we produce builds with versions strings something like:
#
# openjdk version "1.8.0_131"
# OpenJDK Runtime Environment (build 1.8.0-adoptopenjdk-<user>_2017_04_17_17_21-b00)
# OpenJDK 64-Bit Server VM (build 25.71-b00, mixed mode)
configuringVersionStringParameter()
{
  stepIntoTheWorkingDirectory

  if [ -z "${BUILD_CONFIG[TAG]}" ]; then
    OPENJDK_REPO_TAG=$(getFirstTagFromOpenJDKGitRepo)
    echo "OpenJDK repo tag is ${OPENJDK_REPO_TAG}"
  fi

  addConfigureArg "--with-milestone=" "fcs"
  local dateSuffix=$(date -u +%Y%m%d%H%M)

  if [ "${BUILD_CONFIG[OPENJDK_CORE_VERSION]}" == "${JDK8_CORE_VERSION}" ]; then

    if [ -z "${BUILD_CONFIG[TAG]}" ]; then
      addConfigureArg "--with-user-release-suffix=" "${dateSuffix}"
    fi

    if [ "${BUILD_CONFIG[BUILD_VARIANT]}" == "hotspot" ]; then
      addConfigureArg "--with-company-name=" "AdoptOpenJDK"
    fi

    # Set the update version (e.g. 131), this gets passed in from the calling script
    local updateNumber=${BUILD_CONFIG[OPENJDK_UPDATE_VERSION]}
    if [ -z "${updateNumber}" ]; then
      updateNumber=$(echo "${OPENJDK_REPO_TAG}" | cut -f1 -d"-" | cut -f2 -d"u")
    fi
    addConfigureArgIfValueIsNotEmpty "--with-update-version=" "${updateNumber}"

    # Set the build number (e.g. b04), this gets passed in from the calling script
    local buildNumber=${BUILD_CONFIG[OPENJDK_BUILD_NUMBER]}
    if [ -z "${buildNumber}" ]; then
      buildNumber=$(echo "$OPENJDK_REPO_TAG" | cut -f2 -d"-")
    fi
    addConfigureArgIfValueIsNotEmpty "--with-build-number=" "${buildNumber}"
  elif [ "${BUILD_CONFIG[OPENJDK_CORE_VERSION]}" == "${JDK9_CORE_VERSION}" ]; then
    local buildNumber=${BUILD_CONFIG[OPENJDK_BUILD_NUMBER]}
    if [ -z "${buildNumber}" ]; then
      buildNumber=$(echo "${OPENJDK_REPO_TAG}" | cut -f2 -d"+")
    fi

    TRIMMED_TAG=$(echo "${OPENJDK_REPO_TAG}" | cut -f2 -d"-" )

    if [ -z "${BUILD_CONFIG[TAG]}" ]; then
      addConfigureArg "--with-version-opt=" "${dateSuffix}"
    else
      addConfigureArg "--without-version-opt" ""
    fi

    addConfigureArg "--without-version-pre" ""
    addConfigureArgIfValueIsNotEmpty "--with-version-build=" "${buildNumber}"
  else
    # > JDK 9

    # Set the build number (e.g. b04), this gets passed in from the calling script
    local buildNumber=${BUILD_CONFIG[OPENJDK_BUILD_NUMBER]}
    if [ -z "${buildNumber}" ]; then
      buildNumber=$(echo "${OPENJDK_REPO_TAG}" | cut -f2 -d"+")
    fi

    if [ -z "${BUILD_CONFIG[TAG]}" ]; then
      addConfigureArg "--with-version-opt=" "${dateSuffix}"
    else
      addConfigureArg "--without-version-opt" ""
    fi

    addConfigureArg "--without-version-pre" ""
    addConfigureArgIfValueIsNotEmpty "--with-version-build=" "${buildNumber}"
    addConfigureArg "--with-vendor-version-string=" "AdoptOpenJDK"

  fi
  echo "Completed configuring the version string parameter, config args are now: ${CONFIGURE_ARGS}"
}

# Construct all of the 'configure' parameters
buildingTheRestOfTheConfigParameters()
{
  if [ ! -z "$(which ccache)" ]; then
    addConfigureArg "--enable-ccache" ""
  fi

  addConfigureArgIfValueIsNotEmpty "--with-jvm-variants=" "${BUILD_CONFIG[JVM_VARIANT]}"

  if [ "${BUILD_CONFIG[OPENJDK_CORE_VERSION]}" == "${JDK8_CORE_VERSION}" ] || [ "${BUILD_CONFIG[OPENJDK_CORE_VERSION]}" == "${JDK9_CORE_VERSION}" ]; then
    addConfigureArgIfValueIsNotEmpty "--with-cacerts-file=" "${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[WORKING_DIR]}/cacerts_area/security/cacerts"
  fi

  addConfigureArg "--with-alsa=" "${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[WORKING_DIR]}/installedalsa"

  # Point-in-time dependency for openj9 only
  if [[ "${BUILD_CONFIG[BUILD_VARIANT]}" == "openj9" ]] ; then
    addConfigureArg "--with-freemarker-jar=" "${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[WORKING_DIR]}/freemarker-${FREEMARKER_LIB_VERSION}/freemarker.jar"
    addConfigureArg "--with-openssl=" "fetched"
    addConfigureArg "--enable-openssl-bundling" ""
  fi

  addConfigureArg "--with-x=" "/usr/include/X11"

  if [ "${BUILD_CONFIG[OPENJDK_CORE_VERSION]}" == "${JDK8_CORE_VERSION}" ] ; then
    # We don't want any extra debug symbols - ensure it's set to release,
    # other options include fastdebug and slowdebug
    addConfigureArg "--with-debug-level=" "release"
    addConfigureArg "--disable-zip-debug-info" ""
    addConfigureArg "--disable-debug-symbols" ""
  else
    addConfigureArg "--with-debug-level=" "release"
    addConfigureArg "--with-native-debug-symbols=" "none"
  fi
}

configureFreetypeLocation() {
  if [[ ! "${CONFIGURE_ARGS}" =~ "--with-freetype" ]]; then
    if [[ "${BUILD_CONFIG[FREETYPE]}" == "true" ]] ; then
      if [[ "$OSTYPE" == "cygwin" ]] || [[ "$OSTYPE" == "msys" ]] ; then
        addConfigureArg "--with-freetype-src=" "${BUILD_CONFIG[WORKSPACE_DIR]}/libs/freetype"
      else
        local freetypeDir=BUILD_CONFIG[FREETYPE_DIRECTORY]
        case "${BUILD_CONFIG[OPENJDK_CORE_VERSION]}" in
           jdk8*|jdk9*|jdk10*) freetypeDir=${BUILD_CONFIG[FREETYPE_DIRECTORY]:-"${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[WORKING_DIR]}/installedfreetype"} ;;
           *) freetypeDir=${BUILD_CONFIG[FREETYPE_DIRECTORY]:-bundled} ;;
        esac

        echo "setting freetype dir to ${freetypeDir}"
        addConfigureArg "--with-freetype=" "${freetypeDir}"
      fi
    fi
  fi
}

# Configure the command parameters
configureCommandParameters()
{
  configuringVersionStringParameter
  configuringBootJDKConfigureParameter

  if [[ "$OSTYPE" == "cygwin" ]] || [[ "$OSTYPE" == "msys" ]] ; then
    echo "Windows or Windows-like environment detected, skipping configuring environment for custom Boot JDK and other 'configure' settings."
  else
    echo "Building up the configure command..."
    buildingTheRestOfTheConfigParameters
  fi

  # Now we add any configure arguments the user has specified on the command line.
  CONFIGURE_ARGS="${CONFIGURE_ARGS} ${BUILD_CONFIG[USER_SUPPLIED_CONFIGURE_ARGS]}"

  configureFreetypeLocation

  echo "Completed configuring the version string parameter, config args are now: ${CONFIGURE_ARGS}"
}

# Make sure we're in the source directory for OpenJDK now
stepIntoTheWorkingDirectory() {
  cd "${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[WORKING_DIR]}/${BUILD_CONFIG[OPENJDK_SOURCE_DIR]}"  || exit
  echo "Should have the source, I'm at $PWD"
}

buildTemplatedFile() {
  echo "Configuring command and using the pre-built config params..."

  stepIntoTheWorkingDirectory

  echo "Currently at '${PWD}'"

  FULL_CONFIGURE="bash ./configure ${CONFIGURE_ARGS} ${BUILD_CONFIG[CONFIGURE_ARGS_FOR_ANY_PLATFORM]}"
  echo "Running ./configure with arguments '${FULL_CONFIGURE}'"

  # If it's Java 9+ then we also make test-image to build the native test libraries
  JDK_PREFIX="jdk"
  JDK_VERSION_NUMBER="${BUILD_CONFIG[OPENJDK_CORE_VERSION]#$JDK_PREFIX}"
  if [ "$JDK_VERSION_NUMBER" -gt 8 ]; then
    MAKE_TEST_IMAGE=" test-image" # the added white space is deliberate as it's the last arg
  fi

  FULL_MAKE_COMMAND="${BUILD_CONFIG[MAKE_COMMAND_NAME]} ${BUILD_CONFIG[MAKE_ARGS_FOR_ANY_PLATFORM]} ${MAKE_TEST_IMAGE}"

  # shellcheck disable=SC2002
  cat "$SCRIPT_DIR/build.template" | \
      sed -e "s|{configureArg}|${FULL_CONFIGURE}|" \
      -e "s|{makeCommandArg}|${FULL_MAKE_COMMAND}|" > "${BUILD_CONFIG[WORKSPACE_DIR]}/config/configure-and-build.sh"
}

executeTemplatedFile() {
  stepIntoTheWorkingDirectory

  echo "Currently at '${PWD}'"
  bash "${BUILD_CONFIG[WORKSPACE_DIR]}/config/configure-and-build.sh"
  exitCode=$?

  if [ "${exitCode}" -eq 1 ]; then
    echo "Failed to make the JDK, exiting"
    exit 1;
  elif [ "${exitCode}" -eq 2 ]; then
    echo "Failed to configure the JDK, exiting"
    echo "Did you set the JDK boot directory correctly? Override by exporting JDK_BOOT_DIR"
    echo "For example, on RHEL you would do export JDK_BOOT_DIR=/usr/lib/jvm/java-1.7.0-openjdk-1.7.0.131-2.6.9.0.el7_3.x86_64"
    echo "Current JDK_BOOT_DIR value: ${BUILD_CONFIG[JDK_BOOT_DIR]}"
    exit 2;
  fi

}

# Print the version string so we know what we've produced
printJavaVersionString()
{
  # shellcheck disable=SC2086
  PRODUCT_HOME=$(ls -d ${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[WORKING_DIR]}/${BUILD_CONFIG[OPENJDK_SOURCE_DIR]}/build/*/images/${BUILD_CONFIG[JDK_PATH]})
  if [[ -d "$PRODUCT_HOME" ]]; then
     echo "'$PRODUCT_HOME' found"
     if ! "$PRODUCT_HOME"/bin/java -version; then
       echo " Error executing 'java' does not exist in '$PRODUCT_HOME'."
       exit -1
     fi
  else
    echo "'$PRODUCT_HOME' does not exist, build might have not been successful or not produced the expected JDK image at this location."
    exit -1
  fi
}

# Clean up
removingUnnecessaryFiles()
{
  echo "Removing unnecessary files now..."

  if [ -z "$OPENJDK_REPO_TAG" ]; then
    echo "Fetching the first tag from the OpenJDK git repo..."
    echo "Dir=${PWD}"
    OPENJDK_REPO_TAG=$(getFirstTagFromOpenJDKGitRepo)
  fi

  cd "${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[WORKING_DIR]}/${BUILD_CONFIG[OPENJDK_SOURCE_DIR]}" || return

  cd build/*/images || return

  echo "Currently at '${PWD}'"

  echo "moving ${BUILD_CONFIG[JDK_PATH]} to ${OPENJDK_REPO_TAG}"
  rm -rf "${OPENJDK_REPO_TAG}" || true
  mv "${BUILD_CONFIG[JDK_PATH]}" "${OPENJDK_REPO_TAG}"

  if [ -d "${BUILD_CONFIG[JRE_PATH]}" ]
  then
    JRE_TARGET_PATH="${OPENJDK_REPO_TAG}-jre"
    [ "${JRE_TARGET_PATH}" == "${OPENJDK_REPO_TAG}" ] && JRE_TARGET_PATH="${OPENJDK_REPO_TAG}.jre"
    echo "moving ${BUILD_CONFIG[JRE_PATH]} to ${JRE_TARGET_PATH}"
    rm -rf "${JRE_TARGET_PATH}" || true
    mv "${BUILD_CONFIG[JRE_PATH]}" "${JRE_TARGET_PATH}"

    rm -rf "${JRE_TARGET_PATH}"/demo/applets || true
    rm -rf "${JRE_TARGET_PATH}"/demo/jfc/Font2DTest || true
    rm -rf "${JRE_TARGET_PATH}"/demo/jfc/SwingApplet || true
  fi


  # Remove files we don't need
  rm -rf "${OPENJDK_REPO_TAG}"/demo/applets || true
  rm -rf "${OPENJDK_REPO_TAG}"/demo/jfc/Font2DTest || true
  rm -rf "${OPENJDK_REPO_TAG}"/demo/jfc/SwingApplet || true

  find . -name "*.diz" -type f -delete || true

  echo "Finished removing unnecessary files from ${OPENJDK_REPO_TAG}"
}

# If on a Mac, mac a copy of the font lib as required
makeACopyOfLibFreeFontForMacOSX() {
    IMAGE_DIRECTORY=$1
    PERFORM_COPYING=$2

    if [ ! -d "${IMAGE_DIRECTORY}" ]; then
      echo "Could not find dir: ${IMAGE_DIRECTORY}"
      return
    fi

    if [[ "${BUILD_CONFIG[OS_KERNEL_NAME]}" == "darwin" ]]; then
        echo "PERFORM_COPYING=${PERFORM_COPYING}"
        if [ "${PERFORM_COPYING}" == "false" ]; then
            echo " Skipping copying of the free font library to ${IMAGE_DIRECTORY}, does not apply for this version of the JDK. "
            return
        fi

       echo " Performing copying of the free font library to ${IMAGE_DIRECTORY}, applicable for this version of the JDK. "

        SOURCE_LIB_NAME="${IMAGE_DIRECTORY}/lib/libfreetype.dylib.6"

        if [ ! -f "${SOURCE_LIB_NAME}" ]; then
          SOURCE_LIB_NAME="${IMAGE_DIRECTORY}/lib/libfreetype.dylib"
        fi

        if [ ! -f "${SOURCE_LIB_NAME}" ]; then
            echo "[Error] ${SOURCE_LIB_NAME} does not exist in the ${IMAGE_DIRECTORY} folder, please check if this is the right folder to refer to, aborting copy process..."
            exit -1
        fi

        TARGET_LIB_NAME="${IMAGE_DIRECTORY}/lib/libfreetype.6.dylib"

        INVOKED_BY_FONT_MANAGER="${IMAGE_DIRECTORY}/lib/libfontmanager.dylib"

        echo "Currently at '${PWD}'"
        echo "Copying ${SOURCE_LIB_NAME} to ${TARGET_LIB_NAME}"
        echo " *** Workaround to fix the MacOSX issue where invocation to ${INVOKED_BY_FONT_MANAGER} fails to find ${TARGET_LIB_NAME} ***"

        cp "${SOURCE_LIB_NAME}" "${TARGET_LIB_NAME}"
        if [ -f "${INVOKED_BY_FONT_MANAGER}" ]; then
            otool -L "${INVOKED_BY_FONT_MANAGER}"
        else
            # shellcheck disable=SC2154
            echo "[Warning] ${INVOKED_BY_FONT_MANAGER} does not exist in the ${IMAGE_DIRECTORY} folder, please check if this is the right folder to refer to, this may cause runtime issues, please beware..."
        fi

        otool -L "${TARGET_LIB_NAME}"

        echo "Finished copying ${SOURCE_LIB_NAME} to ${TARGET_LIB_NAME}"
    fi
}


# Get the first tag from the git repo
getFirstTagFromOpenJDKGitRepo()
{
    git fetch --tags "${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[WORKING_DIR]}/${BUILD_CONFIG[OPENJDK_SOURCE_DIR]}"
    justOneFromTheRevList=$(git rev-list --tags --max-count=1)
    tagNameFromRepo=$(git describe --tags "$justOneFromTheRevList")
    echo "$tagNameFromRepo"
}

createArchive() {
  repoLocation=$1
  targetName=$2

  archiveExtension=$(getArchiveExtension)

  createOpenJDKArchive "${repoLocation}" "OpenJDK"
  archive="${PWD}/OpenJDK${archiveExtension}"

  echo "Your final archive was created at ${archive}"

  echo "Moving the artifact to ${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[TARGET_DIR]}"
  mv "${archive}" "${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[TARGET_DIR]}/${targetName}"
}

# Create a Tar ball
createOpenJDKTarArchive()
{
  COMPRESS=gzip
  if which pigz >/dev/null 2>&1; then COMPRESS=pigz; fi
  echo "Archiving the build OpenJDK image and compressing with $COMPRESS"

  if [ -z "${OPENJDK_REPO_TAG+x}" ] || [ -z "${OPENJDK_REPO_TAG}" ]; then
    OPENJDK_REPO_TAG=$(getFirstTagFromOpenJDKGitRepo)
  fi
  if [ -z "${JRE_TARGET_PATH+x}" ] || [ -z "${JRE_TARGET_PATH}" ]; then
    JRE_TARGET_PATH="${OPENJDK_REPO_TAG}-jre"
  fi

  echo "OpenJDK repo tag is ${OPENJDK_REPO_TAG}. JRE path will be ${JRE_TARGET_PATH}"

  ## clean out old builds
  rm -r "${BUILD_CONFIG[WORKSPACE_DIR]:?}/${BUILD_CONFIG[TARGET_DIR]}" || true
  mkdir -p "${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[TARGET_DIR]}" || exit

  if [ -d "${JRE_TARGET_PATH}" ]; then
    createArchive "${JRE_TARGET_PATH}" "${BUILD_CONFIG[TARGET_FILE_NAME]/_/-jre_}"
  fi
  createArchive "${OPENJDK_REPO_TAG}" "${BUILD_CONFIG[TARGET_FILE_NAME]}"
}

# Echo success
showCompletionMessage()
{
  echo "All done!"
}

################################################################################

loadConfigFromFile
cd "${BUILD_CONFIG[WORKSPACE_DIR]}"

parseArguments "$@"
configureWorkspace

getOpenJDKUpdateAndBuildVersion
configureCommandParameters
buildTemplatedFile
executeTemplatedFile

printJavaVersionString
removingUnnecessaryFiles
makeACopyOfLibFreeFontForMacOSX "${OPENJDK_REPO_TAG}" "${BUILD_CONFIG[COPY_MACOSX_FREE_FONT_LIB_FOR_JDK_FLAG]}"
makeACopyOfLibFreeFontForMacOSX "${OPENJDK_REPO_TAG}-jre" "${BUILD_CONFIG[COPY_MACOSX_FREE_FONT_LIB_FOR_JRE_FLAG]}"
createOpenJDKTarArchive
showCompletionMessage

# ccache is not detected properly TODO
# change grep to something like $GREP -e '^1.*' -e '^2.*' -e '^3\.0.*' -e '^3\.1\.[0123]$'`]
# See https://github.com/AdoptOpenJDK/openjdk-jdk8u/blob/dev/common/autoconf/build-performance.m4
