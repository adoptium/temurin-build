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
# mirrorMercurialIntoGit
#
# Local setup of the Git clone of a OpenJDK mercurial repository
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

# Make sure we're in a valid dir as a workspace
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
mkdir -p $SCRIPT_DIR/workspace
WORKSPACE=$SCRIPT_DIR/workspace

# TODO generalise this for the non adopt build farm case
function checkArgs() {
  if [ "$1" -lt 1 ]; then
     echo Usage: "$0" '[jdk-updates/jdk10u|jdk/jdk] (branch)'
     echo "Hg Repo supplied should match a repository in https://hg.openjdk.java.net/"
     echo "For example, to get the latest jdk development repo:"
     echo "$0 jdk/jdk"
     echo "For example, to get the raw-string-literals branch from the amber repo:"
     echo "e.g. $0 amber/jdk raw-string-literals"
     exit 1
  fi
}

# Read in the mandatory Mercurial repo, e.g. jdk-updates/jdk10u
# Default to a master branch if one is not given
HG_REPO=$1
GITHUB_REPO=$(echo "$HG_REPO" | cut -d/ -f2)
BRANCH=${2:-master}

function cloneGitHubRepo() {
  cd "$WORKSPACE" || exit 1
  # If we don't have a $GITHUB_REPO locally then clone it from AdoptOpenJDK/openjdk-$GITHUB_REPO.git
  if [ ! -d "$GITHUB_REPO" ] ; then
    git clone git@github.com:AdoptOpenJDK/openjdk-"$GITHUB_REPO".git "$GITHUB_REPO" || exit 1
  fi
}

function addMercurialUpstream() {
  cd "$WORKSPACE/$GITHUB_REPO" || exit 1

  git fetch --all
  if ! git checkout -f "$BRANCH" ; then
    if ! git rev-parse -q --verify "origin/$BRANCH" ; then
      git checkout -b "$BRANCH" || exit 1
    else
      git checkout -b "$BRANCH" origin/"$BRANCH" || exit 1
    fi
  else
    git reset --hard origin/"$BRANCH" || echo "Not resetting as no upstream exists"
  fi

  # shellcheck disable=SC2143
  if [ -z "$(git remote -v | grep 'hg')" ] ; then
    echo "Initial setup of hg::https://hg.openjdk.java.net/$HG_REPO"
    git remote add hg hg::https://hg.openjdk.java.net/"$HG_REPO"
  fi
}

function performMergeFromMercurialIntoGit() {
  git fetch hg
  git merge hg/"$BRANCH" -m "Merge $BRANCH" || (echo "The automatic update failed, time for manual intervention!" && exit 1)


  if git rev-parse -q --verify "origin/$BRANCH"; then
    echo "====Commit diff for branch $BRANCH===="
    git log --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr)%Creset' --abbrev-commit --date=relative $BRANCH..origin/$BRANCH
    echo "======================================"

    git push origin "$BRANCH" || exit 1
    git push origin "$BRANCH" --tags || exit 1
  else
    # In the case this is a new repo, chunk uploads
    git log --pretty=format:"%H"  upstream/master...fix-hg
  fi

}

# Merge master into dev as we build off dev at the AdoptOpenJDK Build farm
# dev contains patches that AdoptOpenJDK has beyond upstream OpenJDK
function performMergeIntoDevFromMaster() {

  # Abort existing rebase
  git rebase --abort || true
  git reset --hard || true

  git fetch --all
  if ! git checkout -f dev ; then
    if ! git rev-parse -q --verify "origin/dev" ; then
      git checkout -b dev || exit 1
    else
      git checkout -b dev origin/dev || exit 1
    fi
  else
    git reset --hard origin/dev || echo "Not resetting as no upstream exists"
  fi

  # Rebase master onto dev


  # Create tmp branch from master
  git branch -D dev-tmp || true
  git checkout -b dev-tmp master

  # place master commits on the end of dev
  git rebase dev || exit 1

  # copy commits into dev
  git checkout dev
  git rebase dev-tmp || exit 1

  git branch -D dev-tmp || true

  if git rev-parse -q --verify "origin/dev" ; then
    git log --oneline origin/dev..dev
  fi

  git push origin dev || exit 1
}

checkArgs $#
#checkGitVersion
installGitRemoteHg
cloneGitHubRepo
addMercurialUpstream
performMergeFromMercurialIntoGit
performMergeIntoDevFromMaster
