#!/bin/bash

set -eux

source constants.sh

MERGE_ARGS=""

while getopts "a" opt; do
    case "${opt}" in
        a)
            MERGE_ARGS="-a"
            ;;
    esac
done
shift $((OPTIND-1))

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

if git show-ref refs/heads/release; then
    git checkout release
else
    git checkout -b release upstream/release
fi
git reset --hard


cd $SCRIPT_DIR
# move release branch on i.e move from jdk8u181-b13 to jdk8u192-b12
./merge.sh -t -T "$TAG" -b "release" $MERGE_ARGS


