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

export JRE_TARGET_PATH
export CONFIGURE_ARGS=""
export MAKE_TEST_IMAGE=""
export GIT_CLONE_ARGUMENTS=()

# Parse the CL arguments, defers to the shared function in common-functions.sh
function parseArguments() {
    parseConfigurationArguments "$@"
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
    local openJdkVersion=$(getOpenJdkVersion)
    if [[ "${openJdkVersion}" == "" ]] ; then
     # shellcheck disable=SC2154
     echo "Unable to detect git tag, exiting..."
     exit 1
    else
     echo "OpenJDK repo tag is $openJdkVersion"
    fi

    local openjdk_update_version;
    openjdk_update_version=$(echo "${openJdkVersion}" | cut -d'u' -f 2 | cut -d'-' -f 1)

    # TODO dont modify config in build script
    echo "Version: ${openjdk_update_version} ${BUILD_CONFIG[OPENJDK_BUILD_NUMBER]}"
  fi

  cd "${BUILD_CONFIG[WORKSPACE_DIR]}"
}

getOpenJdkVersion() {
  local version;

  if [ "${BUILD_CONFIG[BUILD_VARIANT]}" == "${BUILD_VARIANT_CORRETTO}" ]; then
    local updateRegex="UPDATE_VERSION=([0-9]+)";
    local buildRegex="BUILD_NUMBER=b([0-9]+)";

    local versionData="$(tr '\n' ' ' < ${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[WORKING_DIR]}/${BUILD_CONFIG[OPENJDK_SOURCE_DIR]}/version.spec)"

    local updateNum
    local buildNum
    if [[ "${versionData}" =~ $updateRegex ]]; then
      updateNum="${BASH_REMATCH[1]}"
    fi
    if [[ "${versionData}" =~ $buildRegex ]]; then
      buildNum="${BASH_REMATCH[1]}"
    fi
    version="8u${updateNum}-b${buildNum}"
  else
    version=${BUILD_CONFIG[TAG]:-$(getFirstTagFromOpenJDKGitRepo)}
  fi

  echo ${version}
}

