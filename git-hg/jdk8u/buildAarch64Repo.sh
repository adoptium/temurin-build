#!/bin/bash

set -eux

HG_REPO="https://hg.openjdk.java.net/aarch64-port/jdk8u"

source constants.sh

function createTag() {
  tag=$1
  git tag -d "$tag" || true
  git tag -f "$tag"
  git branch -D "$tag"
  git branch "$tag"
}

cd "$REPO"

if [ -d ".git" ];then
  git reset --hard
  git checkout master
  git merge --abort || true
  git am --abort || true
fi

cd "$SCRIPT_DIR"

# update mirrors
./merge.sh -u -s "${HG_REPO}"

################################################
## Build master
## Init master to be synced at aarch64-jdk8u181-b13
./merge.sh -r -T "aarch64-jdk8u181-b13" -s "${HG_REPO}"
################################################

################################################
## Build dev
## dev branch is HEAD track with our patches
cd "$REPO"

# as repo has just been inited to jdk8u181-b13 dev will be at jdk8u181-b13
git checkout -b dev

# Apply our patches
git am $PATCHES/company_name.patch
git am $PATCHES/0001-Set-vendor-information.patch

# Update dev to head
cd $SCRIPT_DIR
./merge.sh -T "HEAD" -b "dev" -s "${HG_REPO}"
################################################

################################################
## Push master up to head
cd "$REPO"
git checkout master

cd $SCRIPT_DIR

# Update dev to HEAD
./merge.sh -T "HEAD" -b "master" -s "${HG_REPO}"
################################################

################################################
## Build release
## release moves from tag to tag with our patches
cd "$SCRIPT_DIR"

# sync and tag the release branch as some key milestones
./merge.sh -t -i -T "jdk8u172-b11" -b "release" -s "${HG_REPO}"
./merge.sh -t -T "aarch64-jdk8u181-b13" -b "release" -s "${HG_REPO}"

cd $REPO
git checkout release
git am $PATCHES/company_name.patch
git am $PATCHES/0001-Set-vendor-information.patch

createTag "jdk8u181-b13"

################################################
