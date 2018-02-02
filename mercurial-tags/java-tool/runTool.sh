#!/usr/bin/env bash

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

ALL_ARGUMENTS="$@"
echo "*********** Running the mercurial tracker tool on the respective repo with parameters: '${ALL_ARGUMENTS}'..."
cd "${SCRIPT_DIR}" || true
java MercurialTracker "${ALL_ARGUMENTS}"
