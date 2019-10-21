#!/usr/bin/env bash

# Script to facilitate automatic merging of changes from the AdoptOpenJDK
# repos into child repos

# The reference AdoptOpenJDK repos
export ADOPT_REPO_PATH=git@github.com:AdoptOpenJDK
# This script could be made to sync any child by passing this in as an arg
export CHILD_REPO_PATH=git@github.com:freebsd
# Branch to be synchronised
# Note: the dev branch is the branch that AdoptOpenJDK builds from
export SYNC_BRANCH=dev

# How to use this script
usage() {
	echo "Usage: sync <version>" 1>&2
	echo "Where <version> is a valid Java version, e.g. 8, 11" 1>&2
}

# Initialise the repo to be sync'ed
initRepo() {
	if [ -d ${REPO} ]; then
		cd ${REPO}
		git pull || exit 1
		git reset --hard origin/${SYNC_BRANCH} || exit 1
	else
		git clone ${CHILD_REPO_PATH}/${REPO}.git || exit 1
		cd ${REPO}
		git checkout ${SYNC_BRANCH} || exit 1
	fi
}

# Verify that we have a parent
verifyParent() {
	if ! git config remote.upstream.url > /dev/null; then
		git remote add upstream ${ADOPT_REPO_PATH}/${REPO}.git || exit 1
	fi

	if [ "x$(git config remote.upstream.url)" != "x${ADOPT_REPO_PATH}/${REPO}.git" ]; then
		echo "WARNING: 'upstream' doesn't point to AdoptOpenJDK parent" 1>&2
	fi
}

# Fetch all parent changes, including tags
fetchParent() {
	git fetch --all || exit 1
	git fetch upstream --tags || exit 1
}

# Merge in changes from the parent
mergeRepo() {
	git merge -m "Merge from AdoptOpenJDK ${SYNC_BRANCH}" upstream/${SYNC_BRANCH} || exit 1
}

# Push
pushMerge() {
	git push || exit 1
	git push --tags || exit 1
}

export REPO=
case $1 in
	8|9|1[0-9])
		export REPO=openjdk-jdk${1}u
		;;
	*)
		usage
		exit 1
esac

echo "Common defs"

. import-common.sh

checkGitVersion

echo "Initialising repo"

initRepo

echo "Verifying parent"

verifyParent

echo "Fetching parent"

fetchParent

echo "Merge changes"

mergeRepo

echo "Push"

pushMerge
