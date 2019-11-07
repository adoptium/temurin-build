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

set -euxo pipefail

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

# Determine latest build TAG_SEARCH, finding tags beginning with "jdk-" followed by ... "+" ...
if [ "$HG_REPO" == "jdk/jdk" ]
then
  TAG_SEARCH="jdk-*+*"
elif [ "$HG_REPO" == "jdk-updates/jdk13u" ]
then
  TAG_SEARCH="jdk-13*+*"
elif [ "$HG_REPO" == "jdk-updates/jdk12u" ]
then
  TAG_SEARCH="jdk-12*+*"
elif [ "$HG_REPO" == "jdk-updates/jdk11u" ]
then
  TAG_SEARCH="jdk-11*+*"
else
  echo "Unable to determine latest build tag TAG_SEARCH for repo: $HG_REPO"
  exit 1
fi

# JDK11+ tag sorting:
# We use sort and tail to choose the latest tag in case more than one refers the same commit.
# Versions tags are formatted: jdk-V[.W[.X]]+B; with V, W, X, B being numeric.
# Transform "-" to "." in tag so we can sort as: "jdk.V[.W[.X]]+B"
#
# Example: jdk-11.0.2+2, jdk-11.0.1+3, jdk-11.0.2+1
# Sort by "B": jdk-11.0.2+1, jdk-11.0.2+2, jdk-11.0.1+3
# Then, "Stable" sort by V.W.X: jdk-11.0.1+3, jdk-11.0.2+1, jdk-11.0.2+2
# Latest = jdk-11.0.2+2
#
# First, sort on build number (B):
jdk11plus_tag_sort1="sort -t+ -k2n"
# Second, (stable) sort on (V), (W), (X):
jdk11plus_tag_sort2="sort -t. -k2n -k3n -k4n -s"
jdk11plus_sort_tags_cmd="grep -v _adopt | sed 's/jdk-/jdk./g' | $jdk11plus_tag_sort1 | $jdk11plus_tag_sort2 | sed 's/jdk./jdk-/g'"


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
  git fetch hg --tags

  git merge hg/"$BRANCH" -m "Merge $BRANCH" || (echo "The automatic update failed, time for manual intervention!" && exit 1)

  if git rev-parse -q --verify "origin/$BRANCH"; then
    echo "====Commit diff for branch $BRANCH===="
    git --no-pager log --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr)%Creset' --abbrev-commit --date=relative $BRANCH..origin/$BRANCH
    echo "======================================"
  else
    # In the case this is a new repo, chunk uploads into 5000 commit chunks
    git log --reverse --pretty=format:"%H"  | split -l 5000 --filter="tail -n1" | while read sha; do
      echo "Pushing $sha";
      git push origin $sha:refs/heads/master
    done
  fi

  git push -u origin "$BRANCH" || exit 1
  git push origin "$BRANCH" --tags || exit 1
}

# Merge master(HEAD) into dev as we build off dev at the AdoptOpenJDK Build farm for Nightlies
# dev contains patches that AdoptOpenJDK has beyond upstream OpenJDK
function performMergeIntoDevFromMaster() {

  # Abort existing merge
  git merge --abort || true
  git reset --hard || true

  # Fetch latest and get latest master build tag
  git fetch --all --tags

  if ! git checkout -f dev ; then
    if ! git rev-parse -q --verify "origin/dev" ; then
      git checkout -b dev || exit 1
    else
      git checkout -b dev origin/dev || exit 1
    fi
  else
    git reset --hard origin/dev || echo "Not resetting as no upstream exists"
  fi

  devTags=$(git tag --merged dev $TAG_SEARCH || exit 1)
  currentDevTag=$(echo "$devTags" | eval "$jdk11plus_sort_tags_cmd" | tail -1 || exit 1)
  echo "Current dev build tag: $currentDevTag"

  # Merge master "HEAD"
  echo "Merging origin/$BRANCH HEAD into dev branch"
  git merge -m"Merging origin/$BRANCH HEAD into dev" origin/"$BRANCH" || exit 1

  # Merge latest patches from "release" branch
  git merge -m"Merging latest patches from release branch" origin/release || exit 1

  if git rev-parse -q --verify "origin/dev" ; then
    git --no-pager log --oneline origin/dev..dev
  fi

  devTags=$(git tag --merged dev $TAG_SEARCH || exit 1)
  currentDevTag=$(echo "$devTags" | eval "$jdk11plus_sort_tags_cmd" | tail -1 || exit 1)
  echo "New dev build tag: $currentDevTag"

  git push origin dev || exit 1
}


# Merge master(New tagged builds only) into release branch as we build
# off release branch at the AdoptOpenJDK Build farm for release builds
# release branch contains patches that AdoptOpenJDK has beyond upstream OpenJDK tagged builds
function performMergeIntoReleaseFromMaster() {

  # Abort existing merge
  git merge --abort || true
  git reset --hard || true

  # Fetch latest and get latest master build tag
  git fetch --all --tags

  buildTags=$(git tag --merged origin/"$BRANCH" $TAG_SEARCH || exit 1)
  sortedBuildTags=$(echo "$buildTags" | eval "$jdk11plus_sort_tags_cmd" || exit 1)

  if ! git checkout -f release ; then
    if ! git rev-parse -q --verify "origin/release" ; then
      currentBuildTag=$(echo "$buildTags" | eval "$jdk11plus_sort_tags_cmd" | tail -1 || exit 1)
      git checkout -b release $currentBuildTag || exit 1
    else
      git checkout -b release origin/release || exit 1
    fi
  else
    git reset --hard origin/release || echo "Not resetting as no upstream exists"
  fi

  releaseTags=$(git tag --merged release $TAG_SEARCH || exit 1)
  currentReleaseTag=$(echo "$releaseTags" | eval "$jdk11plus_sort_tags_cmd" | tail -1 || exit 1)
  echo "Current release build tag: $currentReleaseTag"

  # Merge any new builds since current release build tag
  foundCurrentReleaseTag=false
  for tag in $sortedBuildTags; do
    if [[ "$foundCurrentReleaseTag" == false ]]; then
      if [ "x$tag" == "x$currentReleaseTag" ]; then
        foundCurrentReleaseTag=true
      fi
    else
      mergeTag=true
      # Check if tag is in the releaseTagExcludeList, if so do not bring it into the release branch
      # and do not create an _adopt tag
      if [ ! -z "$releaseTagExcludeList" ] ; then
        for skipTag in $releaseTagExcludeList; do
          if [ "x$tag" == "x$skipTag" ]; then
           mergeTag=false
           echo "Skipping merge of excluded tag $tag"
          fi
        done
      fi
      if [[ "$mergeTag" == true ]]; then
        echo "Merging build tag $tag into release branch"
        git merge -m"Merging $tag into release" $tag || exit 1
        git tag -a "${tag}_adopt" -m "Merged $tag into release" || exit 1
      fi
    fi
  done

  if git rev-parse -q --verify "origin/release" ; then
    git --no-pager log --oneline origin/release..release
  fi

  releaseTags=$(git tag --merged release $TAG_SEARCH || exit 1)
  currentReleaseTag=$(echo "$releaseTags" | eval "$jdk11plus_sort_tags_cmd" | tail -1 || exit 1)
  echo "New release build tag: $currentReleaseTag"

  git push origin release || exit 1
}

checkArgs $#
#checkGitVersion
installGitRemoteHg
cloneGitHubRepo
addMercurialUpstream
performMergeFromMercurialIntoGit
performMergeIntoReleaseFromMaster
performMergeIntoDevFromMaster

git push --tags origin
