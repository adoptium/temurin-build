#!/usr/bin/env bash

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

echo ""
javac -version
echo ""
echo ""
echo "*********** Compiling the mercurial tracker tool... "
cd "${SCRIPT_DIR}" || true
javac MercurialTracker.java
echo "*********** Finished compiling ******************** "
