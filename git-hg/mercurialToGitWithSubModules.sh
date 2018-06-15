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

################################################################################
# mercurialToGitWithSubModules
#
# Local setup of the Git clone of a OpenJDK mercurial repository for Java 8/9
#
# Initial repo will be pushed to git@github.com:AdoptOpenJDK/openjdk-$GITHUB_REPO.git
#
# TODO Make the location of the git push a parameter
#
################################################################################

set -euo pipefail

echo "Import common functionality"
# shellcheck disable=SC1091
source import-common.sh

function checkArgs() {
  if [ $# -lt 1 ]; then
     echo Usage: "$0" '[jdk8u|jdk9u] (TAGS)'
     echo "Version supplied should match a repository in AdoptOpenJDK/openjdk-VERSION"
     exit 1
  fi
  if [ -z "$WORKSPACE" ] || [ ! -d "$WORKSPACE" ] ; then
    echo Cannot access \$WORKSPACE: "$WORKSPACE"
    exit 2
  fi
}

# These the the modules in the mercurial forest that we'll have to iterate over
MODULES=(corba langtools jaxp jaxws nashorn jdk hotspot)

OPENJDK_VERSION="$1"
shift
# shellcheck disable=SC2124
TAGS="$@"
GITHUB_PROJECT=git@github.com:AdoptOpenJDK
GITHUB_REPO="openjdk-$OPENJDK_VERSION"

function setMercurialRepoAndTagsToRetrieve() {
  case "$OPENJDK_VERSION" in
     jdk8*) HG_REPO=http://hg.openjdk.java.net/jdk8u/jdk8u
            # Would be nice to pull out the tags in an automated fashion, but
            # OpenJDK does not provide this yet.
            [ -z "$TAGS" ] && TAGS="jdk8u144-b34 jdk8u151-b12 jdk8u152-b16 jdk8u161-b12 jdk8u162-b12 jdk8u172-b03 jdk8u172-b11 HEAD";;
     jdk9*) HG_REPO=http://hg.openjdk.java.net/jdk-updates/jdk9u
            [ -z "$TAGS" ] && TAGS="jdk-9+181 jdk-9.0.1+11 jdk-9.0.3+9 jdk-9.0.4+11 HEAD";;
         *) Unknown JDK version - only jdk8u and jdk9 are supported; exit 1;;
  esac
}

function createDirectories() {
  mkdir -p  "$WORKSPACE/$GITHUB_REPO" "$WORKSPACE/openjdk/mirror"
}

# Clone current Git repo
function cloneGitOpenJDKRepo() {
  cd "$WORKSPACE/$GITHUB_REPO" || exit 1;
  echo "Clone current $GITHUB_REPO"
  if [ ! -d "$GITHUB_REPO" ] ; then
    git clone "$GITHUB_PROJECT/$GITHUB_REPO.git"
    cd "$GITHUB_REPO" || exit 1;
  else
    cd "$GITHUB_REPO" || exit 1;
    git fetch origin
    git reset --hard origin/master
  fi

  git fetch --tags
  local oldtag=$(git describe --abbrev=0 --tags)
  echo "Current openjdk level is $oldtag"
}

