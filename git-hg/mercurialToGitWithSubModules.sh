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
# There are Git two repos involved in the overall operation, which have *no*
# common history.  One is the Git clone of the AdoptOpenJDK GitHub repo for
# $OPENJDK_VERSION (the target). The other is a Git openjdk-workingdir of the Mercurial
# forests at OpenJDK (the source).
#
# The overall technique used is to:
#
# 1. Get a local Git clone of the AdoptOpenJDK GitHub repo
# 2. Get a local Git clone of the OpenJDK Mercurial Forests
# 3. Get to the right tag
# 4. Merge in any changes from the local Git clone of the base OpenJDK Mercurial
#    forest into the Git clone of the AdoptOpenJDK GitHub repo followed by the
#    merging the forests which represent the sub modules (corba, langtools etc).
# 5. Push that merged result back to the AdoptOpenJDK GitHub repo
#
# Repeat 3-5 as needed
#
# As there is no common history between the two repos we have to go to great
# lengths to merge in the changes cleanly including lots of resetting and
# re-writing histories etc.
#
# WARN:  Please do not make changes to this script without discussing on the
# build channel on the AdoptOpenJDK Slack.
#
# Initial repo will be pushed to git@github.com:AdoptOpenJDK/openjdk-$GITHUB_REPO.git
#
# TODO Make the location of the git push a parameter
#
################################################################################

set -euxo

# TODO Remove these temp vars later
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
mkdir -p $SCRIPT_DIR/workspace
WORKSPACE=$SCRIPT_DIR/workspace

MIRROR=$WORKSPACE/openjdk-clean-mirror
REWRITE_WORKSPACE=$WORKSPACE/openjdk-rewritten-mirror/
REPO_LOCATION=$WORKSPACE/adoptopenjdk-clone/

DEBUG_SCRIPT="true"

if [ ! -z ${DEBUG_SCRIPT+x} ]; then
  rm -rf "$REWRITE_WORKSPACE"
  mkdir -p "$REWRITE_WORKSPACE"
else
  rm -rf "$REWRITE_WORKSPACE/root"
  rm -rf "$REPO_LOCATION"
fi

echo "Import common functionality"
# shellcheck disable=SC1091
source import-common.sh

#TARGET_PROJECT=${TARGET_PROJECT:-git@github.com:AdoptOpenJDK}
function checkArgs() {
  if [ $# -lt 2 ]; then
     echo Usage: "$0" '[jdk8u|jdk9u] [TARGET_REPO] (TAGS)'
     echo "If using this script at AdoptOpenJDK, the version supplied should match";
     echo "a repository in a git@github.com:AdoptOpenJDK/openjdk-VERSION repo"
     exit 1
  fi
  if [ -z "$WORKSPACE" ] || [ ! -d "$WORKSPACE" ] ; then
    echo Cannot access \$WORKSPACE: "$WORKSPACE"
    exit 2
  fi
}

# These the the modules in the mercurial forest that we'll have to iterate over
MODULES=(corba langtools jaxp jaxws nashorn jdk hotspot)

# Get the mandatory version that we are wanting to openjdk-workingdir
OPENJDK_VERSION="$1"
shift

# Get the target project
TARGET_PROJECT="$1"
shift

# Get a list of optional tags
TAGS="$@"

# TODO Assumes a naming scheme for target repos that is openjdk-$OPENJDK_VERSION
GITHUB_REPO="openjdk-$OPENJDK_VERSION"

function setMercurialRepoAndTagsToRetrieve() {
  case "$OPENJDK_VERSION" in
     jdk8*) HG_REPO=http://hg.openjdk.java.net/jdk8u/jdk8u
            # Would be nice to pull out the tags in an automated fashion, but
            # OpenJDK does not provide this yet.
            if [ -z "$TAGS" ] ; then
                TAGS="jdk8u144-b34 jdk8u151-b12 jdk8u152-b16 jdk8u161-b12 jdk8u162-b12 jdk8u171-b03 jdk8u172-b11 jdk8u181-b13 HEAD"
            fi;;
     jdk9*) HG_REPO=http://hg.openjdk.java.net/jdk-updates/jdk9u

            if [ -z "$TAGS" ] ; then
                TAGS="jdk-9+181 jdk-9.0.1+11 jdk-9.0.3+9 jdk-9.0.4+11 HEAD"
            fi;;
         *) Unknown JDK version - only jdk8u and jdk9 are supported; exit 1;;
  esac
}

