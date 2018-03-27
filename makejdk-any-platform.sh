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

################################################################################################
#
# Script to prepare the AdoptOpenJDK build script for any platform and then call it (makejdk.sh)
#
################################################################################################

# TODO 9 should become 9u as will 10 shortly....

set -x # TODO remove this once we've finished

# The OS kernel name, e.g. 'darwin' for Mac OS X
export OS_KERNEL_NAME=""
OS_KERNEL_NAME=$(uname | awk '{print tolower($0)}')

# The O/S architecture, e.g. x86_64 for a modern intel / Mac OS X
export OS_ARCHITECTURE=""
OS_ARCHITECTURE=$(uname -m)

# The full forest name, e.g. jdk8, jdk8u, jdk9, jdk9u, etc.
export OPENJDK_FOREST_NAME=""

# The abridged, core version name, e.g. jdk8, jdk9, etc. No "u"s.
export OPENJDK_CORE_VERSION=""

# The build variant, e.g. openj9
export BUILD_VARIANT=""

# The OpenJDK source code repository to build from, could be a GitHub AdoptOpenJDK repo, mercurial forest etc
export REPOSITORY=""

parseCommandLineArgs()
{
  # While we have flags, (that start with a '-' char) then process them
  while [[ $# -gt 0 ]] && [[ ."$1" = .-* ]] ; do
    opt="$1";
    shift;
    case "$opt" in
      "--variant" | "-bv")
        BUILD_VARIANT=$(echo "$1" | awk "{print $string}")
        shift;;

      # Bypass the other flags (we'll process them again in makejdk.sh
      *) shift;;
    esac
  done

  # Now that we've processed the flags, grab the mandatory argument(s)
  OPENJDK_FOREST_NAME=$(echo "$1" | awk "{print $string}")
  export OPENJDK_CORE_VERSION=${OPENJDK_FOREST_NAME}

  # 'u' means it's an update repo, e.g. jdk8u
  if [[ ${OPENJDK_FOREST_NAME} == *u ]]; then
    export OPENJDK_CORE_VERSION=${OPENJDK_FOREST_NAME%?}
  fi
}

setVariablesBeforeCallingConfigure() {
  # TODO Regex this in the if or use cut to grab out the number and see if >= 9
  if [ "$OPENJDK_CORE_VERSION" == "jdk9" ] || [ "$OPENJDK_CORE_VERSION" == "jdk10" ] || [ "$OPENJDK_CORE_VERSION" == "jdk11" ] || [ "$OPENJDK_CORE_VERSION" == "amber" ]; then
    export JDK_PATH="jdk"
    export JRE_PATH="jre"
    export CONFIGURE_ARGS_FOR_ANY_PLATFORM=${CONFIGURE_ARGS_FOR_ANY_PLATFORM:-"--disable-warnings-as-errors"}
  elif [ "$OPENJDK_CORE_VERSION" == "jdk8" ]; then
    export COPY_MACOSX_FREE_FONT_LIB_FOR_JDK_FLAG="false"
    export COPY_MACOSX_FREE_FONT_LIB_FOR_JRE_FLAG="true"
    export JDK_PATH="j2sdk-image"
    export JRE_PATH="j2re-image"
  else
    echo "Please specify a version, either jdk8, jdk9, jdk10 etc, with or without a 'u' suffix. e.g. $0 [options] jdk8u"
    exit 1
  fi
}

# Set the repository, defaults to AdoptOpenJDK/openjdk-$OPENJDK_FOREST_NAME
setRepository() {
  REPOSITORY="${REPOSITORY:-adoptopenjdk/openjdk-$OPENJDK_FOREST_NAME}";
  REPOSITORY="$(echo "${REPOSITORY}" | awk '{print tolower($0)}')";
}

# Specific architectures needs to have special build settings
processArgumentsforSpecificArchitectures() {
  case "$OS_ARCHITECTURE" in
  "s390x")
    if [ "$OPENJDK_CORE_VERSION" == "jdk8" ] && [ "$BUILD_VARIANT" != "openj9" ]; then
      export JVM_VARIANT=${JVM_VARIANT:-zero}
    else
      export JVM_VARIANT=${JVM_VARIANT:-server}
    fi

    export BUILD_FULL_NAME=${BUILD_FULL_NAME:-linux-s390x-normal-${JVM_VARIANT}-release}
    S390X_MAKE_ARGS="CONF=${BUILD_FULL_NAME} DEBUG_BINARIES=true images"
    export MAKE_ARGS_FOR_ANY_PLATFORM=${MAKE_ARGS_FOR_ANY_PLATFORM:-$S390X_MAKE_ARGS}
  ;;

  "ppc64le")
    export JVM_VARIANT=${JVM_VARIANT:-server}
    export BUILD_FULL_NAME=${BUILD_FULL_NAME:-linux-ppc64-normal-${JVM_VARIANT}-release}
    # shellcheck disable=SC1083
    export FREETYPE_FONT_BUILD_TYPE_PARAM=${FREETYPE_FONT_BUILD_TYPE_PARAM:="--build=$(rpm --eval %{_host})"}
  ;;

  "armv7l")
    export JVM_VARIANT=${JVM_VARIANT:-zero}
    export MAKE_ARGS_FOR_ANY_PLATFORM=${MAKE_ARGS_FOR_ANY_PLATFORM:-"DEBUG_BINARIES=true images"}
    export CONFIGURE_ARGS_FOR_ANY_PLATFORM=${CONFIGURE_ARGS_FOR_ANY_PLATFORM:-"--with-jobs=${NUM_PROCESSORS}"}
  ;;

  "aarch64")
    export FREETYPE_FONT_VERSION="2.5.2"
  ;;
  esac
}

setMakeCommandForOS() {
  case "$OS_KERNEL_NAME" in
  "aix")
    export MAKE_COMMAND_NAME=${MAKE_COMMAND_NAME:-"gmake"}
  ;;
  "SunOS")
    export MAKE_COMMAND_NAME=${MAKE_COMMAND_NAME:-"gmake"}
  ;;

  esac
}

parseCommandLineArgs "$@"
setVariablesBeforeCallingConfigure
setRepository
processArgumentsforSpecificArchitectures
setMakeCommandForOS

./makejdk.sh "$@"
