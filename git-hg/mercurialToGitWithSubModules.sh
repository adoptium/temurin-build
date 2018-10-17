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
# 2 along with this work; if not, see <https://www.gnu.org/licenses/>.
#
# ===========================================================================

################################################################################
# mercurialToGitWithSubModules
#
# Create a Git clone of a OpenJDK mercurial repository for Java 8/9 complete
# with tags and commit history.
#
# There are three repos involved in the overall operation
#
# REPO_LOCATION     - workspace/adoptopenjdk-clone/      - copy of upstream github repo where new commits will end up
# MIRROR            - workspace/openjdk-clean-mirror     - Unmodified clones of openjdk mercurial (basically a local cache)
# REWRITE_WORKSPACE - workspace/openjdk-rewritten-mirror - Workspace where mercurial is manipulated before being written into the upstream
#                   - workspace/bin                      - Helper third party programs
#
# The overall technique used is to:
#
# 1. Setup what tags and modules we want to clone
# 2. Check / Download some tooling we need
# 3. Git clone the remote upstream where we eventually want to push REPO_LOCATION
# 4. Clone / Update $MIRROR
# 5. Rewrite git commits from the $MIRROR into $REWRITE_WORKSPACE which takes
#    care of things like prefixing the module name for sub forests.
# 6  Merge the changes in $REWRITE_WORKSPACE into $REPO_LOCATION
# 7. Push that merged result back to the remote upstream of REPO_LOCATION
#
# WARN: Please do not make changes to this script without discussing on the
# build channel on the AdoptOpenJDK Slack.
#
# TODO: Due to the interleaving of commits in mercurial for CPU and PSU updates
# e.g. jdk8u151+b12 and jdk152+b16 this script does not gracefully handle
# merging in both.  We recommend following a CPU or PSU strategy only.
#
################################################################################

set -euxo

# Set up the workspace to work from
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

# Setup workspace to work in.
function setupWorkingDir() {
  if [ -z ${DEBUG_SCRIPT+x} ]; then
    rm -rf "$REWRITE_WORKSPACE"
    mkdir -p "$REWRITE_WORKSPACE"
  else
    rm -rf "$REWRITE_WORKSPACE/root"
    rm -rf "$REPO_LOCATION"
  fi
}

setupWorkingDir

echo "Import common functionality"
# shellcheck disable=SC1091
source import-common.sh

function checkArgs() {
  if [ $# -lt 3 ]; then
     echo Usage: "$0" '[jdk8u|jdk9u] [SOURCE REPO] [TARGET_PROJECT] [TARGET_REPO] (TAGS)'
     echo ""
     echo "e.g. ./mercurialToGitWithSubModules.sh https://hg.openjdk.java.net/jdk8u/jdk8u jdk8u git@github.com:AdoptOpenJDK openjdk-jdk8u jdk8u172-b11 jdk8u181-b13 HEAD"
     echo ""
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

# The source repo that we're wanting to mirror, e.g. jdk8u or jdk9u
HG_REPO="$1"
shift

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
     jdk8*) # If it's the aarch64 port then they have their own special tag name for 181-b13
            # TODO Exact URL matching is brittle
            if [ ${HG_REPO} == *"aarch64-port"* ] ; then
                TAG_181="aarch64-jdk8u181-b13"
            else
                TAG_181="jdk8u181-b13"
            fi

            # HEAD is interpreted by the script below to mean tip/latest commit.
            # Skipping jdk8u152-b16 as it seems to be problematic
            if [ -z "$TAGS" ] ; then
                TAGS="jdk8u192-b12 HEAD"
            fi;;
     jdk9*) if [ -z "$TAGS" ] ; then
                TAGS="jdk-9+181 jdk-9.0.1+11 jdk-9.0.3+9 jdk-9.0.4+11 HEAD"
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
  if [ "$commitCount" == 0 ]; then
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

function updateMirrors() {
  mkdir -p "$MIRROR"
  cd "$MIRROR" || exit 1

  updateRepo "root" "${HG_REPO}"

  for module in "${MODULES[@]}" ; do
      updateRepo "$module" "${HG_REPO}/$module"
  done

  rewriteMirror
}

