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

set -euo

git_repo_version=$1
hg_root_forest=${2:-${1}}                  # for backwards compatibility
hg_repo_version=${3:-${hg_root_forest}}    # for backwards compatibility

#cleanup TODO put back
#rm -rf openjdk-git openjdk-hg

echo "git repo version: ${git_repo_version}"
echo "hg repo version: ${hg_root_forest}/${hg_repo_version}"

# TODO put back
#git clone -b master "https://github.com/AdoptOpenJDK/openjdk-${git_repo_version}.git" openjdk-git || exit 1
#hg clone "http://hg.openjdk.java.net/${hg_root_forest}/${hg_repo_version}" openjdk-hg || exit 1

cd openjdk-hg || exit 1

chmod u+x get_source.sh
./get_source.sh

cd - || exit 1

pwd
diffNum=$(diff -rq openjdk-git openjdk-hg -x '.git' -x '.hg' -x '.hgtags' | wc -l)

if [ "$diffNum" -gt 0 ]; then
  echo "ERROR - THE DIFF HAS DETECTED UNKNOWN FILES"
  diff -rq openjdk-git openjdk-hg -x '.git' -x '.hg' -x '.hgtags' | grep 'Only in' || exit 1
  exit 1
fi

# get latest git tag

echo "entering openjdk-git"
cd openjdk-git || exit 1
gitTag=$(git describe --abbrev=0 --tags) || exit 1
cd - || exit 1

cd openjdk-hg || exit 1
hgTag=$(hg log -r "." --template "{latesttag}\n") || exit 1
cd - || exit 1

if [ "$gitTag" == "$hgTag" ]; then
  echo "Tags are in sync"
else
  echo "ERROR - THE TAGS ARE NOT IN SYNC"
  exit 1
fi