function createDirectories() {
  mkdir -p "$WORKSPACE/$GITHUB_REPO" "$WORKSPACE/openjdk/openjdk-workingdir"
}

# Clone current Git repo
function cloneGitOpenJDKRepo() {
  echo "Clone current $GITHUB_REPO"
  if [ ! -d "$REPO_LOCATION" ] ; then
    mkdir -p "$REPO_LOCATION"
    cd "$REPO_LOCATION"
    git clone "$TARGET_PROJECT/$GITHUB_REPO.git" .
    cd "$REPO_LOCATION" || exit 1;
  else
    cd "$REPO_LOCATION"
    git fetch origin
    git reset --hard origin/master
  fi

  git fetch --tags
  local oldtag=$(git describe --abbrev=0 --tags)
  echo "Current openjdk level is $oldtag"
}


function updateRepo() {
  repoName=$1
  repoLocation=$2


  if [ ! -d "$MIRROR/$repoName/.git" ]; then
    rm -rf "$MIRROR/$repoName" || exit 1
    mkdir -p "$MIRROR/$repoName" || exit 1
    cd "$MIRROR/$repoName"
    git clone "hg::${repoLocation}" .
  fi

  cd "$MIRROR/$repoName"
  git fetch origin
  git pull origin
  git reset --hard origin/master
  git fetch --all

}

function updateMirrors() {
  mkdir -p "$MIRROR"
  # Go to the location of the Git mirror of the Mercurial OpenJDK source code
  cd "$MIRROR" || exit 1

  updateRepo "root" "${HG_REPO}"

  for module in "${MODULES[@]}" ; do
      updateRepo "$module" "${HG_REPO}/$module"
  done

  for module in "${MODULES[@]}" ; do
    # Make a directory to work in
    mkdir -p "$REWRITE_WORKSPACE/$module"
    cd "$REWRITE_WORKSPACE/$module" || exit 1

    # Clone the sub module
    echo "$(date +%T)": "Clone $module"

    git clone "$MIRROR/$module" . || exit 1

    # Get to to the tag that we want
    git fetch --tags
    # This looks a bit odd but trust us, take all files and prepend $module to them
    echo "$(date +%T)": "GIT filter on $module"

    git reset --hard master
    git filter-branch -f --index-filter "git rm -f -q --cached --ignore-unmatch .hgignore .hgtags && git ls-files -s | sed \"s|\t\\\"*|&$module/|\" | GIT_INDEX_FILE=\$GIT_INDEX_FILE.new git update-index --index-info && mv \"\$GIT_INDEX_FILE.new\" \"\$GIT_INDEX_FILE\"" --prune-empty --tag-name-filter cat -- --all
  done

}

