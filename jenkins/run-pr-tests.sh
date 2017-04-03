#!/usr/bin/env bash

WDIR="$(cd "`dirname $0`"/..; pwd)"
cd "$WDIR"

exec python -u ./jenkins/run-pr-tests.py "$@"
