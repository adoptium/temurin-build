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

# Script to download any additional packages for building OpenJDK
# before calling ./configure (using JDK 7 as the base)


SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# shellcheck source=sbin/common-functions.sh
source "$SCRIPT_DIR/common-functions.sh"

WORKING_DIR=""
TARGET_DIR=""
OPENJDK_REPO_NAME=""
JVM_VARIANT="${JVM_VARIANT:-server}"
OPENJDK_UPDATE_VERSION=""
OPENJDK_BUILD_NUMBER=""
OPENJDK_REPO_TAG=""
JRE_TARGET_PATH=""
TRIMMED_TAG=""
USER_SUPPLIED_CONFIGURE_ARGS=""

while [[ $# -gt 0 ]] && [[ ."$1" = .-* ]] ; do
  opt="$1";
  shift;
  case "$opt" in
    "--" ) break 2;;

    "--source" | "-s" )
    WORKING_DIR="$1"; shift;;

    "--destination" | "-d" )
    TARGET_DIR="$1"; shift;;

    "--repository" | "-r" )
    OPENJDK_REPO_NAME="$1"; shift;;

    "--variant"  | "-jv" )
    JVM_VARIANT="$1"; shift;;

    "--update-version"  | "-uv" )
    OPENJDK_UPDATE_VERSION="$1"; shift;;

    "--build-number"  | "-bn" )
    OPENJDK_BUILD_NUMBER="$1"; shift;;

    "--repository-tag"  | "-rt" )
    OPENJDK_REPO_TAG="$1"; shift;;

    "--configure-args"  | "-ca" )
    USER_SUPPLIED_CONFIGURE_ARGS="$1"; shift;;

    *) echo >&2 "${error}Invalid build.sh option: ${opt}${normal}"; exit 1;;
  esac
done

OPENJDK_DIR=$WORKING_DIR/$OPENJDK_REPO_NAME


RUN_JTREG_TESTS_ONLY=""


if [ "$JVM_VARIANT" == "--run-jtreg-tests-only" ]; then
  RUN_JTREG_TESTS_ONLY="--run-jtreg-tests-only"
  JVM_VARIANT="server"
fi

echo "JDK Image folder name: ${JDK_PATH}"
echo "JRE Image folder name: ${JRE_PATH}"
echo "[debug] COPY_MACOSX_FREE_FONT_LIB_FOR_JDK_FLAG=${COPY_MACOSX_FREE_FONT_LIB_FOR_JDK_FLAG}"
echo "[debug] COPY_MACOSX_FREE_FONT_LIB_FOR_JRE_FLAG=${COPY_MACOSX_FREE_FONT_LIB_FOR_JRE_FLAG}"

MAKE_COMMAND_NAME=${MAKE_COMMAND_NAME:-"make"}
MAKE_ARGS_FOR_ANY_PLATFORM=${MAKE_ARGS_FOR_ANY_PLATFORM:-"images"}
# Defaults to not building this target, for Java 9+ we set this to test-image in order to build the native test libraries
MAKE_TEST_IMAGE=""
CONFIGURE_ARGS_FOR_ANY_PLATFORM=${CONFIGURE_ARGS_FOR_ANY_PLATFORM:-""}

addConfigureArg()
{
  #Only add an arg if it is not overridden by a user-specified arg.
  if [[ ${CONFIGURE_ARGS_FOR_ANY_PLATFORM} != *"$1"* ]] && [[ ${USER_SUPPLIED_CONFIGURE_ARGS} != *"$1"* ]]; then
    CONFIGURE_ARGS="${CONFIGURE_ARGS} ${1}${2}"
  fi
}

addConfigureArgIfValueIsNotEmpty()
{
  #Only try to add an arg if the second argument is not empty.
  if [ ! -z "$2" ]; then
    addConfigureArg "$1" "$2"
  fi
}

sourceFileWithColourCodes()
{
  # shellcheck disable=SC1090
  # shellcheck disable=SC1091
  source "$SCRIPT_DIR"/colour-codes.sh
}

