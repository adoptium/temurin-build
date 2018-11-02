#!/bin/bash

set -eux

source constants.sh


if [ "$#" -gt 0 ]; then
  TAG="$1"
else
  echo "need tag arg"
  exit 1
fi


cd "$SCRIPT_DIR"

# Update mirrors
./merge.sh -u

cd "$REPO"
git reset --hard
git merge --abort || true
git am --abort || true
git checkout release
git reset --hard


cd $SCRIPT_DIR
# move release branch on i.e move from jdk8u181-b13 to jdk8u192-b12
./merge.sh -t -T "$TAG" -b "release"


