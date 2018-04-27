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

set -eux

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# shellcheck source=sbin/common-functions.sh
source "$SCRIPT_DIR/colour-codes.sh"
source "$SCRIPT_DIR/common-functions.sh"
source "$SCRIPT_DIR/prepareWorkspace.sh"

source $SCRIPT_DIR/config_init.sh

export OPENJDK_REPO_TAG
export OPENJDK_DIR
export CONFIGURE_ARGS=""
export RUN_JTREG_TESTS_ONLY=""
export MAKE_TEST_IMAGE=""
export GIT_CLONE_ARGUMENTS="";

function parseArguments() {
    # TODO: can change all this to config file
    while [[ $# -gt 0 ]] && [[ ."$1" = .-* ]] ; do
      opt="$1";
      shift;
      case "$opt" in
        "--" ) break 2;;

        "--source" | "-s" )
        BUILD_CONFIG[WORKING_DIR]="$1"; shift;;

        "--sign" | "-S" )
        BUILD_CONFIG[SIGN]="true";;

        "--destination" | "-d" )
        BUILD_CONFIG[TARGET_DIR]="$1"; shift;;

        "--repository" | "-r" )
        BUILD_CONFIG[OPENJDK_SOURCE_DIR]="$1"; shift;;

        "--variant"  | "-jv" )
        BUILD_CONFIG[JVM_VARIANT]="$1"; shift;;

        "--update-version"  | "-uv" )
        BUILD_CONFIG[OPENJDK_UPDATE_VERSION]="$1"; shift;;

        "--build-number"  | "-bn" )
        BUILD_CONFIG[OPENJDK_BUILD_NUMBER]="$1"; shift;;

        "--repository-tag"  | "-rt" )
        OPENJDK_REPO_TAG="$1"; shift;;

        "--configure-args"  | "-ca" )
        BUILD_CONFIG[USER_SUPPLIED_CONFIGURE_ARGS]="$1"; shift;;

        *) echo >&2 "${error}Invalid build.sh option: ${opt}${normal}"; exit 1;;
      esac
    done

    OPENJDK_DIR="${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[WORKING_DIR]}/${BUILD_CONFIG[OPENJDK_SOURCE_DIR]}"

    if [ "${BUILD_CONFIG[JVM_VARIANT]}" == "--run-jtreg-tests-only" ]; then
      RUN_JTREG_TESTS_ONLY="--run-jtreg-tests-only"
      BUILD_CONFIG[JVM_VARIANT]="server"
    fi

    echo "JDK Image folder name: ${BUILD_CONFIG[JDK_PATH]}"
    echo "JRE Image folder name: ${BUILD_CONFIG[JRE_PATH]}"
    echo "[debug] COPY_MACOSX_FREE_FONT_LIB_FOR_JDK_FLAG=${BUILD_CONFIG[COPY_MACOSX_FREE_FONT_LIB_FOR_JDK_FLAG]}"
    echo "[debug] COPY_MACOSX_FREE_FONT_LIB_FOR_JRE_FLAG=${BUILD_CONFIG[COPY_MACOSX_FREE_FONT_LIB_FOR_JRE_FLAG]}"

    BUILD_CONFIG[MAKE_ARGS_FOR_ANY_PLATFORM]=${BUILD_CONFIG[MAKE_ARGS_FOR_ANY_PLATFORM]:-"images"}
    # Defaults to not building this target, for Java 9+ we set this to test-image in order to build the native test libraries

    BUILD_CONFIG[CONFIGURE_ARGS_FOR_ANY_PLATFORM]=${BUILD_CONFIG[CONFIGURE_ARGS_FOR_ANY_PLATFORM]:-""}
}


