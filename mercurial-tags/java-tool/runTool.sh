#!/bin/bash

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

echo "*********** Running the mercurial tracker tool on the respective repo with parameters: '$*'..."
cd "${SCRIPT_DIR}" || true

set -x
java MercurialTracker "$@"
set +x
