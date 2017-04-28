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

echo "Common defs"

. import-common.sh

echo "Enter hg"

cd hg || exit 1

bpath=$1

echo "Create $bpath"

mkdir -p $bpath || exit 1

echo "Clone $bpath (root)"
git hg clone "http://hg.openjdk.java.net/$bpath" "$bpath/root" || exit 1

for m in $submodules
do
    echo "Clone $bpath -> $m"
    git hg clone "http://hg.openjdk.java.net/$bpath/$m" "$bpath/$m" || exit 1
done

echo "Exit hg"
echo "Enter combined"

cd ../combined || exit 1

echo "Branch $bpath"

pwd

git checkout -b master || exit 1

echo "Add remote for (root)"

git remote add imports/$bpath/root ../hg/$bpath/root || exit 1

echo "Fetch (root)"

git fetch imports/$bpath/root || exit 1

echo "Merge (root)"

#git merge imports/$bpath/root/master -m "Initial merge of (root)" --no-ff || exit 1
git merge imports/$bpath/root/master -m "Initial merge of (root)" || exit 1

for m in $submodules
do
    echo "Add remote for '$m'"
    git remote add imports/$bpath/$m ../hg/$bpath/$m || exit 1

    echo "Fetch '$m'"
    git fetch imports/$bpath/$m || exit 1

    echo "Merge '$m'"
    git subtree add --prefix=$m imports/$bpath/$m/master -m "Initial merge of '$m'" || exit 1
done

echo "Push"

git push github master --tags || exit 1
