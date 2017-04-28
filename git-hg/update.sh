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

bpaths=`ls -d -1 */*`

for bpath in $bpaths
do

pushd "$bpath/root"
echo "Update $bpath -> (root)"
git hg fetch "http://hg.openjdk.java.net/$bpath"
git hg pull "http://hg.openjdk.java.net/$bpath"
popd

for m in $submodules
do
    pushd "$bpath/$m"
    echo "Update $bpath -> $m"
    git hg fetch "http://hg.openjdk.java.net/$bpath/$m"
    git hg pull "http://hg.openjdk.java.net/$bpath/$m"
    popd
done

echo "Exit hg"
echo "Enter combined"

cd ../combined || exit 1

echo "Check out $bpath"

git checkout master || exit 1

echo "Fetch (root)"

git fetch imports/$bpath/root || exit 1

echo "Merge (root)"

git merge imports/$bpath/root/master -m "Merge from (root)" --no-ff || exit 1

for m in $submodules
do
    echo "Fetch '$m'"
    git fetch imports/$bpath/$m || exit 1

    echo "Merge '$m'"
    git subtree merge --prefix=$m imports/$bpath/$m/master -m "Merge from '$m'" || exit 1
done

echo "Push"

git push github master --tags

cd ../hg

done
