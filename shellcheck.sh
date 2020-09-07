#!/bin/bash

################################################################################
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
################################################################################

################################################################################
#
# This script downloads and executes shellcheck. It will be run automatically
# by Travis on every push. You can run it manually to validate your changes.
#
################################################################################

set -eu

shellcheckVersion="stable" # or "v0.4.7", or "latest"
shellcheckDir="shellcheck-stable"
shellcheckCmd="${shellcheckDir}/shellcheck"

install() 
{
  wget "https://github.com/koalaman/shellcheck/releases/download/${shellcheckVersion}/shellcheck-${shellcheckVersion}.linux.x86_64.tar.xz"
  
  tar --xz -xvf "shellcheck-${shellcheckVersion}.linux.x86_64.tar.xz"
  rm "shellcheck-${shellcheckVersion}.linux.x86_64.tar.xz"
  "${shellcheckCmd}" --version
}

check() 
{
  "${shellcheckCmd}" -x ./*.sh
}

if [[ ! -d "${shellcheckDir}" ]] ; then
  install
fi
check
