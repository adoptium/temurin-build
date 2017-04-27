#!/bin/bash

rm -rf $WORKSPACE/combined $WORKSPACE/hg
mkdir $WORKSPACE/combined
mkdir $WORKSPACE/hg
cd $WORKSPACE/combined
git init
git checkout -b root-commit
git remote add github git@github.com:AdoptOpenJDK/openjdk-jdk9.git
cd -
bash add-branch.sh jdk9/jdk9