# Clone current openjdk from Mercurial
function cloneMercurialOpenJDKRepo() {
  if [ ! -z ${DEBUG_SCRIPT+x} ]; then
    updateMirrors
  fi

  # Go to the location of the Git mirror of the Mercurial OpenJDK source code
  cd "$REWRITE_WORKSPACE" || exit 1

  # If we haven't already mirrored the $OPENJDK_VERSION then git clone
  if [ ! -d "$REWRITE_WORKSPACE/root/.git" ] ; then
    rm -rf "$REWRITE_WORKSPACE/root" || true
    mkdir "$REWRITE_WORKSPACE/root"
    cd "$REWRITE_WORKSPACE/root"
    git clone "$MIRROR/root" .
    git remote set-url origin "file://$MIRROR/root"
  fi

  # Move into the $OPENJDK_VERSION and make sure we're on the latest master
  cd "$REWRITE_WORKSPACE/root" || exit 1
  git pull
  git fetch --all
  git reset --hard origin/master

  # Remove certain Mercurial specific files from history
  git filter-branch -f --index-filter 'git rm -r -f -q --cached --ignore-unmatch .hg .hgignore .hgtags get_source.sh' --prune-empty --tag-name-filter cat -- --all

  # Process each TAG in turn (including HEAD)
  for NEWTAG in $TAGS ; do

    # Go back to where we have the AdoptOpenJDK Git clone to see what we need
    # to merge in from the Git openjdk-workingdir of Mercurial
    cd "$REPO_LOCATION" || exit 1

    # If we already have the tag then don't update anything TODO think about HEAD
    if git tag | grep "^$NEWTAG$" ; then
      echo "Skipping $NEWTAG as it already exists"
    else
      # Go to the openjdk-workingdir and reset to the tag that we want to merge in
      cd "$REWRITE_WORKSPACE/root" || exit 1
      git reset --hard "$NEWTAG"

      # Merge in the base Mercurial source code (sub modules to follow) for the tag
      echo "$(date +%T)": "Updating master branch for $NEWTAG"
      cd "$REPO_LOCATION" || exit 1
      git branch --unset-upstream
      git checkout master
      git fetch "$REWRITE_WORKSPACE/root"
      git merge --allow-unrelated-histories -m "Merge base $NEWTAG" FETCH_HEAD

      # For each module
      for module in "${MODULES[@]}" ; do
        # Then go to the Adopt clone
        cd "$REPO_LOCATION" || exit 1

        # Now fetch
        git fetch "$REWRITE_WORKSPACE/$module" "refs/tags/$NEWTAG"

        echo "$(date +%T)": GIT merge of "$module"
        if ! git merge --allow-unrelated-histories -m "Merge $module at $NEWTAG" FETCH_HEAD; then
          if ! tty; then
            echo "Aborting - not running on a real tty therefore cannot allow manual intervention"
            exit 10
          else
            echo "Please resolve them in another window then press return to continue"
            read -r _
          fi
          echo Please resolve the conflicts above in "$REPO_LOCATION", and press return to continue
          read -r _
        fi
      done

      # Then push the changes back to master
      cd "$REPO_LOCATION" || exit 1
      git reset --hard master
      git push origin master

      echo "Pulling in changes to $GITHUB_REPO branch"

      # Grab anything that someone else may have pushed to the remote
      git fetch origin master
      if ! git merge --allow-unrelated-histories -m "Merge $NEWTAG into $GITHUB_REPO" FETCH_HEAD; then
        echo Conflict resolution needed in "$REPO_LOCATION"
        if ! tty; then
          echo "Aborting - not running on a real tty therefore cannot allow manual intervention"
          exit 10
        else
          echo "Please resolve them in another window then press return to continue"
          read -r _
        fi
      fi

      if [ "$NEWTAG" != "HEAD" ] ; then
        echo "Override existing tag on the tag from the server if it is present or push will fail"
        git tag -f -a "$NEWTAG" -m "Merge $NEWTAG into master"
      fi

      # shellcheck disable=SC2015

      if [ "$NEWTAG" != "HEAD" ] ; then
        git push origin :refs/tags/"$NEWTAG"
      fi

      if [ "$NEWTAG" == "HEAD" ] ; then
        git push origin master
      fi

      if [ "$NEWTAG" != "HEAD" ] ; then
        git push origin master --tags
      fi
    fi
  done
}

checkArgs $@
setMercurialRepoAndTagsToRetrieve
createDirectories
checkGitVersion
installGitRemoteHg
cloneGitOpenJDKRepo
cloneMercurialOpenJDKRepo
performMergeIntoDevFromMaster
