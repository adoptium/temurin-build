#!/bin/bash
# shellcheck disable=SC2153,SC2155

################################################################################
#
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
#
################################################################################

################################################################################
#
# This shell script deals with writing the Temurin build configuration to
# the file system so it can be picked up by further build steps, Docker
# containers etc
#
# We are deliberately writing to shell because this needs to work on some truly
# esoteric platforms to fulfil the Java Write Once Run Anywhere (WORA) promise.
#
################################################################################

# We can't use Bash 4.x+ associative arrays as as Apple won't support bash 4.0
# (because of GPL3), we therefore have to name the indexes of the CONFIG_PARAMS
# map. This is why we can't have nice things.
CONFIG_PARAMS=(
ADOPT_PATCHES
ASSEMBLE_EXPLODED_IMAGE
OPENJDK_BUILD_REPO_BRANCH
OPENJDK_BUILD_REPO_URI
BRANCH
BUILD_FULL_NAME
BUILD_REPRODUCIBLE_DATE
BUILD_TIMESTAMP
BUILD_VARIANT
CERTIFICATE
CLEAN_DOCKER_BUILD
CLEAN_GIT_REPO
CLEAN_LIBS
CONTAINER_NAME
COPY_MACOSX_FREE_FONT_LIB_FOR_JDK_FLAG
COPY_MACOSX_FREE_FONT_LIB_FOR_JRE_FLAG
COPY_TO_HOST
CREATE_DEBUG_IMAGE
CREATE_JRE_IMAGE
CREATE_SBOM
CREATE_SOURCE_ARCHIVE
CUSTOM_CACERTS
CROSSCOMPILE
DEBUG_DOCKER
DEBUG_IMAGE_PATH
DISABLE_ADOPT_BRANCH_SAFETY
DOCKER
DOCKER_FILE_PATH
DOCKER_SOURCE_VOLUME_NAME
FREETYPE
FREETYPE_DIRECTORY
FREETYPE_FONT_BUILD_TYPE_PARAM
FREETYPE_FONT_VERSION
GRADLE_USER_HOME_DIR
KEEP_CONTAINER
JDK_BOOT_DIR
JDK_PATH
JRE_PATH
TEST_IMAGE_PATH
STATIC_LIBS_IMAGE_PATH
JVM_VARIANT
MACOSX_CODESIGN_IDENTITY
MAKE_ARGS_FOR_ANY_PLATFORM
MAKE_EXPLODED
MAKE_COMMAND_NAME
NUM_PROCESSORS
OPENJDK_BUILD_NUMBER
OPENJDK_CORE_VERSION
OPENJDK_FEATURE_NUMBER
OPENJDK_FOREST_NAME
OPENJDK_SOURCE_DIR
OPENJDK_UPDATE_VERSION
OS_KERNEL_NAME
OS_FULL_VERSION
OS_ARCHITECTURE
PATCHES
RELEASE
REPOSITORY
REUSE_CONTAINER
SHALLOW_CLONE_OPTION
SIGN
TAG
TARGET_DIR
TARGET_FILE_NAME
TMP_CONTAINER_NAME
TMP_SPACE_BUILD
USE_DOCKER
USE_JEP319_CERTS
USE_SSH
USER_SUPPLIED_CONFIGURE_ARGS
USER_SUPPLIED_MAKE_ARGS
VENDOR
VENDOR_URL
VENDOR_BUG_URL
VENDOR_VERSION
VENDOR_VM_BUG_URL
WORKING_DIR
WORKSPACE_DIR
)

# Directory structure of build environment:
###########################################################################################################################################
#  Dir                                                 Purpose                              Docker Default            Native default
###########################################################################################################################################
#  <WORKSPACE_DIR>                                     Root                                 /openjdk/                   $(pwd)/workspace/
#  <WORKSPACE_DIR>/config                              Configuration                        /openjdk/config             $(pwd)/workspace/config
#  <WORKSPACE_DIR>/<WORKING_DIR>                       Build area                           /openjdk/build              $(pwd)/workspace/build/
#  <WORKSPACE_DIR>/<WORKING_DIR>/<OPENJDK_SOURCE_DIR>  Source code                          /openjdk/build/src          $(pwd)/workspace/build/src
#  <WORKSPACE_DIR>/target                              Destination of built artifacts       /openjdk/target             $(pwd)/workspace/target

