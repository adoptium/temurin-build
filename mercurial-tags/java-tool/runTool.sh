#!/usr/bin/env bash

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

echo "*********** Running the mercurial tracker tool on the respective repo with parameters: '$@'..."
cd "${SCRIPT_DIR}" || true
java MercurialTracker "$@"
