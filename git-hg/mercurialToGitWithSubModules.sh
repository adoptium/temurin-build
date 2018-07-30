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
# Initial repo will be pushed to git@github.com:AdoptOpenJDK/openjdk-$TARGET_REPO.git
#
# TODO Make the location of the git push a parameter
#
################################################################################

set -euxo

# TODO Remove these temp vars later
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
mkdir -p $SCRIPT_DIR/workspace
WORKSPACE=$SCRIPT_DIR/workspace

# REPO_LOCATION     - workspace/adoptopenjdk-clone/      - copy of upstream github repo where new commits will end up
# MIRROR            - workspace/openjdk-clean-mirror     - Unmodified clones of openjdk mercurial (basically a local cache)
# REWRITE_WORKSPACE - workspace/openjdk-rewritten-mirror - Workspace where mercurial is manipulated before being written into the upstream
#                   - workspace/bin                      - Helper third party programs

MIRROR=$WORKSPACE/openjdk-clean-mirror
REWRITE_WORKSPACE=$WORKSPACE/openjdk-rewritten-mirror/
REPO_LOCATION=$WORKSPACE/adoptopenjdk-clone/

if [ -z ${DEBUG_SCRIPT+x} ]; then
  rm -rf "$REWRITE_WORKSPACE"
  mkdir -p "$REWRITE_WORKSPACE"
else
  rm -rf "$REWRITE_WORKSPACE/root"
  rm -rf "$REPO_LOCATION"
fi

echo "Import common functionality"
# shellcheck disable=SC1091
source import-common.sh

function checkArgs() {
  if [ $# -lt 3 ]; then
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

checkArgs $@

# These the the modules in the mercurial forest that we'll have to iterate over
MODULES=(corba langtools jaxp jaxws nashorn jdk hotspot)

# OpenJDK version that we're wanting to mirror, e.g. jdk8u or jdk9u
OPENJDK_VERSION="$1"
shift

# Get the target project, e.g. git@github.com:AdoptOpenJDK
TARGET_PROJECT="$1"
shift

# Get the target repo, e.g. "openjdk-jdk8u"
TARGET_REPO="$1"
shift

# Get a list of optional tags
TAGS="$@"

function setMercurialRepoAndTagsToRetrieve() {
  case "$OPENJDK_VERSION" in
     jdk8*) HG_REPO=http://hg.openjdk.java.net/jdk8u/jdk8u
            # Would be nice to pull out the tags in an automated fashion, but
            # OpenJDK does not provide this yet.
            if [ -z "$TAGS" ] ; then
                TAGS="jdk8u144-b34 jdk8u151-b12 jdk8u152-b16 jdk8u161-b12 jdk8u162-b12 jdk8u171-b03 jdk8u172-b11 jdk8u181-b13"
            fi;;
     jdk9*) HG_REPO=http://hg.openjdk.java.net/jdk-updates/jdk9u

            if [ -z "$TAGS" ] ; then
                TAGS="jdk-9+181 jdk-9.0.1+11 jdk-9.0.3+9 jdk-9.0.4+11"
            fi;;
         *) Unknown JDK version - only jdk8u and jdk9u are supported; exit 1;;
  esac
}

