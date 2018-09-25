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
# add-branch-without-modules
#
# Local setup of the Git clone branches for the OpenJDK10 (updates) mercurial
# repository
#
# Initial repo will be pushed to git@github.com:AdoptOpenJDK/openjdk-jdk10u.git
#
################################################################################

set -euo pipefail

echo "Import common functionality"
# shellcheck disable=SC1091
source import-common.sh

echo "Enter hg"
cd hg || exit 1

bpath=$1
branch=$2

echo "Create $bpath"
mkdir -p "$bpath" || exit 1

echo "git hg clone $bpath (root)"
git hg clone "https://hg.openjdk.java.net/$bpath" "$bpath/root" || exit 1

echo "checkout the $branch"
if [ "$branch" != "" ]; then
  cd "$bpath/root" || exit 1
  git-hg checkout "$branch" || exit 1
  cd - || exit 1
fi

echo "Enter ../combined"
cd ../combined || exit 1

echo "checkout the master branch"
git checkout -b master || exit 1

echo "Add remote for (root)"
git remote add "imports/$bpath/root" "../hg/$bpath/root" || exit 1

echo "Fetch (root)"
git fetch "imports/$bpath/root" || exit 1

echo "Merge (root)"
git merge "imports/$bpath/root/master" -m "Initial merge of (root)" || exit 1

echo "Push the tags to the master branch"
git push github master --tags || exit 1
