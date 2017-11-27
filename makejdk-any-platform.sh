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

# Script to clone the OpenJDK source then build it

# Optionally uses Docker, otherwise you can provide two arguments:
# the area to build the JDK e.g. $HOME/mybuilddir as -s or --source
# and the target destination for the tar.gz e.g. -d or --destination $HOME/mytargetdir
# Both must be absolute paths! You can use $PWD/mytargetdir

# A simple way to install dependencies persistently is to use our Ansible playbooks

# You can set the JDK boot directory with the JDK_BOOT_DIR environment variable

export OS_KERNEL_NAME=""
OS_KERNEL_NAME=$(uname | awk '{print tolower($0)}')
export OS_MACHINE_NAME=""
OS_MACHINE_NAME=$(uname -m)

# The full forest name, e.g. jdk8, jdk8u, jdk9, jdk9u, etc.
export OPENJDK_FOREST_NAME=""

# The abridged, core version name, e.g. jdk8, jdk9, etc. No "u"s.
export OPENJDK_CORE_VERSION=""

export BUILD_VARIANT=""
export REPOSITORY=""

counter=0
for i in "$@"; do
  let counter++
  case "$i" in
    "--version" | "-v")
      let counter++
      string="\$$counter"
      OPENJDK_FOREST_NAME=$(echo "$@" | awk "{print $string}")
      OPENJDK_CORE_VERSION=${OPENJDK_FOREST_NAME}
      if [[ $OPENJDK_FOREST_NAME == *u ]]; then
        OPENJDK_CORE_VERSION=${OPENJDK_FOREST_NAME::-1}
      fi
      ;;
    "--variant" | "-bv")
      let counter++
      string="\$$counter"
      BUILD_VARIANT=$(echo "$@" | awk "{print $string}")
      ;;
  esac
done

if [ "$OPENJDK_CORE_VERSION" == "jdk9" ]; then
  export JDK_PATH="jdk"
  export CONFIGURE_ARGS_FOR_ANY_PLATFORM=${CONFIGURE_ARGS_FOR_ANY_PLATFORM:-"--disable-warnings-as-errors"}
elif [ "$OPENJDK_CORE_VERSION" == "jdk8" ]; then
  export JDK_PATH="j2sdk-image"
else
  echo "Please specify a version with --version or -v , either jdk9 or jdk8, with or without a \'u\' suffix."
  man ./makejdk-any-platform.1
  exit 1
fi

REPOSITORY="${REPOSITORY:-adoptopenjdk/openjdk-$OPENJDK_FOREST_NAME}";
REPOSITORY="$(echo "${REPOSITORY}" | awk '{print tolower($0)}')";

case "$OS_MACHINE_NAME" in
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

case "$OS_KERNEL_NAME" in
"aix")
  export MAKE_COMMAND_NAME=${MAKE_COMMAND_NAME:-"gmake"}
;;
"sunos")
  export MAKE_COMMAND_NAME=${MAKE_COMMAND_NAME:-"gmake"}
 ;;

esac
./makejdk.sh "$@"