# Ensure that we produce builds with versions strings something like:
#
# openjdk version "1.8.0_131"
# OpenJDK Runtime Environment (build 1.8.0-adoptopenjdk-<user>_2017_04_17_17_21-b00)
# OpenJDK 64-Bit Server VM (build 25.71-b00, mixed mode)
configuringVersionStringParameter()
{
  stepIntoTheWorkingDirectory

  local openJdkVersion=$(getOpenJdkVersion)
  echo "OpenJDK repo tag is ${openJdkVersion}"

  addConfigureArg "--with-milestone=" "fcs"
  local dateSuffix=$(date -u +%Y%m%d%H%M)

  if [ "${BUILD_CONFIG[OPENJDK_CORE_VERSION]}" == "${JDK8_CORE_VERSION}" ]; then

    if [ "${BUILD_CONFIG[RELEASE]}" == "false" ]; then
      addConfigureArg "--with-user-release-suffix=" "${dateSuffix}"
    fi

    if [ "${BUILD_CONFIG[BUILD_VARIANT]}" == "${BUILD_VARIANT_HOTSPOT}" ]; then
      addConfigureArg "--with-company-name=" "AdoptOpenJDK"
    fi

    # Set the update version (e.g. 131), this gets passed in from the calling script
    local updateNumber=${BUILD_CONFIG[OPENJDK_UPDATE_VERSION]}
    if [ -z "${updateNumber}" ]; then
      updateNumber=$(echo "${openJdkVersion}" | cut -f1 -d"-" | cut -f2 -d"u")
    fi
    addConfigureArgIfValueIsNotEmpty "--with-update-version=" "${updateNumber}"

    # Set the build number (e.g. b04), this gets passed in from the calling script
    local buildNumber=${BUILD_CONFIG[OPENJDK_BUILD_NUMBER]}
    if [ -z "${buildNumber}" ]; then
      buildNumber=$(echo "${openJdkVersion}" | cut -f2 -d"-")
    fi

    if [ "${buildNumber}" ] && [ "${buildNumber}" != "ga" ]; then
      addConfigureArgIfValueIsNotEmpty "--with-build-number=" "${buildNumber}"
    fi
  elif [ "${BUILD_CONFIG[OPENJDK_CORE_VERSION]}" == "${JDK9_CORE_VERSION}" ]; then
    local buildNumber=${BUILD_CONFIG[OPENJDK_BUILD_NUMBER]}
    if [ -z "${buildNumber}" ]; then
      buildNumber=$(echo "${openJdkVersion}" | cut -f2 -d"+")
    fi

    if [ "${BUILD_CONFIG[RELEASE]}" == "false" ]; then
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
      buildNumber=$(echo "${openJdkVersion}" | cut -f2 -d"+")
    fi

    if [ "${BUILD_CONFIG[RELEASE]}" == "false" ]; then
      addConfigureArg "--with-version-opt=" "${dateSuffix}"
    else
      addConfigureArg "--without-version-opt" ""
    fi

    addConfigureArg "--without-version-pre" ""
    addConfigureArgIfValueIsNotEmpty "--with-version-build=" "${buildNumber}"
    addConfigureArg "--with-vendor-version-string=" "AdoptOpenJDK"
    addConfigureArg "--with-vendor-url=" "https://adoptopenjdk.net/"
    addConfigureArg "--with-vendor-name=" "AdoptOpenJDK"
    addConfigureArg "--with-vendor-vm-bug-url=" "https://github.com/AdoptOpenJDK/openjdk-build/issues"


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

  addConfigureArg "--with-alsa=" "${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[WORKING_DIR]}/installedalsa"

  # Point-in-time dependency for openj9 only
  if [[ "${BUILD_CONFIG[BUILD_VARIANT]}" == "${BUILD_VARIANT_OPENJ9}" ]] ; then
    addConfigureArg "--with-freemarker-jar=" "${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[WORKING_DIR]}/freemarker-${FREEMARKER_LIB_VERSION}/freemarker.jar"
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
        case "${BUILD_CONFIG[OPENJDK_CORE_VERSION]}" in
           jdk9*|jdk10*) addConfigureArg "--with-freetype-src=" "${BUILD_CONFIG[WORKSPACE_DIR]}/libs/freetype" ;;
           *) freetypeDir=${BUILD_CONFIG[FREETYPE_DIRECTORY]:-bundled} ;;
        esac
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

  if [[ "$OSTYPE" == "cygwin" ]] || [[ "$OSTYPE" == "msys" ]]; then
    echo "Windows or Windows-like environment detected, skipping configuring environment for custom Boot JDK and other 'configure' settings."

    if [[ "${BUILD_CONFIG[BUILD_VARIANT]}" == "${BUILD_VARIANT_OPENJ9}" ]] && [ "${BUILD_CONFIG[OPENJDK_CORE_VERSION]}" == "${JDK8_CORE_VERSION}" ]; then
      # This is unfortunatly required as if the path does not start with "/cygdrive" the make scripts are unable to find the "/closed/adds" dir
      local addsDir="/cygdrive/c/cygwin64/${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[WORKING_DIR]}/${BUILD_CONFIG[OPENJDK_SOURCE_DIR]}/closed/adds"
      echo "adding source route -with-add-source-root=${addsDir}"
      addConfigureArg "--with-add-source-root=" "${addsDir}"
    fi
  else
    echo "Building up the configure command..."
    buildingTheRestOfTheConfigParameters
  fi

  if [ "${BUILD_CONFIG[OPENJDK_CORE_VERSION]}" == "${JDK8_CORE_VERSION}" ] || [ "${BUILD_CONFIG[OPENJDK_CORE_VERSION]}" == "${JDK9_CORE_VERSION}" ]; then
    addConfigureArgIfValueIsNotEmpty "--with-cacerts-file=" "${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[WORKING_DIR]}/cacerts_area/security/cacerts"
  fi

  # Now we add any configure arguments the user has specified on the command line.
  CONFIGURE_ARGS="${CONFIGURE_ARGS} ${BUILD_CONFIG[USER_SUPPLIED_CONFIGURE_ARGS]}"

  configureFreetypeLocation

  echo "Completed configuring the version string parameter, config args are now: ${CONFIGURE_ARGS}"
}

# Make sure we're in the source directory for OpenJDK now
stepIntoTheWorkingDirectory() {
  cd "${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[WORKING_DIR]}/${BUILD_CONFIG[OPENJDK_SOURCE_DIR]}"  || exit

  # corretto nest their source under /src in their dir
  if [ "${BUILD_CONFIG[BUILD_VARIANT]}" == "${BUILD_VARIANT_CORRETTO}" ]; then
    cd "src";
  fi

  echo "Should have the source, I'm at $PWD"
}

