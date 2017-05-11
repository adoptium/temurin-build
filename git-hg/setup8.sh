#!/bin/bash
#shellcheck disable=SC2086
#shellcheck disable=SC2164
#shellcheck disable=SC2103
rm -rf $WORKSPACE/combined $WORKSPACE/hg
mkdir $WORKSPACE/combined
mkdir $WORKSPACE/hg
cd $WORKSPACE/combined
git init
git checkout -b root-commit
git remote add github git@github.com:AdoptOpenJDK/openjdk-jdk8u.git
cd -
bash add-branch.sh jdk8u/jdk8u
