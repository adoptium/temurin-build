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
else
  git clone git@github.com:AdoptOpenJDK/openjdk-jdk8u.git .
  git fetch --all
fi

# Update dev branch
cd "$REPO"
git checkout dev
cd $SCRIPT_DIR
./merge.sh -T "HEAD" -b "dev"

# Update master branch
cd "$REPO"
git checkout master
cd $SCRIPT_DIR
./merge.sh -T "HEAD" -b "master"


