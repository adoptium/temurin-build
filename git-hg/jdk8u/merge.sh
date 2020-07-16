#!/usr/bin/env bash

set -exu

source constants.sh

acceptUpstream="false"
doRebuildLocalRepo="false"
doInit="false"
doReset="false"
doTagging="false"
doUpdate="false"
if [ -z ${HG_REPO} ]; then
  hgRepo="https://hg.openjdk.java.net/jdk8u/jdk8u"
else 
  hgRepo="$HG_REPO"
fi
tag="jdk8u172-b08"
workingBranch="master"

function initRepo() {
  tag=$1

  rm -rf "$REPO"
  mkdir -p "$REPO"
  cd "$REPO"
  git clone $MIRROR/root/ .
  git checkout master
  git reset --hard "$tag"
  addRemotes

  for module in "${MODULES[@]}" ; do
      cd "$MIRROR/$module/";
      git checkout master
      git reset --hard
  done
  git fetch --all

  cd "$REPO"
  git tag | while read tag
  do
    git tag -d $tag || true
  done

  git fetch upstream --tags
}

function addRemotes() {

  cd "$REPO"
  if ! git config remote.upstream.url > /dev/null; then
    git remote add "upstream" $UPSTREAM_GIT_REPO
  fi

  if ! git config remote.root.url > /dev/null; then
    git remote add "root" "$MIRROR/root/"
  fi

  git fetch --all
  git fetch upstream --tags
}

function inititialCheckin() {
  tag=$1
  cd "$REPO"
  if [ "$workingBranch" != "master" ]; then
    git branch -D "$workingBranch" || true
    git checkout --orphan "$workingBranch"
    git rm -rf .
  else
    git checkout master
  fi

  if [ "$tag" != "HEAD" ]; then
    git fetch root --no-tags +refs/tags/$tag:refs/tags/$tag-root
    git merge "$tag-root"
  else
    git fetch root --no-tags HEAD
    git merge HEAD
  fi

  if [ "$doTagging" == "true" ]; then
    git tag -d $tag || true
  fi

  for module in "${MODULES[@]}" ; do
      cd "$REPO"
      git subtree add --prefix=$module "$MIRROR/$module/" $tag
  done

  cd "$REPO"
  git tag | while read tag
  do
    git tag -d $tag || true
  done
  git fetch upstream --tags
}

function updateRepo() {
  repoName=$1
  repoLocation=$2

  if [ ! -d "$MIRROR/$repoName/.git" ]; then
    rm -rf "$MIRROR/$repoName" || exit 1
    mkdir -p "$MIRROR/$repoName" || exit 1
    cd "$MIRROR/$repoName"
    git clone "hg::${repoLocation}" .
  fi

  addRemotes

  cd "$MIRROR/$repoName"
  git fetch origin
  git pull origin
  git reset --hard origin/master
  git fetch --all
  git fetch --tags

}

# Builds a local repo on a new machine by pulling down the existing remote repo
function rebuildLocalRepo() {
    hgRepo=$1

    # Steps required to build a new host
    #
    # 1. Clone upstream mirrors (done by updateMirrors function)
    #
    # 2. Pull adopt repo down into $REPO
    #
    # 3. Set up remotes on $REPO
    #     Remotes should look as follows:
    #       upstream: git@github.com:AdoptOpenJDK/openjdk-jdk8u.git (or aarch)
    #       root:     "$MIRROR/root/"
    #       origin:   "$MIRROR/root/"
    #

    # Step 1 Clone mirrors
    updateMirrors $hgRepo

    # Step 2, Reclone upstream repo
    rm -rf "$REPO" || true
    mkdir -p "$REPO"
    cd "$REPO"
    git clone $UPSTREAM_GIT_REPO .
    git checkout master || git checkout -b master

    # Step 3 Setup remotes
    addRemotes

    # Remove any incorrect local tags we have
    git tag -l | xargs git tag -d
    git fetch --tags

    # Ensure origin is correct
    cd "$REPO"
    git remote set-url origin "$UPSTREAM_GIT_REPO"

    # Repoint origin from the upstream repo to root module
    cd "$REPO"
    git remote set-url origin "$MIRROR/root/"
}

