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

# For terminal colors
esc=$(echo -en "\033")
error="${esc}[0;31m"
normal=$(echo -en "${esc}[m\017")


exit_script() {
    if [[ -z ${KEEP} ]] ; then
      docker ps -a | awk '{ print $1,$2 }' | grep "$CONTAINER" | awk '{print $1 }' | xargs -I {} docker rm -f {}
    fi
    echo "${error}Process exited${normal}"
    trap - SIGINT SIGTERM # clear the trap
    kill -- -$$ # Sends SIGTERM to child/sub processes
}

trap exit_script SIGINT SIGTERM 
