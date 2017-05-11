#!/bin/bash

rm -rf "$WORKSPACE"/combined "$WORKSPACE"/hg
mkdir "$WORKSPACE"/combined
mkdir "$WORKSPACE"/hg
cd "$WORKSPACE"/combined || exit
git init
git checkout -b root-commit
git remote add github git@github.com:AdoptOpenJDK/openjdk-jdk8u.git
cd - || exit
bash add-branch.sh jdk8u/jdk8u
