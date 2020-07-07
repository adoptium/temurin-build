#!/bin/bash

set -eux

source constants.sh

# Update mirrors
./merge.sh -u

cd "$REPO"
if [ -d ".git" ];then
  git reset --hard
  git checkout master
  git merge --abort || true
  git am --abort || true
fi

# Update dev branch
cd "$REPO"
git fetch --all --no-tags

if git rev-parse -q --verify "dev" ; then
  git checkout dev
else
  git checkout -b dev upstream/dev
fi

cd $SCRIPT_DIR
./merge.sh -T "HEAD" -b "dev"

# Update master branch
cd "$REPO"
git checkout master
cd $SCRIPT_DIR
./merge.sh -T "HEAD" -b "master"
cd "$REPO"