checkIfDockerIsUsedForBuildingOrNot()
{
  # If on docker

  if [[ -f /.dockerenv ]] ; then
    echo "Detected we're in docker"
    WORKING_DIR=/openjdk/build
    TARGET_DIR=/openjdk/target/
    OPENJDK_REPO_NAME=/openjdk
    OPENJDK_DIR="$WORKING_DIR/$OPENJDK_REPO_NAME"
    USE_DOCKER=true
  fi

  # E.g. /openjdk/build if you're building in a Docker container
  # otherwise ensure it's a writable area e.g. /home/youruser/myopenjdkarea

  if [ -z "$WORKING_DIR" ] || [ -z "$TARGET_DIR" ] ; then
    echo "build.sh is called by makejdk.sh and requires two parameters"
    echo "Are you sure you want to call it directly?"
    echo "Usage: bash ./${0} <workingarea> <targetforjdk>"
    echo "Note that you must have the OpenJDK source before using this script!"
    echo "This script will try to move ./openjdk to the source directory for you, "
    echo "and this will be your working area where all required files will be downloaded to."
    echo "You can override the JDK boot directory by setting the environment variable JDK_BOOT_DIR"
    exit;
  fi
}

createWorkingDirectory()
{
  echo "Making the working directory to store source files and extensions: ${WORKING_DIR}"

  mkdir -p $WORKING_DIR

  cd $WORKING_DIR || exit
}

configuringBootJDKConfigureParameter()
{
  if [ -z "$JDK_BOOT_DIR" ] ; then
    echo "JDK_BOOT_DIR is ${JDK_BOOT_DIR}"
    JDK_BOOT_DIR=/usr/lib/java-1.7.0
  else
    echo "Overriding JDK_BOOT_DIR, set to ${JDK_BOOT_DIR}"
  fi

  echo "Boot dir set to ${JDK_BOOT_DIR}"

  addConfigureArgIfValueIsNotEmpty "--with-boot-jdk=" "${JDK_BOOT_DIR}"
}

# Ensure that we produce builds with versions strings something like:
#
# openjdk version "1.8.0_131"
# OpenJDK Runtime Environment (build 1.8.0-adoptopenjdk-<user>_2017_04_17_17_21-b00)
# OpenJDK 64-Bit Server VM (build 25.71-b00, mixed mode)
configuringVersionStringParameter()
{
  if [ "$OPENJDK_CORE_VERSION" == "jdk8" ]; then
    # Replace the default 'internal' with our own milestone string
    addConfigureArg "--with-milestone=" "adoptopenjdk"

    # Set the update version (e.g. 131), this gets passed in from the calling script
    addConfigureArgIfValueIsNotEmpty "--with-update-version=" "${OPENJDK_UPDATE_VERSION}"

    # Set the build number (e.g. b04), this gets passed in from the calling script
    addConfigureArgIfValueIsNotEmpty "--with-build-number=" "${OPENJDK_BUILD_NUMBER}"
  else
    if [ -z "$OPENJDK_REPO_TAG" ]; then
      cd "${WORKING_DIR}/${OPENJDK_REPO_NAME}" || echo Cannot change to "${WORKING_DIR}/${OPENJDK_REPO_NAME}"
      OPENJDK_REPO_TAG=$(getFirstTagFromOpenJDKGitRepo)
      echo "OpenJDK repo tag is ${OPENJDK_REPO_TAG}"
    fi
    # > JDK 8
    addConfigureArg "--with-version-pre=" "adoptopenjdk"

    TRIMMED_TAG=$(echo "$OPENJDK_REPO_TAG" | cut -f2 -d"-")
    addConfigureArg "--with-version-string=" "${TRIMMED_TAG}"

  fi
  echo "Completed configuring the version string parameter, config args are now: ${CONFIGURE_ARGS}"
}

