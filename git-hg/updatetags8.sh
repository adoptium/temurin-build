#!/bin/bash
#
# ===========================================================================
# (c) Copyright IBM Corp. 2018 All Rights Reserved
# ===========================================================================
#
# This code is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License version 2 only, as
# published by the Free Software Foundation.
#
# This code is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
# FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
# version 2 for more details (a copy is included in the LICENSE file that
# accompanied this code).
#
# You should have received a copy of the GNU General Public License version
# 2 along with this work; if not, see <http://www.gnu.org/licenses/>.
#
# ===========================================================================

if [ $# -lt 2 ]; then
   echo Usage: $0 '[jdk8u|jdk9] TAGS'
   echo Version supplied should match a reposotiry in adoptopenjdk/openjdk-VERSION
   echo And also http://hg.openjdk.java.net/VERSION/VERSION
   exit 1
fi
[ -z "$WORKSPACE" -o ! -d "$WORKSPACE" ] && echo Cannot access \$WORKSPACE: $WORKSPACE && exit 2

set -euo pipefail

MODULES=(corba langtools jaxp jaxws nashorn jdk hotspot)

# These variables needs to define in Jenkin's job pipeline
OPENJDK_VERSION="$1"
TAGS="$2"
GITHUB_PROJECT=git@github.com:AdoptOpenJDK
GITHUB_REPO="openjdk-$OPENJDK_VERSION"

# Clean up
rm    -rf $WORKSPACE/$GITHUB_REPO $WORKSPACE/openjdk
mkdir -p  $WORKSPACE/$GITHUB_REPO $WORKSPACE/openjdk/mirror 

git --version || exit 1
GIT_VERSION=$(git --version | awk '{print$NF}')
GIT_MAJOR_VERSION=$(echo $GIT_VERSION | cut -d. -f1)
GIT_MINOR_VERSION=$(echo $GIT_VERSION | cut -d. -f2)
[ $GIT_MAJOR_VERSION -eq 1 ] && echo I need git version 2.16 or later and you have $GIT_VERSION && exit 1
[ $GIT_MAJOR_VERSION -eq 2 -a $GIT_MINOR_VERSION -lt 16 ] && echo I need git version 2.16 or later and you have $GIT_VERSION && exit 1
# https://raw.githubusercontent.com/felipec/git-remote-hg/master/git-remote-hg
if ! which git-remote-hg 2>/dev/null; then
  echo I need git-remote-hg and could not find it
  echo Get it from http://raw.githubusercontent.com/felipec/git-remote-hg/master/git-remote-hg
  exit 1
fi

# Clone current AdoptOpenJDK repo
cd $WORKSPACE/$GITHUB_REPO
echo "Clone current $GITHUB_REPO"
git clone $GITHUB_PROJECT/$GITHUB_REPO.git
cd $GITHUB_REPO
git fetch --tags
OLDTAG=$(git describe --abbrev=0 --tags) 
echo "Current openjdk level is $OLDTAG"

# Clone current openjdk from Mercurial
echo "Get base openjdk repository" 
cd $WORKSPACE/openjdk/mirror
git init
git clone --bare "hg::http://hg.openjdk.java.net/$OPENJDK_VERSION/$OPENJDK_VERSION"

cd "$OPENJDK_VERSION.git"

git filter-branch -f --index-filter 'git rm -r -f -q --cached --ignore-unmatch .hg .hgignore .hgtags get_source.sh' --prune-empty --tag-name-filter cat -- --all

cd ..
git pull "$OPENJDK_VERSION"
git fetch --tags "$OPENJDK_VERSION"
# NEWTAG=$(git describe --abbrev=0 --tags)
for NEWTAG in $TAGS ; do
  cd $WORKSPACE/openjdk/mirror
  git reset --hard $NEWTAG

  echo $(date +%T): "Updating master branch for $NEWTAG"
  cd $WORKSPACE/$GITHUB_REPO/$GITHUB_REPO
  git checkout master
  git fetch $WORKSPACE/openjdk/mirror
  git merge --allow-unrelated-histories -m "Merge base $NEWTAG" FETCH_HEAD

  for module in "${MODULES[@]}"
    do
      if [ ! -d "$WORKSPACE/openjdk/$module" ]; then
        rm -rf "$WORKSPACE/openjdk/$module"
        mkdir "$WORKSPACE/openjdk/$module"
        cd $WORKSPACE/openjdk/$module
        git init
        echo $(date +%T): "Clone $module"
        git clone --bare "hg::http://hg.openjdk.java.net/${OPENJDK_VERSION}/${OPENJDK_VERSION}/$module" || exit 1
        echo $(date +%T): "GIT filter on $module"
        cd $module.git
        git filter-branch -f --index-filter "git rm -f -q --cached --ignore-unmatch .hgignore .hgtags && git ls-files -s | sed \"s|\t\\\"*|&$module/|\" | GIT_INDEX_FILE=\$GIT_INDEX_FILE.new git update-index --index-info && mv \"\$GIT_INDEX_FILE.new\" \"\$GIT_INDEX_FILE\"" --prune-empty --tag-name-filter cat -- --all
        cd ..
      fi
      echo $(date +%T): "GIT pull/reset on $module at $NEWTAG"
      cd $WORKSPACE/openjdk/$module
      git pull $module
      git fetch --tags $module
      git reset --hard $NEWTAG
      cd $WORKSPACE/$GITHUB_REPO/$GITHUB_REPO 
      git fetch $WORKSPACE/openjdk/$module
      echo $(date +%T): "GIT filter on $module"
      if ! git merge --allow-unrelated-histories -m "Merge $module at $NEWTAG" FETCH_HEAD; then
         echo Please resolve the conflicts above in $WORKSPACE/$GITHUB_REPO/$GITHUB_REPO, then press return to continue
         read _
      fi
    done
  cd $WORKSPACE/$GITHUB_REPO/$GITHUB_REPO
  git push origin master
  
  echo "Pulling in changes to $GITHUB_REPO branch"
  git checkout master
  git fetch origin master
  if ! git merge --allow-unrelated-histories -m "Merge $NEWTAG into $GITHUB_REPO" FETCH_HEAD; then
    echo Please resolve the conflicts above in $WORKSPACE/$GITHUB_REPO/$GITHUB_REPO, then press return to continue
    read PAUSE
  fi
  [ "$NEWTAG" != "HEAD" ] && git tag -f -a $NEWTAG -m "Merge $NEWTAG into master"
  echo Deleting the old version of the tag from the server if it is present or push will fail
  # shellcheck disable=SC2015
  [ "$NEWTAG" != "HEAD" ] && git push origin :refs/tags/$NEWTAG || true
  [ "$NEWTAG" == "HEAD" ] && git push origin master
  [ "$NEWTAG" != "HEAD" ] && git push origin master --tags

done
