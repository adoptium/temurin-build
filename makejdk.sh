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
################################################################################

# TODO rewrite the doc here

#
# Script to clone the OpenJDK source then build it

# Optionally uses Docker, otherwise you can provide two arguments:
# the area to build the JDK e.g. $HOME/mybuilddir as -s or --source and the
# target destination for the tar.gz e.g. -d or --destination $HOME/mytargetdir
# Both must be absolute paths! You can use $PWD/mytargetdir

# To install dependencies persistently is to use our Ansible playbooks

# You can set the JDK boot directory with the JDK_BOOT_DIR environment variable
#
################################################################################

set -eux

# i.e. Where we are
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Pull in configuration support (read / write / display)
source ${SCRIPT_DIR}/configureBuild.sh
source ${SCRIPT_DIR}/docker-build.sh
source ${SCRIPT_DIR}/native-build.sh


unset BUILD_CONFIG

if [ -z ${BUILD_CONFIG+x} ]
then
  declare -A BUILD_CONFIG
  BUILD_CONFIG[foo]="bar"
fi

configure_build "$(declare -p BUILD_CONFIG)" UPDATED_BUILD_CONFIG "$@"
declare -A BUILD_CONFIG=${UPDATED_BUILD_CONFIG#*=}

set +x
echo "BUILDING WITH CONFIGURATION:"
echo "============================"
for K in "${!BUILD_CONFIG[@]}";
do
  echo BUILD_CONFIG[$K]=${BUILD_CONFIG[$K]};
done | sort
set -x

if [ "${BUILD_CONFIG[USE_DOCKER]}" == "true" ] ; then
  buildAndTestOpenJDKViaDocker
else
  buildAndTestOpenJDKInNativeEnvironment
fi

