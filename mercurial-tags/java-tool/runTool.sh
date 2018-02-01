#!/usr/bin/env bash

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

echo "*********** Running the mercurial tracker tool..."
cd "${SCRIPT_DIR}" || true
java MercurialTracker "$@"
