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
# diff
#
# For finding the diff between an AdoptOpenJDK Git repo and the OpenJDK Mercurial
# Repo for Java versions <= jdk9u
#
# 1. Clones the AdoptOpenJDK Git repo for a particular version
# 2. Clones the OpenJDK Mercurial repo for that same version
# 3. Runs a diff between the two
#
################################################################################

set -euxo pipefail

function checkArgs() {
  if [ $# -lt 2 ]; then
     echo Usage: "$0" '[AdoptOpenJDK Git Repo Version] [OpenJDK Mercurial Root Forest Name] [OpenJDK Mercurial Root Forest Version] [Tag Name] [Allowed Change Size]'
     echo ""
     echo "e.g. ./diff.sh jdk8u jdk8u jdk8u or ./diff.sh jdk9u jdk-updates jdk9u"
     echo ""
     exit 1
  fi
}

checkArgs $@

git_repo_version=$1
hg_root_forest=${2:-${1}}                  # for backwards compatibility
hg_repo_version=${3:-${hg_root_forest}}    # for backwards compatibility
tag=${4:-} # tag to check
expectedDiffLimit=${5:-0} # Number of lines that the full-diff file can be before an error is reported

function cleanUp() {
  rm -rf openjdk-git openjdk-hg || true
}

function cloneRepos() {
  echo "AdoptOpenJDK Git Repo Version: ${git_repo_version}"
  echo "OpenJDK Mercurial Repo Version: ${hg_root_forest}/${hg_repo_version}"

  git clone -b master "https://github.com/AdoptOpenJDK/openjdk-${git_repo_version}.git" openjdk-git || exit 1
  hg clone "https://hg.openjdk.java.net/${hg_root_forest}/${hg_repo_version}" openjdk-hg || exit 1

  if [ -n "${tag}" ]; then
    cd openjdk-hg
    hg update $tag
    cd ../openjdk-git
    git fetch --all
    git checkout $tag
    cd ..
  else
    # By default compare the dev branch
    cd ./openjdk-git
    git fetch --all
    git checkout dev
    cd ..
  fi
}

function updateMercurialClone() {
    local rootDir=$(pwd)

    cd "${rootDir}/openjdk-hg" || exit 1
    if [ -f get_source.sh ]; then
        chmod u+x get_source.sh
        ./get_source.sh

        if [ -n "${tag}" ]; then
            MODULES=(corba langtools jaxp jaxws nashorn jdk hotspot)

            hg update $tag
            for module in "${MODULES[@]}" ; do
                cd "${rootDir}/openjdk-hg/${module}"
                hg update $tag
            done
        fi
    fi

    cd $rootDir || exit 1
}

function runDiff() {

  local diffArgs="openjdk-git openjdk-hg -x '.git' -x '.hg' -x '.hgtags' -x '.hgignore' -x 'get_source.sh' -x 'README.md'"
  set +e
  diff -r  $diffArgs > full-changes.diff
  diff -rq $diffArgs > changes.diff
  set -e

  diffNum=$(wc -l < full-changes.diff)

  if [ "$diffNum" -gt ${expectedDiffLimit} ]; then
    echo "ERROR - THE DIFF IS TOO LARGE, EXAMINE full-changes.diff"
    exit 1
  fi
}

cleanUp
cloneRepos
updateMercurialClone
runDiff
