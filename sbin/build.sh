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

WORKING_DIR=$1
TARGET_DIR=$2
OPENJDK_REPO_NAME=$3
JVM_VARIANT=${4:-server}
OPENJDK_UPDATE_VERSION=$5
OPENJDK_BUILD_NUMBER=$6
OPENJDK_DIR=$WORKING_DIR/$OPENJDK_REPO_NAME

RUN_JTREG_TESTS_ONLY=""

if [ "$JVM_VARIANT" == "--run-jtreg-tests-only" ]; then
  RUN_JTREG_TESTS_ONLY="--run-jtreg-tests-only"
  JVM_VARIANT="server"
fi

MAKE_ARGS_FOR_ANY_PLATFORM=${MAKE_ARGS_FOR_ANY_PLATFORM:-"images"}
CONFIGURE_ARGS_FOR_ANY_PLATFORM=${CONFIGURE_ARGS_FOR_ANY_PLATFORM:-""}

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

  CONFIGURE_ARGS=" --with-boot-jdk=${JDK_BOOT_DIR}"
}

# Ensure that we produce builds with versions strings something like:
#
# openjdk version "1.8.0_131"
# OpenJDK Runtime Environment (build 1.8.0-adoptopenjdk-<user>_2017_04_17_17_21-b00)
# OpenJDK 64-Bit Server VM (build 25.71-b00, mixed mode)
configuringVersionStringParameter()
{
  # Replace the default 'internal' with our own milestone string
  CONFIGURE_ARGS="${CONFIGURE_ARGS} --with-milestone=adoptopenjdk"

  # Set the update version (e.g. 131), this gets passed in from the calling script
  CONFIGURE_ARGS="${CONFIGURE_ARGS} --with-update-version=${OPENJDK_UPDATE_VERSION}"

  # Set the build number (e.g. b04), this gets passed in from the calling script
  CONFIGURE_ARGS="${CONFIGURE_ARGS} --with-build-number=${OPENJDK_BUILD_NUMBER}"

  echo "Completed configuring the version string parameter, config args are now: ${CONFIGURE_ARGS}"
}

buildingTheRestOfTheConfigParameters()
{
  if [ ! -z "$(which ccache)" ]; then
    CONFIGURE_ARGS="${CONFIGURE_ARGS} --enable-ccache"
  fi

  CONFIGURE_ARGS="${CONFIGURE_ARGS} --with-jvm-variants=${JVM_VARIANT}"
  CONFIGURE_ARGS="${CONFIGURE_ARGS} --with-cacerts-file=${WORKING_DIR}/cacerts_area/security/cacerts"
  CONFIGURE_ARGS="${CONFIGURE_ARGS} --with-alsa=${WORKING_DIR}/alsa-lib-${ALSA_LIB_VERSION}"

  if [[ -z "${FREETYPE}" ]] ; then
    FREETYPE_DIRECTORY=${FREETYPE_DIRECTORY:-"${WORKING_DIR}/${OPENJDK_REPO_NAME}/installedfreetype"}
    CONFIGURE_ARGS="${CONFIGURE_ARGS} --with-freetype=$FREETYPE_DIRECTORY"
  fi

  # These will have been installed by the package manager (see our Dockerfile)
  CONFIGURE_ARGS="${CONFIGURE_ARGS} --with-x=/usr/include/X11"

  # We don't want any extra debug symbols - ensure it's set to release,
  # other options include fastdebug and slowdebug
  CONFIGURE_ARGS="${CONFIGURE_ARGS} --with-debug-level=release"
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
  cd "$OPENJDK_DIR" || exit
  CONFIGURED_OPENJDK_ALREADY=$(find -name "config.status")

  if [[ ! -z "$CONFIGURED_OPENJDK_ALREADY" ]] ; then
    echo "Not reconfiguring due to the presence of config.status in ${WORKING_DIR}"
  else
    CONFIGURE_ARGS="${CONFIGURE_ARGS} ${CONFIGURE_ARGS_FOR_ANY_PLATFORM}"

    echo "Running ./configure with arguments $CONFIGURE_ARGS"
    # Depends upon the configure command being split for multiple args.  Dont quote it.
    # shellcheck disable=SC2086
    bash ./configure $CONFIGURE_ARGS
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

  case "${OS_KERNEL_NAME}" in
    aix)
      makeCMD="gmake ${MAKE_ARGS_FOR_ANY_PLATFORM}" ;;
    *)
      makeCMD="make ${MAKE_ARGS_FOR_ANY_PLATFORM}" ;;
  esac

  echo "Building the JDK: calling ${makeCMD}"
  $makeCMD

  if [ $? -ne 0 ]; then
     echo "${error}Failed to make the JDK, exiting"
    exit;
  else
    echo "${good}Built the JDK!"
  fi
  echo "${normal}"
}

printJavaVersionString()
{
  PRODUCT_HOME=$(ls -d $OPENJDK_DIR/build/*/images/j2sdk-image)
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

  if [ "$USE_DOCKER" == "true" ] ; then
     cd build/*/images || return
  else
     rm -rf cacerts_area

     cd build/*/images || return

     mv j2sdk-image "${OPENJDK_REPO_TAG}"
  fi
  
  # Remove files we don't need
  rm -rf "${OPENJDK_REPO_TAG}"/demo/applets
  rm -rf "${OPENJDK_REPO_TAG}"/demo/jfc/Font2DTest
  rm -rf "${OPENJDK_REPO_TAG}"/demo/jfc/SwingApplet
  find . -name "*.diz" -type f -delete
}

createOpenJDKTarArchive()
{
  echo "Archiving the build OpenJDK image..."

  OPENJDK_REPO_TAG=$(getFirstGitTag)
  echo "OpenJDK repo tag is ${OPENJDK_REPO_TAG}"

  mv j2sdk-image ${OPENJDK_REPO_TAG}
  if [ "$USE_DOCKER" == "true" ] ; then
     GZIP=-9 tar -czf OpenJDK.tar.gz ./${OPENJDK_REPO_TAG}
     EXT=".tar.gz"

     echo "${good}Moving the artifact to ${TARGET_DIR}${normal}"
     mv "OpenJDK${EXT}" "${TARGET_DIR}"
  else
      case "${OS_KERNEL_NAME}" in
        *cygwin*)
          zip -r -q OpenJDK.zip ./"${OPENJDK_REPO_TAG}"
          EXT=".zip" ;;
        aix)
          GZIP=-9 tar -cf - ./${OPENJDK_REPO_TAG}/ | gzip -c > OpenJDK.tar.gz
          EXT=".tar.gz" ;;
        *)
          GZIP=-9 tar -czf OpenJDK.tar.gz ./"${OPENJDK_REPO_TAG}"
          EXT=".tar.gz" ;;
      esac
      echo "${good}Your final ${EXT} was created at ${PWD}${normal}"

      echo "${good}Moving the artifact to ${TARGET_DIR}${normal}"
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
createOpenJDKTarArchive
showCompletionMessage
