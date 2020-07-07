#!/bin/bash

set -eu

# Set up the workspace to work from
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
mkdir -p "$SCRIPT_DIR/workspace"

export WORKSPACE="$SCRIPT_DIR/workspace"
export MIRROR="$WORKSPACE/openjdk-clean-mirror"
export MODULE_MIRROR="$WORKSPACE/module-mirrors/"
export REWRITE_WORKSPACE="$WORKSPACE/openjdk-rewritten-mirror/"
export REPO_LOCATION="$WORKSPACE/adoptopenjdk-clone/"
export REPO="$WORKSPACE/repo/"
export PATCHES="$SCRIPT_DIR/patches/"

mkdir -p "$REPO"
mkdir -p "$MODULE_MIRROR"

chmod +x "$SCRIPT_DIR/merge.sh"

# These the the modules in the mercurial forest that we'll have to iterate over
export MODULES=(corba langtools jaxp jaxws nashorn jdk hotspot)
export MODULES_WITH_ROOT=(root corba langtools jaxp jaxws nashorn jdk hotspot)
