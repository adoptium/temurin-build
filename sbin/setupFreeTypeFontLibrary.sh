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
# A simple script to build Free Type Font Library via an existing script, into the user's home directory

DESTINATION_PARENT_FOLDER=${1:-$HOME}
FREE_TYPE_FONT_LIBRARY_LOCATION="${DESTINATION_PARENT_FOLDER}/installedfreetype"
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

if [[ -d "${FREE_TYPE_FONT_LIBRARY_LOCATION}" ]]; then
    echo "${info}"
    echo "Skipping the building process, as the FreeTypeFont Library already exists at ${FREE_TYPE_FONT_LIBRARY_LOCATION}"
    echo "${normal}"   
    exit 0
fi

export OS_KERNEL_NAME=""
OS_KERNEL_NAME=$(uname | awk '{print tolower($0)}')
export OS_MACHINE_NAME=""
OS_MACHINE_NAME=$(uname -m)

export FREETYPE_FONT_BUILD_TYPE_PARAM=""
if [[ "$OS_MACHINE_NAME" = "ppc64le" ]] ; then
  # shellcheck disable=SC1083
  FREETYPE_FONT_BUILD_TYPE_PARAM=${FREETYPE_FONT_BUILD_TYPE_PARAM:="--build=$(rpm --eval %{_host})"}
fi

# shellcheck source=sbin/colour-codes.sh
source "$SCRIPT_DIR/colour-codes.sh"

# shellcheck source=sbin/common-functions.sh
source "$SCRIPT_DIR/common-functions.sh"

echo "${info}"
echo "Building FreeTypeFontLibrary in $DESTINATION_PARENT_FOLDER"
echo "${normal}"

buildFreeTypeFontLibrary "$DESTINATION_PARENT_FOLDER"

echo "${info}"
echo "Finished building FreeTypeFontLibrary in ${DESTINATION_PARENT_FOLDER}, see contents below"
echo "${normal}"

ls "${FREE_TYPE_FONT_LIBRARY_LOCATION}" -d
ls "${FREE_TYPE_FONT_LIBRARY_LOCATION}"