# Helper code to perform index lookups by name
declare -a -x PARAM_LOOKUP
numParams=$((${#CONFIG_PARAMS[@]}))

# seq not available on aix
index=0
# shellcheck disable=SC2086
while [  $index -lt $numParams ]; do
    paramName=${CONFIG_PARAMS[$index]};
    eval declare -r -x "$paramName=$index"
    PARAM_LOOKUP[index]=$paramName

    # shellcheck disable=SC2219
    let index=index+1
done

function displayParams() {
    echo "# ============================"
    echo "# OPENJDK BUILD CONFIGURATION:"
    echo "# ============================"
    for K in "${!BUILD_CONFIG[@]}";
    do
      echo "BUILD_CONFIG[${PARAM_LOOKUP[$K]}]=\"${BUILD_CONFIG[$K]}\""
    done | sort
}

function writeConfigToFile() {
  if [ ! -d "workspace/config" ]
  then
    mkdir -p "workspace/config"
  fi
  displayParams | sed 's/\r$//' > ./workspace/config/built_config.cfg
}

function createConfigToJsonString() {
  jsonString="{ "
  for K in "${!BUILD_CONFIG[@]}";
  do
    jsonString+="\"${PARAM_LOOKUP[$K]}\" : \"${BUILD_CONFIG[$K]}\", "
  done
  jsonString+=" \"Data Source\" : \"BUILD_CONFIG hashmap\"}"
  echo "${jsonString}"
}

function loadConfigFromFile() {
  if [ -f "$SCRIPT_DIR/../config/built_config.cfg" ]
  then
    # shellcheck disable=SC1091,SC1090
    source "$SCRIPT_DIR/../config/built_config.cfg"
  elif [ -f "config/built_config.cfg" ]
  then
    # shellcheck disable=SC1091
    source config/built_config.cfg
  elif [ -f "workspace/config/built_config.cfg" ]
  then
    # shellcheck disable=SC1091
    source workspace/config/built_config.cfg
  elif [ -f "built_config.cfg" ]
  then
    # shellcheck disable=SC1091
    source built_config.cfg
  else
    echo "Failed to find configuration"
    exit
  fi
}

# Parse the configuration args from the CL, please keep this in alpha order
function parseConfigurationArguments() {

    while [[ $# -gt 0 ]] && [[ ."$1" = .-* ]] ; do
      opt="$1";
      shift;

      echo "Parsing opt: ${opt}"
      if [ -n "${1-}" ]
      then
        echo "Possible opt arg: $1"
      fi

      case "$opt" in
        "--" ) break 2;;

        "--openjdk-build-repo-branch" )
        BUILD_CONFIG[OPENJDK_BUILD_REPO_BRANCH]="$1"; shift;;

        "--openjdk-build-repo-uri" )
        BUILD_CONFIG[OPENJDK_BUILD_REPO_URI]="$1"; shift;;

        "--build-variant" )
        BUILD_CONFIG[BUILD_VARIANT]="$1"; shift;;

        "--build-reproducible-date" )
        BUILD_CONFIG[BUILD_REPRODUCIBLE_DATE]="$1"; shift;;

        "--branch" | "-b" )
        BUILD_CONFIG[BRANCH]="$1"; shift;;

        "--build-number"  | "-B" )
        BUILD_CONFIG[OPENJDK_BUILD_NUMBER]="$1"; shift;;

        "--configure-args"  | "-C" )
        BUILD_CONFIG[USER_SUPPLIED_CONFIGURE_ARGS]="$1"; shift;;

        "--make-args" )
        BUILD_CONFIG[USER_SUPPLIED_MAKE_ARGS]="$1"; shift;;

        "--make-exploded-image" )
        BUILD_CONFIG[MAKE_EXPLODED]=true;;

        "--assemble-exploded-image" )
        BUILD_CONFIG[ASSEMBLE_EXPLODED_IMAGE]=true;;

        "--custom-cacerts" )
        BUILD_CONFIG[CUSTOM_CACERTS]="$1"; shift;;

        "--codesign-identity" )
        BUILD_CONFIG[MACOSX_CODESIGN_IDENTITY]="$1"; shift;;

        "--clean-docker-build" | "-c" )
        BUILD_CONFIG[CLEAN_DOCKER_BUILD]=true;;

        "--clean-git-repo" )
        BUILD_CONFIG[CLEAN_GIT_REPO]=true;;

        "--clean-libs" )
        BUILD_CONFIG[CLEAN_LIBS]=true;;

        "--create-debug-image" )
        BUILD_CONFIG[CREATE_DEBUG_IMAGE]="true";;

        "--create-jre-image" )
        BUILD_CONFIG[CREATE_JRE_IMAGE]=true;;

        "--create-sbom" )
        BUILD_CONFIG[CREATE_SBOM]=true;;

        "--create-source-archive" )
        BUILD_CONFIG[CREATE_SOURCE_ARCHIVE]=true;;

        "--disable-adopt-branch-safety" )
        BUILD_CONFIG[DISABLE_ADOPT_BRANCH_SAFETY]=true;;

        "--destination" | "-d" )
        BUILD_CONFIG[TARGET_DIR]="$1"; shift;;

        "--docker" | "-D" )
        BUILD_CONFIG[USE_DOCKER]="true";;

        "--debug-docker" )
        BUILD_CONFIG[DEBUG_DOCKER]="true";;

        "--disable-shallow-git-clone" )
        BUILD_CONFIG[SHALLOW_CLONE_OPTION]="";;

        "--freetype-dir" | "-f" )
        BUILD_CONFIG[FREETYPE_DIRECTORY]="$1"; shift;;

        "--freetype-build-param" )
        BUILD_CONFIG[FREETYPE_FONT_BUILD_TYPE_PARAM]="$1"; shift;;

        "--freetype-version" )
        BUILD_CONFIG[FREETYPE_FONT_VERSION]="$1"; shift;;

        "--gradle-user-home-dir" )
        BUILD_CONFIG[GRADLE_USER_HOME_DIR]="$1"; shift;;

        "--skip-freetype" | "-F" )
        BUILD_CONFIG[FREETYPE]=false;;

        "--help" | "-h" )
        man ./makejdk-any-platform.1 && exit 0;;

        "--ignore-container" | "-i" )
        BUILD_CONFIG[REUSE_CONTAINER]=false;;

        "--jdk-boot-dir" | "-J" )
        BUILD_CONFIG[JDK_BOOT_DIR]="$1";shift;;

        "--cross-compile" )
        BUILD_CONFIG[CROSSCOMPILE]=true;;

        "--keep" | "-k" )
        BUILD_CONFIG[KEEP_CONTAINER]=true;;

        "--no-adopt-patches" )
        BUILD_CONFIG[ADOPT_PATCHES]=false;;

        "--patches" )
        BUILD_CONFIG[PATCHES]="$1"; shift;;

        "--processors" | "-p" )
        BUILD_CONFIG[NUM_PROCESSORS]="$1"; shift;;

        "--repository" | "-r" )
        BUILD_CONFIG[REPOSITORY]="$1"; shift;;

        "--release" )
        BUILD_CONFIG[RELEASE]=true; shift;;

        "--source" | "-s" )
        BUILD_CONFIG[WORKING_DIR]="$1"; shift;;

        "--ssh" | "-S" )
        BUILD_CONFIG[USE_SSH]=true;;

        # Signing is a separate step on the Temurin build farm itself
        # JIC you're wondering why you don't see this get set there.
        "--sign" )
        BUILD_CONFIG[SIGN]=true; BUILD_CONFIG[CERTIFICATE]="$1"; shift;;

        "--sudo" )
        BUILD_CONFIG[DOCKER]="sudo docker";;

        "--tag" | "-t" )
        BUILD_CONFIG[TAG]="$1"; BUILD_CONFIG[SHALLOW_CLONE_OPTION]=""; shift;;

        "--target-file-name"  | "-T" )
        BUILD_CONFIG[TARGET_FILE_NAME]="$1"; shift;;

        "--tmp-space-build")
        BUILD_CONFIG[TMP_SPACE_BUILD]=true;;

        "--update-version"  | "-u" )
        BUILD_CONFIG[OPENJDK_UPDATE_VERSION]="$1"; shift;;

        "--use-jep319-certs" )
        BUILD_CONFIG[USE_JEP319_CERTS]=true;;

        "--vendor" | "-ve" )
        BUILD_CONFIG[VENDOR]="$1"; shift;;

        "--vendor-url")
        BUILD_CONFIG[VENDOR_URL]="$1"; shift;;

        "--vendor-bug-url")
        BUILD_CONFIG[VENDOR_BUG_URL]="$1"; shift;;

        "--vendor-vm-bug-url")
        BUILD_CONFIG[VENDOR_VM_BUG_URL]="$1"; shift;;

        "--version"  | "-v" )
        setOpenJdkVersion "$1"
        setDockerVolumeSuffix "$1"; shift;;

        "--jvm-variant"  | "-V" )
        BUILD_CONFIG[JVM_VARIANT]="$1"; shift;;

        *) echo >&2 "Invalid build.sh option: ${opt}"; exit 1;;
      esac
    done

    setBranch
}

