#!/bin/bash
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
# import-common
#
# common functionality for the git-hg scripts
#
################################################################################

export modules=(corba langtools jaxp jaxws hotspot nashorn jdk)

function checkGitVersion() {
  git --version || exit 1
  GIT_VERSION=$(git --version | awk '{print$NF}')
  GIT_MAJOR_VERSION=$(echo "$GIT_VERSION" | cut -d. -f1)
  GIT_MINOR_VERSION=$(echo "$GIT_VERSION" | cut -d. -f2)
  [ "$GIT_MAJOR_VERSION" -eq 1 ] && echo I need git version 2.16 or later and you have "$GIT_VERSION" && exit 1
  if [ "$GIT_MAJOR_VERSION" -eq 2 ] && [ "$GIT_MINOR_VERSION" -lt 16 ] ; then
    echo I need git version 2.16 or later and you have "$GIT_VERSION"
    exit 1
  fi
}

function installGitRemoteHg() {
  if ! which git-remote-hg 2>/dev/null; then
    echo "I need git-remote-hg and could not find it"
    echo "Getting it from https://raw.githubusercontent.com/felipec/git-remote-hg/master/git-remote-hg"
    mkdir -p "$WORKSPACE/bin"
    PATH="$PATH:$WORKSPACE/bin"
    wget -O "$WORKSPACE/bin/git-remote-hg" "https://raw.githubusercontent.com/felipec/git-remote-hg/master/git-remote-hg"
    chmod ugo+x "$WORKSPACE/bin/git-remote-hg"
    if ! which git-remote-hg 2>/dev/null; then
      echo "Still cannot find it, exiting.."
      exit 1
    fi
  fi
}

# Merge master into dev as we build off dev at the AdoptOpenJDK Build farm
# dev contains patches that AdoptOpenJDK has beyond upstream OpenJDK
function performMergeIntoDevFromMaster() {
  git checkout dev || git checkout -b dev origin/dev
  git pull origin dev || exit 1
  git rebase master || exit 1
  git push origin dev || exit 1
}