buildingTheRestOfTheConfigParameters()
{
  if [ ! -z "$(which ccache)" ]; then
    addConfigureArg "--enable-ccache" ""
  fi

  addConfigureArgIfValueIsNotEmpty "--with-jvm-variants=" "${JVM_VARIANT}"
  addConfigureArgIfValueIsNotEmpty "--with-cacerts-file=" "${WORKING_DIR}/cacerts_area/security/cacerts"
  addConfigureArg "--with-alsa=" "${WORKING_DIR}/alsa-lib-${ALSA_LIB_VERSION}"

  # Point-in-time dependency for openj9 only
  if [[ "${BUILD_VARIANT}" == "openj9" ]] ; then
    addConfigureArg "--with-freemarker-jar=" "${WORKING_DIR}/freemarker-${FREEMARKER_LIB_VERSION}/lib/freemarker.jar"
  fi

  if [[ -z "${FREETYPE}" ]] ; then
    FREETYPE_DIRECTORY=${FREETYPE_DIRECTORY:-"${WORKING_DIR}/${OPENJDK_REPO_NAME}/installedfreetype"}
    addConfigureArg "--with-freetype=" "$FREETYPE_DIRECTORY"
  fi

  # These will have been installed by the package manager (see our Dockerfile)
  addConfigureArg "--with-x=" "/usr/include/X11"

  # We don't want any extra debug symbols - ensure it's set to release,
  # other options include fastdebug and slowdebug
  addConfigureArg "--with-debug-level=" "release"
}

configureCommandParameters()
{
  configuringVersionStringParameter
  if [[ "$OSTYPE" == "cygwin" ]] || [[ "$OSTYPE" == "msys" ]] ; then
    echo "Windows or Windows-like environment detected, skipping configuring environment for custom Boot JDK and other 'configure' settings."

  else
    echo "Building up the configure command..."
    configuringBootJDKConfigureParameter
    buildingTheRestOfTheConfigParameters
  fi

  #Now we add any configure arguments the user has specified on the command line.
  CONFIGURE_ARGS="${CONFIGURE_ARGS} ${USER_SUPPLIED_CONFIGURE_ARGS}"

  echo "Completed configuring the version string parameter, config args are now: ${CONFIGURE_ARGS}"
}

stepIntoTheWorkingDirectory()
{
  # Make sure we're in the source directory for OpenJDK now
  cd "$WORKING_DIR/$OPENJDK_REPO_NAME"  || exit
  echo "Should have the source, I'm at $PWD"
}

runTheOpenJDKConfigureCommandAndUseThePrebuiltConfigParams()
{
  echo "Configuring command and using the pre-built config params..."

  cd "$OPENJDK_DIR" || exit

  echo "Currently at '${PWD}'"

  CONFIGURED_OPENJDK_ALREADY=$(find . -name "config.status")

  if [[ ! -z "$CONFIGURED_OPENJDK_ALREADY" ]] ; then
    echo "Not reconfiguring due to the presence of config.status in ${WORKING_DIR}"
  else
    CONFIGURE_ARGS="${CONFIGURE_ARGS} ${CONFIGURE_ARGS_FOR_ANY_PLATFORM}"

    echo "Running ./configure with arguments '${CONFIGURE_ARGS}'"
    # Depends upon the configure command being split for multiple args.  Don't quote it.
    # shellcheck disable=SC2086
    bash ./configure ${CONFIGURE_ARGS}

    # shellcheck disable=SC2181
    if [ $? -ne 0 ]; then
      echo "${error}"
      echo "Failed to configure the JDK, exiting"
      echo "Did you set the JDK boot directory correctly? Override by exporting JDK_BOOT_DIR"
      echo "For example, on RHEL you would do export JDK_BOOT_DIR=/usr/lib/jvm/java-1.7.0-openjdk-1.7.0.131-2.6.9.0.el7_3.x86_64"
      echo "Current JDK_BOOT_DIR value: ${JDK_BOOT_DIR}"
      exit;
    else
      echo "${good}Configured the JDK"
    fi
    echo "${normal}"
  fi
}

