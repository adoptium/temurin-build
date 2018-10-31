#!/bin/bash

set -eux

# Set up the workspace to work from
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
mkdir -p "$SCRIPT_DIR/workspace"
WORKSPACE="$SCRIPT_DIR/workspace"
MIRROR="$WORKSPACE/openjdk-clean-mirror"
MODULE_MIRROR="$WORKSPACE/module-mirrors/"
REWRITE_WORKSPACE="$WORKSPACE/openjdk-rewritten-mirror/"
REPO_LOCATION="$WORKSPACE/adoptopenjdk-clone/"
REPO="$WORKSPACE/repo/"
PATCHES="$SCRIPT_DIR/patches/"

mkdir -p "$REPO"
mkdir -p "$MODULE_MIRROR"

chmod +x "$SCRIPT_DIR/merge.sh"

# These the the modules in the mercurial forest that we'll have to iterate over
MODULES=(corba langtools jaxp jaxws nashorn jdk hotspot)
MODULES_WITH_ROOT=(root corba langtools jaxp jaxws nashorn jdk hotspot)
