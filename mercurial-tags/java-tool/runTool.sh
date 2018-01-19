#!/usr/bin/env bash

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

echo ""
java -version
echo ""
echo ""
echo "*********** Running the mercurial tracker tool..."
cd ${SCRIPT_DIR}
java MercurialTracker $@

echo ""
echo "*********** Thank you @judovana (Jiri Vanek) & Redhat for your contribution ************"