buildOpenJDK()
{
  cd "$OPENJDK_DIR" || exit

  #If the user has specified nobuild, we do everything short of building the JDK, and then we stop.
  if [ "${RUN_JTREG_TESTS_ONLY}" == "--run-jtreg-tests-only" ]; then
    rm -rf cacerts_area
    echo "Nobuild option was set. Prep complete. Java not built."
    exit 0
  fi

  # If it's Java 9+ then we also make test-image to build the native test libraries
  JDK_PREFIX="jdk"
  JDK_VERSION_NUMBER="${OPENJDK_CORE_VERSION#$JDK_PREFIX}"
  if [ "$JDK_VERSION_NUMBER" -gt 8 ]; then
    MAKE_TEST_IMAGE=" test-image" # the added white space is deliberate as it's the last arg
  fi

  FULL_MAKE_COMMAND="${MAKE_COMMAND_NAME} ${MAKE_ARGS_FOR_ANY_PLATFORM} ${MAKE_TEST_IMAGE}"
  echo "Building the JDK: calling '${FULL_MAKE_COMMAND}'"

  if ! ${FULL_MAKE_COMMAND}; then
    echo "${error}Failed to make the JDK, exiting"
    exit 1;
  else
    echo "${good}Built the JDK!"
  fi
  echo "${normal}"
}

