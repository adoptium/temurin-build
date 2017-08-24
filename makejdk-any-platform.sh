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

export OPENJDK_VERSION=""
export REPOSITORY=""

counter=0
for i in "$@"; do
  let counter++
  case "$i" in
    "--version" | "-v")
      let counter++
      string="\$$counter"
      OPENJDK_VERSION=$(echo "$@" | awk "{print $string}")
      ;;
  esac
done

if [ "$OPENJDK_VERSION" == "jdk9" ]; then
  export JDK_PATH="jdk"
elif [ "$OPENJDK_VERSION" == "jdk8u" ]; then
  export JDK_PATH="j2sdk-image"
else
  echo "Please specify a version with --version or -v , either jdk9 or jdk8u"
  man ./makejdk-any-platform.1
  exit 1
fi

REPOSITORY="${REPOSITORY:-adoptopenjdk/openjdk-$OPENJDK_VERSION}";
REPOSITORY="$(echo "${REPOSITORY}" | awk '{print tolower($0)}')";

case "$OS_MACHINE_NAME" in
"s390x")
  case "OPENJDK_VERSION" in
     "jdk9")
     export JVM_VARIANT=${JVM_VARIANT:-server}
     export CONFIGURE_ARGS_FOR_ANY_PLATFORM=${CONFIGURE_ARGS_FOR_ANY_PLATFORM:-"--disable-warnings-as-errors"};;
     "jdk8u")
     export JVM_VARIANT=${JVM_VARIANT:-zero} ;;
  esac

  export BUILD_FULL_NAME=${BUILD_FULL_NAME:-linux-s390x-normal-${JVM_VARIANT}-release}
  S390X_MAKE_ARGS="CONF=${BUILD_FULL_NAME} DEBUG_BINARIES=true images"
  export MAKE_ARGS_FOR_ANY_PLATFORM=${MAKE_ARGS_FOR_ANY_PLATFORM:-$S390X_MAKE_ARGS}
;;

"ppc64le")
  case "OPENJDK_VERSION" in
    "jdk9")
    export CONFIGURE_ARGS_FOR_ANY_PLATFORM=${CONFIGURE_ARGS_FOR_ANY_PLATFORM:-"--disable-warnings-as-errors"};;
  esac
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
  case "OPENJDK_VERSION" in
    "jdk9")
    export CONFIGURE_ARGS_FOR_ANY_PLATFORM=${CONFIGURE_ARGS_FOR_ANY_PLATFORM:-"--disable-warnings-as-errors"};;
  esac
  export FREETYPE_FONT_VERSION="2.5.2"
;;
esac

case "$OS_KERNEL_NAME" in
"aix")
  case "OPENJDK_VERSION" in
    "jdk9")
    export CONFIGURE_ARGS_FOR_ANY_PLATFORM=${CONFIGURE_ARGS_FOR_ANY_PLATFORM:-"--disable-warnings-as-errors"};;
  esac
  export MAKE_COMMAND_NAME=${MAKE_COMMAND_NAME:-"gmake"}
;;

"darwin")
  case "OPENJDK_VERSION" in
    "jdk9")
    export CONFIGURE_ARGS_FOR_ANY_PLATFORM=${CONFIGURE_ARGS_FOR_ANY_PLATFORM:-"--disable-warnings-as-errors"};;
  esac
;;

esac
./makejdk.sh "$@"