function setBranch() {

  # Which repo branch to build, e.g. dev by default for temurin, "openj9" for openj9
  local branch="master"
  if [ "${BUILD_CONFIG[BUILD_VARIANT]}" == "${BUILD_VARIANT_TEMURIN}" ]; then
    branch="dev"
  elif [ "${BUILD_CONFIG[BUILD_VARIANT]}" == "${BUILD_VARIANT_OPENJ9}" ]; then
    branch="openj9";
  elif [ "${BUILD_CONFIG[BUILD_VARIANT]}" == "${BUILD_VARIANT_DRAGONWELL}" ]; then
    branch="master";
  elif [ "${BUILD_CONFIG[BUILD_VARIANT]}" == "${BUILD_VARIANT_FAST_STARTUP}" ]; then
    branch="master";
  elif [ "${BUILD_CONFIG[BUILD_VARIANT]}" == "${BUILD_VARIANT_CORRETTO}" ]; then
    branch="develop";
  elif [ "${BUILD_CONFIG[BUILD_VARIANT]}" == "${BUILD_VARIANT_BISHENG}" ]; then
    if [ "${BUILD_CONFIG[OS_ARCHITECTURE]}" == "riscv64" ] ; then
      branch="risc-v"
    else
      branch="master"
    fi
  fi

  BUILD_CONFIG[BRANCH]=${BUILD_CONFIG[BRANCH]:-$branch}
}

