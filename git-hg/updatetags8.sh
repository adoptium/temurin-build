#!/bin/bash -x
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

set -euo pipefail

echo "Common defs"

# shellcheck disable=SC1091
modules=(corba langtools jaxp jaxws nashorn jdk hotspot)

# These variables needs to define in Jenkin's job pipeline
#WORKSPACE="<Define local workspace path where clone and merge is going to take place>"
#GITHUB_PROJECT="<Path for extension git repo>"
#GITHUB_REPO="<extention repo name, where merge will be pushed>" 
GITHUB_PROJECT=git@github.com:AdoptOpenJDK
GITHUB_REPO=openjdk-jdk8u

rm -rf $WORKSPACE/$GITHUB_REPO
rm -rf $WORKSPACE/openjdk

mkdir $WORKSPACE/$GITHUB_REPO
mkdir $WORKSPACE/openjdk
mkdir $WORKSPACE/openjdk/mirror

cd $WORKSPACE/$GITHUB_REPO

echo NOTE: This script requires git 2.16.2 or later and git-remote-hg from
echo https://raw.githubusercontent.com/felipec/git-remote-hg/master/git-remote-hg
git --version

# Clone current repo
echo "Clone current $GITHUB_REPO"
git clone $GITHUB_PROJECT/$GITHUB_REPO.git
cd $GITHUB_REPO
#git fetch --tags
#OLDTAG=$(git describe --abbrev=0 --tags) 
OLDTAG=none
echo "Current openjdk level is $OLDTAG"

# Clone current openjdk
echo "Get base openjdk repository" 
cd $WORKSPACE/openjdk/mirror
git init
git clone --bare hg::http://hg.openjdk.java.net/jdk8u/jdk8u

cd jdk8u.git

git filter-branch -f --index-filter 'git rm -r -f -q --cached --ignore-unmatch .hg .hgignore .hgtags README get_source.sh' --prune-empty --tag-name-filter cat -- --all

cd ..
git pull jdk8u
git fetch --tags jdk8u
# NEWTAG=$(git describe --abbrev=0 --tags)
# sxa@sainz:~/git/banana/combined$ git tag | grep jdk8u1..-b.. | while read LINE; do VERS=`echo $LINE | cut -d- -f1`; BUILD=`echo $LINE | cut -d- -f2`; if [ "$VERS" != "$LASTVERS" -a ! -z "$LASTVERS" ]; then echo $LASTVERS-$LASTBUILD; fi; LASTBUILD=$BUILD; LASTVERS=$VERS;  done
#for NEWTAG in jdk8u101-b13 jdk8u102-b35 jdk8u111-b14 jdk8u112-b33 jdk8u121-b36 jdk8u122-b04 jdk8u131-b34 \
#for NEWTAG in jdk8u132-b00 jdk8u141-b32 jdk8u144-b34 jdk8u151-b12 jdk8u152-b16 jdk8u161-b12 jdk8u162-b12 jdk8u172-b03 ; do
#for NEWTAG in jdk8u144-b34 jdk8u151-b12 jdk8u152-b16 jdk8u161-b12 jdk8u162-b12 jdk8u172-b11 ; do
for NEWTAG in jdk8u172-b11 ; do
  cd $WORKSPACE/openjdk/mirror
  git reset --hard $NEWTAG
  #rm -rf jdk8u.git

  echo $(date +%T): "SXA: New tag $NEWTAG, updating master branch"
  cd $WORKSPACE/$GITHUB_REPO/$GITHUB_REPO
  git checkout master
  git fetch $WORKSPACE/openjdk/mirror
  git merge --allow-unrelated-histories -m "Merge base $NEWTAG" FETCH_HEAD

  for module in "${modules[@]}"
    do
      if [ ! -d "$WORKSPACE/openjdk/$module" ]; then
        rm -rf "$WORKSPACE/openjdk/$module"
        mkdir "$WORKSPACE/openjdk/$module"
        cd $WORKSPACE/openjdk/$module
        git init
        echo "Clone $module"
        git clone --bare hg::http://hg.openjdk.java.net/jdk8u/jdk8u/$module || exit 1
        cd $module.git
        echo `date +%T`: SXA: "GIT filter on $module"
        git filter-branch -f --index-filter "git rm -f -q --cached --ignore-unmatch .hgignore .hgtags && git ls-files -s | sed \"s|\t\\\"*|&$module/|\" | GIT_INDEX_FILE=\$GIT_INDEX_FILE.new git update-index --index-info && mv \"\$GIT_INDEX_FILE.new\" \"\$GIT_INDEX_FILE\"" --prune-empty --tag-name-filter cat -- --all

        cd ..
      fi
      echo "GIT pull on $module"
      cd $WORKSPACE/openjdk/$module
      git pull $module
      git fetch --tags $module
      git reset --hard $NEWTAG
      #rm -rf $module.git
      cd $WORKSPACE/$GITHUB_REPO/$GITHUB_REPO 
      git fetch $WORKSPACE/openjdk/$module
      if ! git merge --allow-unrelated-histories -m "Merge $module $NEWTAG" FETCH_HEAD; then
         echo Please resolve the conflicts abova in $WORKSPACE/$GITHUB_REPO/$GITHUB_REPO, then press return to continue

         read PAUSE
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
  echo Deletng the old version of the tag from the server if it is present or push will fail
  [ "$NEWTAG" != "HEAD" ] && git push origin :refs/tags/$NEWTAG || true
  [ "$NEWTAG" == "HEAD" ] && git push origin master
  [ "$NEWTAG" != "HEAD" ] && git push origin master --tags

done

