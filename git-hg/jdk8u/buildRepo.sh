#!/bin/bash

set -eux

source constants.sh

cd "$REPO"

if [ -d ".git" ];then
  git reset --hard
  git checkout master
  git merge --abort || true
  git am --abort || true
fi

cd "$SCRIPT_DIR"

# update mirrors
./merge.sh -u


################################################
## Build master
## Init master to be synced at jdk8u181-b13
./merge.sh -r -T "jdk8u181-b13"
################################################



################################################
## Build dev
## dev branch is HEAD track with our patches
cd "$REPO"

# as repo has just been inited to jdk8u181-b13 dev will be at jdk8u181-b13
git checkout -b dev

# Apply our patches
git am $PATCHES/company_name.patch

cd $SCRIPT_DIR

# Update dev to HEAD
./merge.sh -T "HEAD" -b "dev"
################################################



################################################
## Push master up to head
cd "$REPO"
git checkout master

cd $SCRIPT_DIR

# Update dev to HEAD
./merge.sh -T "HEAD" -b "master"
################################################



################################################
## Build release
## release moves from tag to tag with our patches
cd "$SCRIPT_DIR"

./merge.sh -t -i -T "jdk8u144-b34" -b "release"
./merge.sh -t -T "jdk8u162-b12" -b "release"
./merge.sh -t -T "jdk8u172-b11" -b "release"
./merge.sh -t -T "jdk8u181-b13" -b "release"

cd $REPO
git checkout release
git am $PATCHES/company_name.patch
git am $PATCHES/ppc64le_1.patch
git am $PATCHES/ppc64le_2.patch

git tag -d "jdk8u181-b13" || true
git tag -f "jdk8u181-b13"
git branch -D "jdk8u181-b13"
git branch "jdk8u181-b13"

cd $SCRIPT_DIR
./merge.sh -t -T "jdk8u192-b12" -b "release"
################################################