# Set the config defaults
function configDefaults() {

  # The OS kernel name, e.g. 'darwin' for Mac OS X
  BUILD_CONFIG[OS_KERNEL_NAME]=$(uname | awk '{print tolower($0)}')

  # Determine OS full system version
  local unameSys=$(uname -s)
  local unameOSSysVer=$(uname -sr)
  local unameKernel=$(uname -r)
  if [ "${unameSys}" == "Linux" ]; then
    if [ -f "/etc/os-release" ]; then
      local unameFullOSVer=$(awk -F= '/^NAME=/{OS=$2}/^VERSION_ID=/{VER=$2}END{print OS " " VER}' /etc/os-release  | tr -d '"')
      unameOSSysVer="${unameFullOSVer} (Kernel: ${unameKernel})"
    elif [ -f "/etc/system-release" ]; then
      local linuxName=$(tr -d '"' < /etc/system-release)
      unameOSSysVer="${unameOSSysVer} : ${linuxName} (Kernel: ${unameKernel} )"
    else
      unameOSSysVer="${unameSys} : unameOSSysVer (Kernel: ${unameKernel} )"
    fi
  elif [ "${unameSys}" == "AIX" ]; then
    # AIX provides full version info using oslevel
    aixVer=$(oslevel -r)
    unameOSSysVer="${unameSys} ${aixVer}"
  fi

  # Store the OS full version name, eg.Darwin 20.4.0
  BUILD_CONFIG[OS_FULL_VERSION]="${unameOSSysVer}"

  local arch=$(uname -m)

  if [ "${BUILD_CONFIG[OS_KERNEL_NAME]}" == "aix" ]; then
    arch=$(uname -p | sed 's/powerpc/ppc/')
  fi

  BUILD_CONFIG[JDK_PATH]=""
  BUILD_CONFIG[JRE_PATH]=""

  # The default value defined for GRADLE_USER_HOME
  BUILD_CONFIG[GRADLE_USER_HOME_DIR]=""

  # The O/S architecture, e.g. x86_64 for a modern intel / Mac OS X
  BUILD_CONFIG[OS_ARCHITECTURE]=${arch}

  # The full forest name, e.g. jdk8, jdk8u, jdk9, jdk9u, etc.
  BUILD_CONFIG[OPENJDK_FOREST_NAME]=""

  # The abridged openjdk core version name, e.g. jdk8, jdk9, etc.
  BUILD_CONFIG[OPENJDK_CORE_VERSION]=""

  # The OpenJDK source code repository to build from, e.g. an Temurin repo
  BUILD_CONFIG[REPOSITORY]=""

  BUILD_CONFIG[ASSEMBLE_EXPLODED_IMAGE]=${BUILD_CONFIG[ASSEMBLE_EXPLODED_IMAGE]:-"false"}
  BUILD_CONFIG[MAKE_EXPLODED]=${BUILD_CONFIG[MAKE_EXPLODED]:-"false"}

  # The default adoptium/temurin-build repo branch
  BUILD_CONFIG[OPENJDK_BUILD_REPO_BRANCH]="master"

  # The default adoptium/temurin-build repo uri
  BUILD_CONFIG[OPENJDK_BUILD_REPO_URI]="https://github.com/adoptium/temurin-build.git"

  BUILD_CONFIG[COPY_MACOSX_FREE_FONT_LIB_FOR_JDK_FLAG]="false"
  BUILD_CONFIG[COPY_MACOSX_FREE_FONT_LIB_FOR_JRE_FLAG]="false"
  BUILD_CONFIG[FREETYPE]=true
  BUILD_CONFIG[FREETYPE_DIRECTORY]=""
  BUILD_CONFIG[FREETYPE_FONT_VERSION]="86bc8a95056c97a810986434a3f268cbe67f2902" # 2.9.1
  BUILD_CONFIG[FREETYPE_FONT_BUILD_TYPE_PARAM]=""

  case "${BUILD_CONFIG[OS_KERNEL_NAME]}" in
    aix | sunos | *bsd )
      BUILD_CONFIG[MAKE_COMMAND_NAME]="gmake"
      ;;
    * )
      BUILD_CONFIG[MAKE_COMMAND_NAME]="make"
      ;;
  esac

  # Default to no supplied reproducible build date, uses current date
  BUILD_CONFIG[BUILD_REPRODUCIBLE_DATE]=""

  # The default behavior of whether we want to create a separate debug symbols archive
  BUILD_CONFIG[CREATE_DEBUG_IMAGE]="false"

  # The default behavior of whether we want to create the legacy JRE
  BUILD_CONFIG[CREATE_JRE_IMAGE]="false"

  # Set default value to "false". We config buildArg per each config file to have it enabled by our pipeline
  BUILD_CONFIG[CREATE_SBOM]="false"

  # The default behavior of whether we want to create a separate source archive
  BUILD_CONFIG[CREATE_SOURCE_ARCHIVE]="false"

  BUILD_CONFIG[SIGN]="false"
  BUILD_CONFIG[JDK_BOOT_DIR]=""

  BUILD_CONFIG[MACOSX_CODESIGN_IDENTITY]=${BUILD_CONFIG[MACOSX_CODESIGN_IDENTITY]:-""}

  BUILD_CONFIG[NUM_PROCESSORS]="1"
  BUILD_CONFIG[TARGET_FILE_NAME]="OpenJDK-jdk.tar.gz"

  # Dir where we clone the OpenJDK source code for building, defaults to 'src'
  BUILD_CONFIG[OPENJDK_SOURCE_DIR]="src"

  # By default only git clone the HEAD commit
  BUILD_CONFIG[SHALLOW_CLONE_OPTION]=${BUILD_CONFIG[SHALLOW_CLONE_OPTION]:-"--depth=1"}

  # Set Docker Container names and defaults
  BUILD_CONFIG[DOCKER_SOURCE_VOLUME_NAME]=${BUILD_CONFIG[DOCKER_SOURCE_VOLUME_NAME]:-"openjdk-source-volume"}

  BUILD_CONFIG[CONTAINER_NAME]=${BUILD_CONFIG[CONTAINER_NAME]:-openjdk_container}

  BUILD_CONFIG[TMP_CONTAINER_NAME]=${BUILD_CONFIG[TMP_CONTAINER_NAME]:-openjdk-copy-src}
  BUILD_CONFIG[CLEAN_DOCKER_BUILD]=${BUILD_CONFIG[CLEAN_DOCKER_BUILD]:-false}

  # Use Docker to build (defaults to false)
  BUILD_CONFIG[USE_DOCKER]=${BUILD_CONFIG[USE_DOCKER]:-false}

  # Alow to debug docker build.sh script (dafult to false)
  BUILD_CONFIG[DEBUG_DOCKER]=${BUILD_CONFIG[DEBUG_DOCKER]:-false}

  # Location of DockerFile and where scripts get copied to inside the container
  BUILD_CONFIG[DOCKER_FILE_PATH]=${BUILD_CONFIG[DOCKER_FILE_PATH]:-""}

  # Whether we keep the Docker container after we build it
  # TODO Please note that the persistent volume is managed separately
  BUILD_CONFIG[KEEP_CONTAINER]=${BUILD_CONFIG[KEEP_CONTAINER]:-false}

  # Whether we use an existing container
  # TODO Please note that the persistent volume is managed separately
  BUILD_CONFIG[REUSE_CONTAINER]=${BUILD_CONFIG[REUSE_CONTAINER]:-true}

  # The current working directory
  BUILD_CONFIG[WORKING_DIR]=${BUILD_CONFIG[WORKING_DIR]:-"./build/"}

  # Root of the workspace
  BUILD_CONFIG[WORKSPACE_DIR]=${BUILD_CONFIG[WORKSPACE_DIR]:-""}

  # Use SSH for the GitHub connection (defaults to false)
  BUILD_CONFIG[USE_SSH]=${BUILD_CONFIG[USE_SSH]:-false}

  # Director where OpenJDK binary gets built to
  BUILD_CONFIG[TARGET_DIR]=${BUILD_CONFIG[TARGET_DIR]:-"target/"}


  # Which repo tag to build, e.g. jdk8u172-b03
  BUILD_CONFIG[TAG]=${BUILD_CONFIG[TAG]:-""}

  # Update version e.g. 172
  BUILD_CONFIG[OPENJDK_UPDATE_VERSION]=${BUILD_CONFIG[OPENJDK_UPDATE_VERSION]:-""}

  # build number e.g. b03
  BUILD_CONFIG[OPENJDK_BUILD_NUMBER]=${BUILD_CONFIG[OPENJDK_BUILD_NUMBER]:-""}

  # feature number e.g. 11
  BUILD_CONFIG[OPENJDK_FEATURE_NUMBER]=${BUILD_CONFIG[OPENJDK_FEATURE_NUMBER]:-""}

  # URL to a git repo containing source code patches to be applied
  BUILD_CONFIG[PATCHES]=${BUILD_CONFIG[PATCHES]:-""}

  # Build variant, e.g. openj9, defaults to "hotspot"
  BUILD_CONFIG[BUILD_VARIANT]=${BUILD_CONFIG[BUILD_VARIANT]:-"${BUILD_VARIANT_HOTSPOT}"}

  # JVM variant, e.g. client or server, defaults to server
  BUILD_CONFIG[JVM_VARIANT]=${BUILD_CONFIG[JVM_VARIANT]:-""}

  # Any extra config / make args provided by the user
  BUILD_CONFIG[USER_SUPPLIED_CONFIGURE_ARGS]=${BUILD_CONFIG[USER_SUPPLIED_CONFIGURE_ARGS]:-""}
  BUILD_CONFIG[USER_SUPPLIED_MAKE_ARGS]=${BUILD_CONFIG[USER_SUPPLIED_MAKE_ARGS]:-""}

  # Whether to use Temurin's cacerts file (true) or use the file provided by OpenJDK (false)
  BUILD_CONFIG[CUSTOM_CACERTS]=${BUILD_CONFIG[CUSTOM_CACERTS]:-"true"}

  BUILD_CONFIG[DOCKER]=${BUILD_CONFIG[DOCKER]:-"docker"}

  BUILD_CONFIG[TMP_SPACE_BUILD]=${BUILD_CONFIG[TMP_SPACE_BUILD]:-false}

  # If the wrong git repo is there allow it to be removed
  BUILD_CONFIG[CLEAN_GIT_REPO]=false

  BUILD_CONFIG[CLEAN_LIBS]=false

  # By default dont backport JEP318 certs to < Java 10
  BUILD_CONFIG[USE_JEP319_CERTS]=false

  BUILD_CONFIG[RELEASE]=false

  BUILD_CONFIG[CROSSCOMPILE]=false

  # By default assume we have Adoptium patches applied to the repo
  BUILD_CONFIG[ADOPT_PATCHES]=true

  BUILD_CONFIG[DISABLE_ADOPT_BRANCH_SAFETY]=false

  # Used in 'release' file for jdk8u
  BUILD_CONFIG[VENDOR]=${BUILD_CONFIG[VENDOR]:-"Undefined Vendor"}
}

# Declare the map of build configuration that we're going to use
declare -ax BUILD_CONFIG
export BUILD_CONFIG