printJavaVersionString()
{
  # shellcheck disable=SC2086
  PRODUCT_HOME=$(ls -d $OPENJDK_DIR/build/*/images/${JDK_PATH})
  if [[ -d "$PRODUCT_HOME" ]]; then
     echo "${good}'$PRODUCT_HOME' found${normal}"
     # shellcheck disable=SC2154
     echo "${info}"
     if ! "$PRODUCT_HOME"/bin/java -version; then
       echo "${error} Error executing 'java' does not exist in '$PRODUCT_HOME'.${normal}"
       exit -1
     fi
     echo "${normal}"
     echo ""
  else
    echo "${error}'$PRODUCT_HOME' does not exist, build might have not been successful or not produced the expected JDK image at this location.${normal}"
    exit -1
  fi
}

removingUnnecessaryFiles()
{
  echo "Removing unnecessary files now..."

  echo "Fetching the first tag from the OpenJDK git repo..."
  if [ -z "$OPENJDK_REPO_TAG" ]; then
    OPENJDK_REPO_TAG=$(getFirstTagFromOpenJDKGitRepo)
  fi
  if [ "$USE_DOCKER" != "true" ] ; then
    rm -rf cacerts_area
  fi

  cd "${WORKING_DIR}/${OPENJDK_REPO_NAME}" || return

  cd build/*/images || return

  echo "Currently at '${PWD}'"

  echo "moving ${JDK_PATH} to ${OPENJDK_REPO_TAG}"
  rm -rf "${OPENJDK_REPO_TAG}" || true
  mv "$JDK_PATH" "${OPENJDK_REPO_TAG}"

  JRE_TARGET_PATH="${OPENJDK_REPO_TAG/jdk/jre}"
  [ "${JRE_TARGET_PATH}" == "${OPENJDK_REPO_TAG}" ] && JRE_TARGET_PATH="${OPENJDK_REPO_TAG}.jre"
  echo "moving ${JRE_PATH} to ${JRE_TARGET_PATH}"
  rm -rf "${JRE_TARGET_PATH}" || true
  mv "$JRE_PATH" "${JRE_TARGET_PATH}"

  # Remove files we don't need
  rm -rf "${OPENJDK_REPO_TAG}"/demo/applets || true
  rm -rf "${OPENJDK_REPO_TAG}"/demo/jfc/Font2DTest || true
  rm -rf "${OPENJDK_REPO_TAG}"/demo/jfc/SwingApplet || true
  rm -rf "${JRE_TARGET_PATH}"/demo/applets || true
  rm -rf "${JRE_TARGET_PATH}"/demo/jfc/Font2DTest || true
  rm -rf "${JRE_TARGET_PATH}"/demo/jfc/SwingApplet || true
  find . -name "*.diz" -type f -delete || true

  echo "Finished removing unnecessary files from ${OPENJDK_REPO_TAG} and ${JRE_TARGET_PATH}"
}

makeACopyOfLibFreeFontForMacOSX() {
    IMAGE_DIRECTORY=$1
    PERFORM_COPYING=$2

    if [[ "$OS_KERNEL_NAME" == "darwin" ]]; then
        echo "PERFORM_COPYING=${PERFORM_COPYING}"
        if [ "${PERFORM_COPYING}" == "false" ]; then
            echo "${info} Skipping copying of the free font library to ${IMAGE_DIRECTORY}, does not apply for this version of the JDK. ${normal}"
            return
        fi

       echo "${info} Performing copying of the free font library to ${IMAGE_DIRECTORY}, applicable for this version of the JDK. ${normal}"
        SOURCE_LIB_NAME="${IMAGE_DIRECTORY}/lib/libfreetype.dylib.6"
        if [ ! -f "${SOURCE_LIB_NAME}" ]; then
            echo "${error}[Error] ${SOURCE_LIB_NAME} does not exist in the ${IMAGE_DIRECTORY} folder, please check if this is the right folder to refer to, aborting copy process...${normal}"
            exit -1
        fi
        TARGET_LIB_NAME="${IMAGE_DIRECTORY}/lib/libfreetype.6.dylib"

        INVOKED_BY_FONT_MANAGER="${IMAGE_DIRECTORY}/lib/libfontmanager.dylib"

        echo "Currently at '${PWD}'"
        echo "Copying ${SOURCE_LIB_NAME} to ${TARGET_LIB_NAME}"
        echo " *** Workaround to fix the MacOSX issue where invocation to ${INVOKED_BY_FONT_MANAGER} fails to find ${TARGET_LIB_NAME} ***"

        set -x
        cp "${SOURCE_LIB_NAME}" "${TARGET_LIB_NAME}"
        if [ -f "${INVOKED_BY_FONT_MANAGER}" ]; then
            otool -L "${INVOKED_BY_FONT_MANAGER}"
        else
            # shellcheck disable=SC2154
            echo "${warning}[Warning] ${INVOKED_BY_FONT_MANAGER} does not exist in the ${IMAGE_DIRECTORY} folder, please check if this is the right folder to refer to, this may cause runtime issues, please beware...${normal}"
        fi

        otool -L "${TARGET_LIB_NAME}"
        set +x

        echo "Finished copying ${SOURCE_LIB_NAME} to ${TARGET_LIB_NAME}"
    fi
}

signRelease()
{
  if [ "$SIGN" ]; then
    case "$OSTYPE" in
      "cygwin")
        echo "Signing Windows release"
        signToolPath=${signToolPath:-"/cygdrive/c/Program Files/Microsoft SDKs/Windows/v7.1/Bin/signtool.exe"}
        # Sign .exe files
        FILES=$(find "${OPENJDK_REPO_TAG}" "${JRE_TARGET_PATH}" -type f -name '*.exe')
        echo "$FILES" | while read -r f; do "$signToolPath" sign /f "$CERTIFICATE" /p "$SIGN_PASSWORD" /fd SHA256 /t http://timestamp.verisign.com/scripts/timstamp.dll "$f"; done
        # Sign .dll files
        FILES=$(find "${OPENJDK_REPO_TAG}" "${JRE_TARGET_PATH}" -type f -name '*.dll')
        echo "$FILES" | while read -r f; do "$signToolPath" sign /f "$CERTIFICATE" /p "$SIGN_PASSWORD" /fd SHA256 /t http://timestamp.verisign.com/scripts/timstamp.dll "$f"; done
      ;;
      "darwin"*)
        echo "Signing OSX release"
        # Login to KeyChain
        # shellcheck disable=SC2046
        # shellcheck disable=SC2006
        security unlock-keychain -p `cat ~/.password`
        # Sign all files with the executable permission bit set.
        FILES=$(find "${OPENJDK_REPO_TAG}" "${JRE_TARGET_PATH}" ! -perm +111 -type f || find "${OPENJDK_REPO_TAG}" -perm /111 -type f)
        echo "$FILES" | while read -r f; do codesign -s "$CERTIFICATE" "$f"; done
      ;;
      *)
        echo "Skipping code signing as it's not supported on $OSTYPE"
      ;;
    esac
  fi
}