addConfigureArg()
{
  #Only add an arg if it is not overridden by a user-specified arg.
  if [[ ${BUILD_CONFIG[CONFIGURE_ARGS_FOR_ANY_PLATFORM]} != *"$1"* ]] && [[ ${BUILD_CONFIG[USER_SUPPLIED_CONFIGURE_ARGS]} != *"$1"* ]]; then
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
  if [[ "${BUILD_CONFIG[COLOUR]}" == "true" ]] ; then
    # shellcheck disable=SC1091
    source ./sbin/colour-codes.sh
  fi
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

getOpenJDKUpdateAndBuildVersion()
{
  cd "${BUILD_CONFIG[WORKING_DIR]}"

  if [ -d "${BUILD_CONFIG[OPENJDK_SOURCE_DIR]}/.git" ]; then

    # It does exist and it's a repo other than the AdoptOpenJDK one
    cd "${BUILD_CONFIG[OPENJDK_SOURCE_DIR]}" || return
    echo "${git}Pulling latest tags and getting the latest update version using git fetch -q --tags ${BUILD_CONFIG[SHALLOW_CLONE_OPTION]}${normal}"
    echo "${info}NOTE: This can take quite some time!  Please be patient"
    git fetch -q --tags "${BUILD_CONFIG[SHALLOW_CLONE_OPTION]}"
    OPENJDK_REPO_TAG=${BUILD_CONFIG[TAG]:-$(getFirstTagFromOpenJDKGitRepo)} # getFirstTagFromOpenJDKGitRepo resides in sbin/common-functions.sh
    if [[ "${OPENJDK_REPO_TAG}" == "" ]] ; then
     echo "${error}Unable to detect git tag, exiting...${normal}"
     exit 1
    else
     echo "OpenJDK repo tag is $OPENJDK_REPO_TAG"
    fi

    local openjdk_update_version=$(echo "${OPENJDK_REPO_TAG}" | cut -d'u' -f 2 | cut -d'-' -f 1)

    # TODO dont modify config in build script
    BUILD_CONFIG[OPENJDK_BUILD_NUMBER]=$(echo "${OPENJDK_REPO_TAG}" | cut -d'b' -f 2 | cut -d'-' -f 1)
    echo "Version: ${BUILD_CONFIG[openjdk_update_version]} ${BUILD_CONFIG[OPENJDK_BUILD_NUMBER]}"
  fi

  cd "${BUILD_CONFIG[WORKSPACE_DIR]}"

  echo "${normal}"
}

# Ensure that we produce builds with versions strings something like:
#
# openjdk version "1.8.0_131"
# OpenJDK Runtime Environment (build 1.8.0-adoptopenjdk-<user>_2017_04_17_17_21-b00)
# OpenJDK 64-Bit Server VM (build 25.71-b00, mixed mode)
configuringVersionStringParameter()
{
  if [ "${BUILD_CONFIG[OPENJDK_CORE_VERSION]}" == "jdk8" ]; then
    # Replace the default 'internal' with our own milestone string
    addConfigureArg "--with-milestone=" "adoptopenjdk"

    # Set the update version (e.g. 131), this gets passed in from the calling script
    addConfigureArgIfValueIsNotEmpty "--with-update-version=" "${BUILD_CONFIG[OPENJDK_UPDATE_VERSION]}"

    # Set the build number (e.g. b04), this gets passed in from the calling script
    addConfigureArgIfValueIsNotEmpty "--with-build-number=" "${BUILD_CONFIG[OPENJDK_BUILD_NUMBER]}"
  else
    if [ -z "$OPENJDK_REPO_TAG" ]; then
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

  addConfigureArgIfValueIsNotEmpty "--with-jvm-variants=" "${BUILD_CONFIG[JVM_VARIANT]}"
  addConfigureArgIfValueIsNotEmpty "--with-cacerts-file=" "${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[WORKING_DIR]}/cacerts_area/security/cacerts"
  addConfigureArg "--with-alsa=" "${BUILD_CONFIG[WORKING_DIR]}/alsa-lib-${ALSA_LIB_VERSION}"


  # Point-in-time dependency for openj9 only
  if [[ "${BUILD_CONFIG[BUILD_VARIANT]}" == "openj9" ]] ; then
    addConfigureArg "--with-freemarker-jar=" "${BUILD_CONFIG[WORKING_DIR]}/freemarker-${FREEMARKER_LIB_VERSION}/lib/freemarker.jar"
  fi

  if [[ "${BUILD_CONFIG[FREETYPE]}" == "true" ]] ; then
    BUILD_CONFIG[FREETYPE_DIRECTORY]=${BUILD_CONFIG[FREETYPE_DIRECTORY]:-"${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[WORKING_DIR]}/${BUILD_CONFIG[OPENJDK_SOURCE_DIR]}/installedfreetype"}
    addConfigureArg "--with-freetype=" "${BUILD_CONFIG[FREETYPE_DIRECTORY]}"
  fi

  # These will have been installed by the package manager (see our Dockerfile)
  addConfigureArg "--with-x=" "/usr/include/X11"

  # We don't want any extra debug symbols - ensure it's set to release,
  # other options include fastdebug and slowdebug
  addConfigureArg "--with-debug-level=" "release"
  addConfigureArg "--disable-zip-debug-info" ""
  addConfigureArg "--disable-debug-symbols" ""
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
  CONFIGURE_ARGS="${CONFIGURE_ARGS} ${BUILD_CONFIG[USER_SUPPLIED_CONFIGURE_ARGS]}"

  echo "Completed configuring the version string parameter, config args are now: ${CONFIGURE_ARGS}"
}

stepIntoTheWorkingDirectory() {
  # Make sure we're in the source directory for OpenJDK now
  cd "${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[WORKING_DIR]}/${BUILD_CONFIG[OPENJDK_SOURCE_DIR]}"  || exit
  echo "Should have the source, I'm at $PWD"
}

runTheOpenJDKConfigureCommandAndUseThePrebuiltConfigParams()
{
  echo "Configuring command and using the pre-built config params..."

  stepIntoTheWorkingDirectory

  echo "Currently at '${PWD}'"

  CONFIGURED_OPENJDK_ALREADY=$(find . -name "config.status")

  if [[ ! -z "$CONFIGURED_OPENJDK_ALREADY" ]] ; then
    echo "Not reconfiguring due to the presence of config.status in ${BUILD_CONFIG[WORKING_DIR]}"
  else
    CONFIGURE_ARGS="${CONFIGURE_ARGS} ${BUILD_CONFIG[CONFIGURE_ARGS_FOR_ANY_PLATFORM]}"

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
  stepIntoTheWorkingDirectory

  #If the user has specified nobuild, we do everything short of building the JDK, and then we stop.
  if [ "${RUN_JTREG_TESTS_ONLY}" == "--run-jtreg-tests-only" ]; then
    rm -rf cacerts_area
    echo "Nobuild option was set. Prep complete. Java not built."
    exit 0
  fi

  # If it's Java 9+ then we also make test-image to build the native test libraries
  JDK_PREFIX="jdk"
  JDK_VERSION_NUMBER="${BUILD_CONFIG[OPENJDK_CORE_VERSION]#$JDK_PREFIX}"
  if [ "$JDK_VERSION_NUMBER" -gt 8 ]; then
    MAKE_TEST_IMAGE=" test-image" # the added white space is deliberate as it's the last arg
  fi

  FULL_MAKE_COMMAND="${BUILD_CONFIG[MAKE_COMMAND_NAME]} ${BUILD_CONFIG[MAKE_ARGS_FOR_ANY_PLATFORM]} ${MAKE_TEST_IMAGE}"
  echo "Building the JDK: calling '${FULL_MAKE_COMMAND}'"
  exitCode=$(${FULL_MAKE_COMMAND})

  # shellcheck disable=SC2181
  if [ "${exitCode}" -ne 0 ]; then
     echo "${error}Failed to make the JDK, exiting"
    exit;
  else
    echo "${good}Built the JDK!"
  fi
  echo "${normal}"
}

printJavaVersionString()
{
  # shellcheck disable=SC2086
  PRODUCT_HOME=$(ls -d $OPENJDK_DIR/build/*/images/${BUILD_CONFIG[JDK_PATH]})
  if [[ -d "$PRODUCT_HOME" ]]; then
     echo "${good}'$PRODUCT_HOME' found${normal}"
     # shellcheck disable=SC2154
     echo "${info}"
     "$PRODUCT_HOME"/bin/java -version || (echo "${error} Error executing 'java' does not exist in '$PRODUCT_HOME'.${normal}" && exit -1)
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

  # Remove files we don't need
  rm -rf "${OPENJDK_REPO_TAG}"/demo/applets || true
  rm -rf "${OPENJDK_REPO_TAG}"/demo/jfc/Font2DTest || true
  rm -rf "${OPENJDK_REPO_TAG}"/demo/jfc/SwingApplet || true
  find . -name "*.diz" -type f -delete || true

  echo "Finished removing unnecessary files from ${OPENJDK_REPO_TAG}"
}

makeACopyOfLibFreeFontForMacOSX() {
    IMAGE_DIRECTORY=$1
    PERFORM_COPYING=$2

    if [[ "${BUILD_CONFIG[OS_KERNEL_NAME]}" == "darwin" ]]; then
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

        cp "${SOURCE_LIB_NAME}" "${TARGET_LIB_NAME}"
        if [ -f "${INVOKED_BY_FONT_MANAGER}" ]; then
            otool -L "${INVOKED_BY_FONT_MANAGER}"
        else
            # shellcheck disable=SC2154
            echo "${warning}[Warning] ${INVOKED_BY_FONT_MANAGER} does not exist in the ${IMAGE_DIRECTORY} folder, please check if this is the right folder to refer to, this may cause runtime issues, please beware...${normal}"
        fi

        otool -L "${TARGET_LIB_NAME}"

        echo "Finished copying ${SOURCE_LIB_NAME} to ${TARGET_LIB_NAME}"
    fi
}

signRelease()
{
  if [ -z "${BUILD_CONFIG[SIGN]}" ]; then
    if [[ "$OSTYPE" == "cygwin" ]]; then
      echo "Signing release"
      signToolPath=${signToolPath:-"/cygdrive/c/Program Files/Microsoft SDKs/Windows/v7.1/Bin/signtool.exe"}
      # Sign .exe files
      FILES=$(find "${OPENJDK_REPO_TAG}" -type f -name '*.exe')
      for f in $FILES; do
        "$signToolPath" sign /f "$CERTIFICATE" /p "$SIGN_PASSWORD" /fd SHA256 /t http://timestamp.verisign.com/scripts/timstamp.dll "$f"
      done
      # Sign .dll files
      FILES=$(find "${OPENJDK_REPO_TAG}" -type f -name '*.dll')
      for f in $FILES; do
        "$signToolPath" sign /f "$CERTIFICATE" /p "$SIGN_PASSWORD" /fd SHA256 /t http://timestamp.verisign.com/scripts/timstamp.dll "$f"
      done
    else
      echo "Skiping code signing as it's only supported on Windows"
    fi
  fi
}

createOpenJDKTarArchive()
{
  echo "Archiving the build OpenJDK image..."

  if [ -z "$OPENJDK_REPO_TAG" ]; then
    OPENJDK_REPO_TAG=$(getFirstTagFromOpenJDKGitRepo)
  fi
  echo "OpenJDK repo tag is ${OPENJDK_REPO_TAG}"

  if [ "${BUILD_CONFIG[USE_DOCKER]}" == "true" ] ; then
     GZIP=-9 tar -czf OpenJDK.tar.gz ./"${OPENJDK_REPO_TAG}"
     EXT=".tar.gz"

     echo "${good}Moving the artifact to ${BUILD_CONFIG[TARGET_DIR]}${normal}"
     mv "OpenJDK${EXT}" "${BUILD_CONFIG[TARGET_DIR]}"
  else
      case "${OS_KERNEL_NAME}" in
        *cygwin*)
          zip -r -q OpenJDK.zip ./"${OPENJDK_REPO_TAG}"
          EXT=".zip" ;;
        aix)
          GZIP=-9 tar -cf - ./"${OPENJDK_REPO_TAG}"/ | gzip -c > OpenJDK.tar.gz
          EXT=".tar.gz" ;;
        *)
          GZIP=-9 tar -czf OpenJDK.tar.gz ./"${OPENJDK_REPO_TAG}"
          EXT=".tar.gz" ;;
      esac
      echo "${good}Your final ${EXT} was created at ${PWD}${normal}"

      echo "${good}Moving the artifact to ${BUILD_CONFIG[TARGET_DIR]}${normal}"
      mv "OpenJDK${EXT}" "${BUILD_CONFIG[TARGET_DIR]}"
  fi

}

showCompletionMessage()
{
  echo "All done!"
}


loadConfigFromFile

cd "${BUILD_CONFIG[WORKSPACE_DIR]}"

sourceFileWithColourCodes

parseArguments "$@"
configureWorkspace

getOpenJDKUpdateAndBuildVersion
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