# Clone current openjdk from Mercurial
function cloneMercurialOpenJDKRepo() {
  echo "Get base openjdk repository"
  cd "$WORKSPACE/openjdk/mirror" || exit 1

  if [ ! -d "$OPENJDK_VERSION" ] ; then
    git init
    git clone "hg::${HG_REPO}"
  fi

  cd "$OPENJDK_VERSION" || exit 1
  git fetch origin
  git reset --hard origin/master

  git filter-branch -f --index-filter 'git rm -r -f -q --cached --ignore-unmatch .hg .hgignore .hgtags get_source.sh' --prune-empty --tag-name-filter cat -- --all

  cd "$WORKSPACE/openjdk/mirror" || exit

  git pull "$OPENJDK_VERSION"
  git fetch --tags "$OPENJDK_VERSION"

  # Processing each TAG in turn (including HEAD)
  for NEWTAG in $TAGS ; do
    cd "$WORKSPACE/openjdk/mirror" || exit 1
    git reset --hard "$NEWTAG"

    echo "$(date +%T)": "Updating master branch for $NEWTAG"
    cd "$WORKSPACE/$GITHUB_REPO/$GITHUB_REPO" || exit 1
    git checkout master
    git fetch "$WORKSPACE/openjdk/mirror"
    git merge --allow-unrelated-histories -m "Merge base $NEWTAG" FETCH_HEAD

    for module in "${MODULES[@]}" ; do
      if [ ! -d "$WORKSPACE/openjdk/$module" ]; then
        mkdir -p "$WORKSPACE/openjdk/$module"
        cd "$WORKSPACE/openjdk/$module" || exit 1
        git init
        echo "$(date +%T)": "Clone $module"
        git clone "hg::${HG_REPO}/$module" || exit 1
        echo "$(date +%T)": "GIT filter on $module"
        cd "$module" || exit
        git filter-branch -f --index-filter "git rm -f -q --cached --ignore-unmatch .hgignore .hgtags && git ls-files -s | sed \"s|\t\\\"*|&$module/|\" | GIT_INDEX_FILE=\$GIT_INDEX_FILE.new git update-index --index-info && mv \"\$GIT_INDEX_FILE.new\" \"\$GIT_INDEX_FILE\"" --prune-empty --tag-name-filter cat -- --all
        cd .. || exit
      fi
      echo "$(date +%T)": "GIT pull/reset on $module at $NEWTAG"
      cd "$WORKSPACE/openjdk/$module" || exit 1
      git pull "$module"
      git fetch --tags "$module"
      git reset --hard "$NEWTAG"
      cd "$WORKSPACE/$GITHUB_REPO/$GITHUB_REPO" || exit 1
      if [ ! -d "$WORKSPACE/$GITHUB_REPO/$GITHUB_REPO/$module" ] ; then
        mkdir -p "$WORKSPACE/$GITHUB_REPO/$GITHUB_REPO/$module"
      fi
      cd "$WORKSPACE/$GITHUB_REPO/$GITHUB_REPO/$module" || exit 1
      git fetch "$WORKSPACE/openjdk/$module"
      echo "$(date +%T)": GIT filter on "$module"
      if ! git merge --allow-unrelated-histories -m "Merge $module at $NEWTAG" FETCH_HEAD; then
        if ! tty; then
          echo "Aborting - not running on a real tty therefore cannot allow manual intervention"
          exit 10
        else
          echo "Please resolve them in another window then press return to continue"
          read -r _
        fi
        echo Please resolve the conflicts above in "$WORKSPACE/$GITHUB_REPO/$GITHUB_REPO", and press return to continue
        read -r _
      fi
    done
    cd "$WORKSPACE/$GITHUB_REPO/$GITHUB_REPO" || exit 1
    git push origin master

    echo "Pulling in changes to $GITHUB_REPO branch"
    git checkout master
    git fetch origin master
    if ! git merge --allow-unrelated-histories -m "Merge $NEWTAG into $GITHUB_REPO" FETCH_HEAD; then
      echo Conflict resolution needed in "$WORKSPACE/$GITHUB_REPO/$GITHUB_REPO"
      if ! tty; then
        echo "Aborting - not running on a real tty therefore cannot allow manual intervention"
        exit 10
      else
        echo "Please resolve them in another window then press return to continue"
        read -r _
      fi
    fi
    [ "$NEWTAG" != "HEAD" ] && git tag -f -a "$NEWTAG" -m "Merge $NEWTAG into master"
    echo "Deleting the old version of the tag from the server if it is present or push will fail"
    # shellcheck disable=SC2015
    [ "$NEWTAG" != "HEAD" ] && git push origin :refs/tags/"$NEWTAG" || true
    [ "$NEWTAG" == "HEAD" ] && git push origin master
    [ "$NEWTAG" != "HEAD" ] && git push origin master --tags
  done
}

# TODO Need to cover always merging mercurial master into our GitHub dev branch
checkArgs $#
setMercurialRepoAndTagsToRetrieve
createDirectories
checkGitVersion
installGitRemoteHg
cloneGitOpenJDKRepo
cloneMercurialOpenJDKRepo
performMergeIntoDevFromMaster