# We pass in the repo we want to mirror as the first arg
function updateMirrors() {

  HG_REPO=$1

  mkdir -p "$MIRROR"
  cd "$MIRROR" || exit 1

  updateRepo "root" "${HG_REPO}"

  for module in "${MODULES[@]}" ; do
      updateRepo "$module" "${HG_REPO}/$module"
  done
}

function fixAutoConfigure() {
    chmod +x ./common/autoconf/autogen.sh
    ./common/autoconf/autogen.sh
    git commit -a --no-edit
}

while getopts "ab:irtls:T:u" opt; do
    case "${opt}" in
        a)
            acceptUpstream="true"
            ;;
        b)
            workingBranch=${OPTARG}
            ;;
        i)
            doInit="true"
            ;;
        r)
            doReset="true"
            doInit="true"
            ;;
        l)
            doRebuildLocalRepo="true"
            ;;
        s)
            hgRepo=${OPTARG}
            ;;
        t)
            doTagging="true"
            ;;
        T)
            tag=${OPTARG}
            ;;
        u)
            doUpdate="true"
            ;;
        *)
            usage
            exit
            ;;
    esac
done
shift $((OPTIND-1))

if [ "$doRebuildLocalRepo" == "true" ]; then
    rebuildLocalRepo $hgRepo
    exit
fi

if [ "$doUpdate" == "true" ]; then
  updateMirrors $hgRepo
  exit
fi

if [ "$doReset" == "true" ]; then
  initRepo $tag
fi

if [ "$doInit" == "true" ]; then
  inititialCheckin $tag
  exit
fi

echo "$tag" >> $WORKSPACE/mergedTags

cd "$MIRROR/root/";
commitId=$(git rev-list -n 1  $tag)

cd "$REPO"
git merge --abort || true
git rebase --abort || true
git checkout $workingBranch

# Get rid of existing tag that we are about to create
if [ "$doTagging" == "true" ]; then
  git tag -d $tag || true
fi

if [ "$tag" != "HEAD" ]; then
  git fetch --no-tags root +refs/tags/$tag:refs/tags/$tag-root
else
  git fetch --no-tags root HEAD
fi

set +e
git merge -q -m "Merge root at $tag" $commitId
returnCode=$?
set -e

if [[ "$returnCode" -ne "0" ]]; then
  if [ "$(git diff --name-only --diff-filter=U | wc -l)" == "1" ] && [ "$(git diff --name-only --diff-filter=U)" == "common/autoconf/generated-configure.sh" ];
  then
    fixAutoConfigure
  else
    echo "Conflicts"
    exit 1
  fi
fi

cd "$REPO"
for module in "${MODULES[@]}" ; do
    set +e
    git subtree pull -q -m "Merge $module at $tag" --prefix=$module "$MIRROR/$module/" $tag

    if [ $? != 0 ]; then
      if [ "$acceptUpstream" == "true" ]; then
        git diff --name-only --diff-filter=U | xargs git checkout --theirs
        git commit -a -m "Resolve conflicts on module $module when merging tag $tag"
      else
        echo "Failed to merge in module $module"
        exit 1
      fi
    fi

    set -e
done

echo "Success $tag" >> $WORKSPACE/mergedTags

if [ "$doTagging" == "true" ]; then
  cd "$REPO"
  git tag -d "$tag" || true
  git branch -D "$tag" || true
  git branch "$tag"
  git tag -f "$tag"
fi

cd "$REPO"

# Remove temporary tags
git tag | grep ".*\-root" | while read tag
do
  git tag -d $tag || true
done

git prune
git gc