buildTemplatedFile() {
  echo "Configuring command and using the pre-built config params..."

  stepIntoTheWorkingDirectory

  echo "Currently at '${PWD}'"

  FULL_CONFIGURE="bash ./configure --verbose ${CONFIGURE_ARGS} ${BUILD_CONFIG[CONFIGURE_ARGS_FOR_ANY_PLATFORM]}"
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
  stepIntoTheWorkingDirectory

  case "${BUILD_CONFIG[OS_KERNEL_NAME]}" in
  "darwin")
    # shellcheck disable=SC2086
    PRODUCT_HOME=$(ls -d ${PWD}/build/*/images/${BUILD_CONFIG[JDK_PATH]}/Contents/Home)
  ;;
  *)
    # shellcheck disable=SC2086
    PRODUCT_HOME=$(ls -d ${PWD}/build/*/images/${BUILD_CONFIG[JDK_PATH]})
  ;;
  esac
  if [[ -d "$PRODUCT_HOME" ]]; then
     echo "'$PRODUCT_HOME' found"
     if ! "$PRODUCT_HOME"/bin/java -version; then

       echo "===$PRODUCT_HOME===="
       ls -alh "$PRODUCT_HOME"

       echo "===$PRODUCT_HOME/bin/===="
       ls -alh "$PRODUCT_HOME/bin/"

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

  local openJdkVersion=$(getOpenJdkVersion)
  stepIntoTheWorkingDirectory

  cd build/*/images || return

  echo "Currently at '${PWD}'"

  local jdkPath=$(ls -d ${BUILD_CONFIG[JDK_PATH]})
  echo "moving ${jdkPath} to ${openJdkVersion}"
  rm -rf "${openJdkVersion}" || true
  mv "${jdkPath}" "${openJdkVersion}"

  if [ -d "$(ls -d ${BUILD_CONFIG[JRE_PATH]})" ]
  then
    JRE_TARGET_PATH="${openJdkVersion}-jre"
    [ "${JRE_TARGET_PATH}" == "${openJdkVersion}" ] && JRE_TARGET_PATH="${openJdkVersion}.jre"
    echo "moving $(ls -d ${BUILD_CONFIG[JRE_PATH]}) to ${JRE_TARGET_PATH}"
    rm -rf "${JRE_TARGET_PATH}" || true
    mv "$(ls -d ${BUILD_CONFIG[JRE_PATH]})" "${JRE_TARGET_PATH}"

    case "${BUILD_CONFIG[OS_KERNEL_NAME]}" in
      "darwin") JRE_TARGET="${JRE_TARGET_PATH}/Contents/Home" ;;
      *) JRE_TARGET="${JRE_TARGET_PATH}" ;;
    esac
    rm -rf "${JRE_TARGET}"/demo/applets || true
    rm -rf "${JRE_TARGET}"/demo/jfc/Font2DTest || true
    rm -rf "${JRE_TARGET}"/demo/jfc/SwingApplet || true
  fi

  # Remove files we don't need
  case "${BUILD_CONFIG[OS_KERNEL_NAME]}" in
    "darwin") JDK_TARGET="${openJdkVersion}/Contents/Home" ;;
    *) JDK_TARGET="${openJdkVersion}" ;;
  esac
  rm -rf "${JDK_TARGET}"/demo/applets || true
  rm -rf "${JDK_TARGET}"/demo/jfc/Font2DTest || true
  rm -rf "${JDK_TARGET}"/demo/jfc/SwingApplet || true

  find . -name "*.diz" -type f -delete || true
  find . -name "*.pdb" -type f -delete || true
  find . -name "*.map" -type f -delete || true

  echo "Finished removing unnecessary files from ${openJdkVersion}"
}

moveFreetypeLib() {
  local LIB_DIRECTORY="${1}"

  if [ ! -d "${LIB_DIRECTORY}" ]; then
    echo "Could not find dir: ${LIB_DIRECTORY}"
    return
  fi

  echo " Performing copying of the free font library to ${LIB_DIRECTORY}, applicable for this version of the JDK. "

  local SOURCE_LIB_NAME="${LIB_DIRECTORY}/libfreetype.dylib.6"

  if [ ! -f "${SOURCE_LIB_NAME}" ]; then
    SOURCE_LIB_NAME="${LIB_DIRECTORY}/libfreetype.dylib"
  fi

  if [ ! -f "${SOURCE_LIB_NAME}" ]; then
      echo "[Error] ${SOURCE_LIB_NAME} does not exist in the ${LIB_DIRECTORY} folder, please check if this is the right folder to refer to, aborting copy process..."
      return
  fi

  local TARGET_LIB_NAME="${LIB_DIRECTORY}/libfreetype.6.dylib"

  local INVOKED_BY_FONT_MANAGER="${LIB_DIRECTORY}/libfontmanager.dylib"

  echo "Currently at '${PWD}'"
  echo "Copying ${SOURCE_LIB_NAME} to ${TARGET_LIB_NAME}"
  echo " *** Workaround to fix the MacOSX issue where invocation to ${INVOKED_BY_FONT_MANAGER} fails to find ${TARGET_LIB_NAME} ***"

  cp "${SOURCE_LIB_NAME}" "${TARGET_LIB_NAME}"
  if [ -f "${INVOKED_BY_FONT_MANAGER}" ]; then
      otool -L "${INVOKED_BY_FONT_MANAGER}"
  else
      # shellcheck disable=SC2154
      echo "[Warning] ${INVOKED_BY_FONT_MANAGER} does not exist in the ${LIB_DIRECTORY} folder, please check if this is the right folder to refer to, this may cause runtime issues, please beware..."
  fi

  otool -L "${TARGET_LIB_NAME}"

  echo "Finished copying ${SOURCE_LIB_NAME} to ${TARGET_LIB_NAME}"
}


# If on a Mac, mac a copy of the font lib as required
makeACopyOfLibFreeFontForMacOSX() {
    local DIRECTORY="${1}"
    local PERFORM_COPYING=$2

    echo "PERFORM_COPYING=${PERFORM_COPYING}"
    if [ "${PERFORM_COPYING}" == "false" ]; then
        echo " Skipping copying of the free font library to ${DIRECTORY}, does not apply for this version of the JDK. "
        return
    fi

    if [[ "${BUILD_CONFIG[OS_KERNEL_NAME]}" == "darwin" ]]; then
      moveFreetypeLib "${DIRECTORY}/Contents/Home/lib"
      moveFreetypeLib "${DIRECTORY}/Contents/Home/jre/lib"
    fi
}


# Get the first tag from the git repo
# Excluding "openj9" tag names as they have other ones for milestones etc. that get in the way
getFirstTagFromOpenJDKGitRepo()
{
    git fetch --tags "${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[WORKING_DIR]}/${BUILD_CONFIG[OPENJDK_SOURCE_DIR]}"
    revList=$(git rev-list --tags --topo-order --max-count=$GIT_TAGS_TO_SEARCH)
    firstMatchingNameFromRepo=$(git describe --tags $revList | grep jdk | grep -v openj9 | head -1)
    echo "$firstMatchingNameFromRepo"
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

  local openJdkVersion=$(getOpenJdkVersion)

  if which pigz >/dev/null 2>&1; then COMPRESS=pigz; fi
  echo "Archiving the build OpenJDK image and compressing with $COMPRESS"

  if [ -z "${openJdkVersion+x}" ] || [ -z "${openJdkVersion}" ]; then
    openJdkVersion=$(getFirstTagFromOpenJDKGitRepo)
  fi
  if [ -z "${JRE_TARGET_PATH+x}" ] || [ -z "${JRE_TARGET_PATH}" ]; then
    JRE_TARGET_PATH="${openJdkVersion}-jre"
  fi

  echo "OpenJDK repo tag is ${openJdkVersion}. JRE path will be ${JRE_TARGET_PATH}"

  ## clean out old builds
  rm -r "${BUILD_CONFIG[WORKSPACE_DIR]:?}/${BUILD_CONFIG[TARGET_DIR]}" || true
  mkdir -p "${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[TARGET_DIR]}" || exit

  if [ -d "${JRE_TARGET_PATH}" ]; then
    local jreName=$(echo "${BUILD_CONFIG[TARGET_FILE_NAME]}" | sed 's/-jdk/-jre/')
    createArchive "${JRE_TARGET_PATH}" "${jreName}"
  fi
  createArchive "${openJdkVersion}" "${BUILD_CONFIG[TARGET_FILE_NAME]}"
}

# Echo success
showCompletionMessage()
{
  echo "All done!"
}

copyFreeFontForMacOS() {
  local openJdkVersion=$(getOpenJdkVersion)
  makeACopyOfLibFreeFontForMacOSX "${openJdkVersion}" "${BUILD_CONFIG[COPY_MACOSX_FREE_FONT_LIB_FOR_JDK_FLAG]}"
  makeACopyOfLibFreeFontForMacOSX "${openJdkVersion}-jre" "${BUILD_CONFIG[COPY_MACOSX_FREE_FONT_LIB_FOR_JRE_FLAG]}"
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
copyFreeFontForMacOS
createOpenJDKTarArchive
showCompletionMessage

# ccache is not detected properly TODO
# change grep to something like $GREP -e '^1.*' -e '^2.*' -e '^3\.0.*' -e '^3\.1\.[0123]$'`]
# See https://github.com/AdoptOpenJDK/openjdk-jdk8u/blob/dev/common/autoconf/build-performance.m4