# Clone current Git repo
function cloneGitOpenJDKRepo() {
  echo "Clone current $TARGET_REPO"
  if [ ! -d "$REPO_LOCATION" ] ; then
    mkdir -p "$REPO_LOCATION"
    cd "$REPO_LOCATION"
    git clone "$TARGET_PROJECT/$TARGET_REPO.git" .
    cd "$REPO_LOCATION" || exit 1;
  else
    cd "$REPO_LOCATION"
    git fetch origin
    git reset --hard origin/master
  fi

  commitCount=$(git rev-list --all --count)
  if [ "$commitCount" == "0" ]; then
    git checkout -b master
    touch README.md
    git add README.md
    git commit -a -m "Initial commit"
    git push --set-upstream origin master
  fi

  git checkout master
  git pull --allow-unrelated-histories origin master
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

TMP_WORKSPACE="/tmp/adopt-tmp/"

cleanup () {
  if [ -d "$TMP_WORKSPACE" ]; then
    rm -rf "$TMP_WORKSPACE" || true
  fi

  if [ -d "/dev/shm/adopt/" ]; then
    rm -rf "/dev/shm/adopt/" || true
  fi
  exit $exit_code
}

function updateMirrors() {
  mkdir -p "$MIRROR"
  # Go to the location of the Git mirror of the Mercurial OpenJDK source code
  cd "$MIRROR" || exit 1

  updateRepo "root" "${HG_REPO}"

  for module in "${MODULES[@]}" ; do
      updateRepo "$module" "${HG_REPO}/$module"
  done

  rewriteMirror
}

function rewriteMirror() {
  availableMemory=$(free -mw | grep Mem | egrep -o "[0-9]+$")

  trap cleanup EXIT ERR INT TERM

  if [[ $availableMemory -gt 500 ]]; then
    echo "Detected more than 500mb of ram available, attempting to use ram dist to speed up"
    TMP_WORKSPACE="/dev/shm/adopt/"
  else
    TMP_WORKSPACE="/tmp/adopt-tmp/"
    rm -rf "$TMP_WORKSPACE" || true
  fi

  mkdir -p "$TMP_WORKSPACE" || exit 1

  for module in "${MODULES[@]}" ; do
    needsUpdate=$(doesModuleNeedUpdate "$module")

    # dont rewrite mirror if HEAD in mirror is already merged in
    if [ "$needsUpdate" == "true" ]; then
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

      mkdir "$TMP_WORKSPACE/$module"

      git reset --hard master
      git filter-branch -d "$TMP_WORKSPACE/$module" -f --index-filter "git rm -f -q --cached --ignore-unmatch .hgignore .hgtags && git ls-files -s | sed \"s|\t\\\"*|&$module/|\" | GIT_INDEX_FILE=\$GIT_INDEX_FILE.new git update-index --index-info && mv \"\$GIT_INDEX_FILE.new\" \"\$GIT_INDEX_FILE\"" --prune-empty --tag-name-filter cat -- --all
      rm -rf "$TMP_WORKSPACE/$module" || exit 1
    fi
  done

  rm -rf "$TMP_WORKSPACE" || exit 1
}

function checkoutRoot() {
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
  (git filter-branch -f --index-filter 'git rm -r -f -q --cached --ignore-unmatch .hg .hgignore .hgtags get_source.sh' --prune-empty --tag-name-filter cat -- --all)
}

function fetchRootTagIntoRepo() {
  NEWTAG=$1

  # Go to the openjdk-workingdir and reset to the tag that we want to merge in
  cd "$REWRITE_WORKSPACE/root" || exit 1
  git reset --hard "$NEWTAG"

  # Merge in the base Mercurial source code (sub modules to follow) for the tag
  echo "$(date +%T)": "Updating master branch for $NEWTAG"
  cd "$REPO_LOCATION" || exit 1
  git branch --unset-upstream || true
  git checkout master
  git fetch "$REWRITE_WORKSPACE/root"
  git merge --allow-unrelated-histories -m "Merge base $NEWTAG" FETCH_HEAD
}


function fetchModuleTagIntoRepo() {
  NEWTAG=$1
  module=$2

  needsUpdate=$(doesModuleNeedUpdate "$module")

  if [ "$needsUpdate" == "true" ]; then
    cd "$REWRITE_WORKSPACE/$module"
    newCommitId=$(git rev-list -n 1 "$NEWTAG")

    cd "$MIRROR/$module"
    originalCommitId=$(git rev-list -n 1 "$NEWTAG")

    # Then go to the Adopt clone
    cd "$REPO_LOCATION" || exit 1

    # Now fetch
    if [ "$NEWTAG" == "HEAD" ]
    then
      git fetch "$REWRITE_WORKSPACE/$module" master
    else
      git fetch "$REWRITE_WORKSPACE/$module" "refs/tags/$NEWTAG"
    fi

    echo "$(date +%T)": GIT merge of "$module"
    if ! git merge --allow-unrelated-histories -m "Merge module $module at $NEWTAG. OriginalCommitId: $originalCommitId NewCommitId: $newCommitId" FETCH_HEAD; then
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
  fi
}

function pushTagToMaster() {

  NEWTAG=$1

  # Then push the changes back to master
  cd "$REPO_LOCATION" || exit 1
  git reset --hard master
  git push origin master

  echo "Pulling in changes to $TARGET_REPO branch"

  # Grab anything that someone else may have pushed to the remote
  git fetch origin master
  if ! git merge --allow-unrelated-histories -m "Merge $NEWTAG into $TARGET_REPO" FETCH_HEAD; then
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
}

function doesModuleNeedUpdate() {
  module=$1

  cd "$MIRROR/$module"
  latestCommitInMirror=$(git rev-list -n 1 HEAD)

  cd "$REPO_LOCATION"

  # Merge module $module at $NEWTAG. OriginalCommitId: $originalCommitId NewCommitId: $newCommitId
  mergeCount=$(git log --all --pretty=format:"%H" --grep="Merge module $module at.*OriginalCommitId: $latestCommitInMirror"  | wc -l)

  if [ "$mergeCount" == "0" ]; then
    echo "true"
  else
    echo "false"
  fi
}

# Clone current openjdk from Mercurial
function cloneMercurialOpenJDKRepo() {

  if [ -z ${DEBUG_SCRIPT+x} ]; then
    updateMirrors
  fi

  # Go to the location of the Git mirror of the Mercurial OpenJDK source code
  cd "$REWRITE_WORKSPACE" || exit 1
  checkoutRoot

  for NEWTAG in $TAGS ; do

    cd "$REPO_LOCATION" || exit 1

    # If we already have the tag then don't update anything
    if git tag | grep "^$NEWTAG$" ; then
      echo "Skipping $NEWTAG as it already exists"
    else
      fetchRootTagIntoRepo "$NEWTAG"

      # For each module
      for module in "${MODULES[@]}" ; do
        fetchModuleTagIntoRepo "$NEWTAG" "$module"
      done
      pushTagToMaster "$NEWTAG"
    fi
  done
}

setMercurialRepoAndTagsToRetrieve
checkGitVersion
installGitRemoteHg
cloneGitOpenJDKRepo
cloneMercurialOpenJDKRepo
performMergeIntoDevFromMaster
