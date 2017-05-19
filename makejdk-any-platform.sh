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

set -eu

OS_MACHINE_NAME=$(uname -m)

if [[ "$OS_MACHINE_NAME" == "s390x" ]] ; then
   export JVM_VARIANT=${JVM_VARIANT:-zero}
   export BUILD_FULL_NAME=${BUILD_FULL_NAME:-linux-s390x-normal-${JVM_VARIANT}-release}
   S390X_MAKE_ARGS="CONF=${BUILD_FULL_NAME} DEBUG_BINARIES=true images"
   export MAKE_ARGS_FOR_ANY_PLATFORM=${MAKE_ARGS_FOR_ANY_PLATFORM:-$S390X_MAKE_ARGS}
fi
if [[ "$OS_MACHINE_NAME" = "ppc64le" ]] ; then
  export JVM_VARIANT=${JVM_VARIANT:-server}
  export BUILD_FULL_NAME=${BUILD_FULL_NAME:-linux-ppc64-normal-${JVM_VARIANT}-release}
  # shellcheck disable=SC1083
  export FREETYPE_FONT_BUILD_TYPE_PARAM=${FREETYPE_FONT_BUILD_TYPE_PARAM:="--build=$(rpm --eval %{_host})"}
fi
if [[ "$OS_MACHINE_NAME" == "armv7l" ]] ; then
   export JVM_VARIANT=${JVM_VARIANT:-zero}
   export MAKE_ARGS_FOR_ANY_PLATFORM=${MAKE_ARGS_FOR_ANY_PLATFORM:-"DEBUG_BINARIES=true images"}
   export CONFIGURE_ARGS_FOR_ANY_PLATFORM=${CONFIGURE_ARGS_FOR_ANY_PLATFORM:-"--with-jobs=${NUM_PROCESSORS}"}
fi

./makejdk.sh "$@"
