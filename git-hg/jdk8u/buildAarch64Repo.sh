#!/bin/bash

set -eux

HG_REPO="https://hg.openjdk.java.net/aarch64-port/jdk8u-shenandoah"

source constants.sh

function createTag() {
  tag=$1

  cd $REPO
  git tag -d "$tag" || true
  git tag -f "$tag"
  git branch -D "$tag" || true
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
## Init master to be synced at aarch64-shenandoah-jdk8u191-b12
./merge.sh -r -T "aarch64-shenandoah-jdk8u191-b12" -s "${HG_REPO}"
################################################

################################################
## Build dev
## dev branch is HEAD track with our patches
cd "$REPO"

# as repo has just been inited to aarch64-shenandoah-jdk8u191-b12 dev will be at aarch64-shenandoah-jdk8u191-b12
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

# Apply the company patches
cd $REPO
git checkout release
git am --exclude common/autoconf/generated-configure.sh $PATCHES/company_name.patch
git am $PATCHES/0001-Set-vendor-information.patch

chmod +x ./common/autoconf/autogen.sh
./common/autoconf/autogen.sh
git commit -a -m "autogen"

# Create a saner looking tag
createTag "jdk8u181-b13"

cd "$SCRIPT_DIR"
./merge.sh -t -T "aarch64-shenandoah-jdk8u191-b12" -b "release" -s "${HG_REPO}"

# Create a saner looking tag
createTag "jdk8u191-b12"

################################################