createOpenJDKTarArchive()
{
  COMPRESS=gzip
  if which pigz >/dev/null 2>&1; then COMPRESS=pigz; fi
  echo "Archiving the build OpenJDK image and compressing with $COMPRESS"

  if [ -z "$OPENJDK_REPO_TAG" ]; then
    OPENJDK_REPO_TAG=$(getFirstTagFromOpenJDKGitRepo)
  fi
  if [ -z "$JRE_TARGET_PATH" ]; then
    JRE_TARGET_PATH="${OPENJDK_REPO_TAG/jdk/jre}"
    [ "${JRE_TARGET_PATH}" == "${OPENJDK_REPO_TAG}" ] && JRE_TARGET_PATH="${OPENJDK_REPO_TAG}.jre"
  fi
  
  echo "OpenJDK repo tag is ${OPENJDK_REPO_TAG}. JRE path will be ${JRE_TARGET_PATH}"

  if [ "$USE_DOCKER" == "true" ] ; then
    GZIP=-9 tar --use-compress-program=$COMPRESS -cf OpenJDK.tar.gz ./"${OPENJDK_REPO_TAG}"
    GZIP=-9 tar --use-compress-program=$COMPRESS -cf OpenJRE.tar.gz ./"${JRE_TARGET_PATH}"
    EXT=".tar.gz"

    echo "${good}Moving the artifact to ${TARGET_DIR}${normal}"
    mv "OpenJDK${EXT}" "${TARGET_DIR}"
    mv "OpenJRE${EXT}" "${TARGET_DIR}"
  else
    case "${OS_KERNEL_NAME}" in
      *cygwin*)
        zip -r -q OpenJDK.zip ./"${OPENJDK_REPO_TAG}"
        zip -r -q OpenJRE.zip ./"${JRE_TARGET_PATH}"
      EXT=".zip" ;;
      aix)
        GZIP=-9 tar -cf - ./"${OPENJDK_REPO_TAG}"/ | $COMPRESS -c > OpenJDK.tar.gz
        GZIP=-9 tar -cf - ./"${JRE_TARGET_PATH}"/ | $COMPRESS -c > OpenJRE.tar.gz
      EXT=".tar.gz" ;;
      *)
        GZIP=-9 tar --use-compress-program=$COMPRESS -cf OpenJDK.tar.gz ./"${OPENJDK_REPO_TAG}"
        GZIP=-9 tar --use-compress-program=$COMPRESS -cf OpenJRE.tar.gz ./"${JRE_TARGET_PATH}"
      EXT=".tar.gz" ;;
    esac
    echo "${good}Your final ${EXT} was created at ${PWD}${normal}"
    ls -l 
    echo "${good}Moving the artifacts to ${TARGET_DIR}${normal}"
    # This really ought to be a separate parameter to makejdk_any_platform or
    # TARGET_DIR should be a dir name as the name suggests, not a full filename
    # This is currnently assuming TARGET_DIT has JDK in the filename, otherwise
    # it wiill get overridden
    mv "OpenJRE${EXT}" "${TARGET_DIR/JDK/JRE}"
    mv "OpenJDK${EXT}" "${TARGET_DIR}"
  fi

}

showCompletionMessage()
{
  echo "All done!"
}

sourceFileWithColourCodes
checkIfDockerIsUsedForBuildingOrNot
createWorkingDirectory
downloadingRequiredDependencies # This function is in common-functions.sh
configureCommandParameters
stepIntoTheWorkingDirectory
runTheOpenJDKConfigureCommandAndUseThePrebuiltConfigParams
buildOpenJDK
printJavaVersionString
removingUnnecessaryFiles
makeACopyOfLibFreeFontForMacOSX "${OPENJDK_REPO_TAG}" "${COPY_MACOSX_FREE_FONT_LIB_FOR_JDK_FLAG}"
makeACopyOfLibFreeFontForMacOSX "${JRE_PATH}" "${COPY_MACOSX_FREE_FONT_LIB_FOR_JRE_FLAG}"
signRelease
createOpenJDKTarArchive
showCompletionMessage