function rewriteMirror() {

  # clean out old tmp dirs if left around
  rm -rf "/dev/shm/adopt/" "/tmp/adopt-tmp/"

  # If running locally on Mac OS X then use availableMemory=400
  availableMemory=$(free -mw | grep Mem | egrep -o "[0-9]+$")

  for module in "${MODULES[@]}" ; do
    needsUpdate=$(doesModuleNeedUpdate "$module")

    # dont rewrite mirror if HEAD in mirror is already merged in
    if [ "$needsUpdate" == "true" ]; then

      mkdir -p "$REWRITE_WORKSPACE/$module"
      cd "$REWRITE_WORKSPACE/$module" || exit 1

      # Clone the sub module
      echo "$(date +%T)": "Clone $module"
      git clone "$MIRROR/$module" . || exit 1

      # Get to to the tag that we want
      git fetch --tags

      echo "$(date +%T)": "GIT filter on $module"
      git reset --hard master

      # This looks a bit odd but trust us, take all files and prepend $module to them
      prefix_module_sed="s|$(printf '\t')\\\"*|&$module/|"
      git filter-branch -f --index-filter "git rm -f -q --cached --ignore-unmatch .hgignore .hgtags && git ls-files -s | sed \"$prefix_module_sed\" | GIT_INDEX_FILE=\$GIT_INDEX_FILE.new git update-index --index-info && mv \"\$GIT_INDEX_FILE.new\" \"\$GIT_INDEX_FILE\"" --prune-empty --tag-name-filter cat -- --all
    fi
  done
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

  git filter-branch -f --index-filter 'git rm -r -f -q --cached --ignore-unmatch .hg .hgignore .hgtags get_source.sh' --prune-empty --tag-name-filter cat -- --all
}


function fixGeneratedConfigure() {
  # Since generated-configure.sh contains a timestamp it is a frequent source of merge conflicts
  # if we have a conflict, regenerate that file
  local result=$1

  if [ $result != 0 ]
  then
    local num_conflicts=$(git status | grep "both modified:" | wc -l)
    local is_generated=$(git status | grep "both modified:.*generated-configure.sh" | wc -l)

    if [ $num_conflicts == 1 ] && [ $is_generated == 1 ]
    then
      # we have a conflict, regenerate the file
      ./common/autoconf/autogen.sh
      git commit -a --no-edit
    else
      echo "Merge conflicts"
      git status
      exit 1
    fi

  fi
}

function fetchRootTagIntoRepo() {
  NEWTAG=$1

  cd "$REWRITE_WORKSPACE/root" || exit 1
  git reset --hard "$NEWTAG"

  echo "$(date +%T)": "Updating master branch for $NEWTAG"
  cd "$REPO_LOCATION" || exit 1
  git branch --unset-upstream || true
  git checkout master
  git fetch "$REWRITE_WORKSPACE/root"

  set +x
  git merge --allow-unrelated-histories -m "Merge base $NEWTAG" FETCH_HEAD
  local result=$?
  set -x
  fixGeneratedConfigure $result
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

    cd "$REPO_LOCATION" || exit 1

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

  # Merge module $module at $NEWTAG. OriginalCommitId: $originalCommitId NewCommitId: $newCommitId, tr -d is for Mac OS X
  mergeCount=$(git log --all --pretty=format:"%H\n" --grep="Merge module $module at.*OriginalCommitId: $latestCommitInMirror" 2>&1 | wc -l)

  if [ "$mergeCount" == 0 ]; then
    echo "true"
  else
    echo "false"
  fi
}

function cloneMercurialOpenJDKRepo() {

  if [ -z ${DEBUG_SCRIPT+x} ]; then
    updateMirrors
  fi

  cd "$REWRITE_WORKSPACE" || exit 1
  checkoutRoot

  for NEWTAG in $TAGS ; do

    cd "$REPO_LOCATION" || exit 1

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