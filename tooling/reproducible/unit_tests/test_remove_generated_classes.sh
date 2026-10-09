#!/bin/bash
# ********************************************************************************
# Copyright (c) 2026 Contributors to the Eclipse Foundation
#
# See the NOTICE file(s) with this work for additional
# information regarding copyright ownership.
#
# This program and the accompanying materials are made
# available under the terms of the Apache Software License 2.0
# which is available at https://www.apache.org/licenses/LICENSE-2.0.
#
# SPDX-License-Identifier: Apache-2.0
# ********************************************************************************

set -euo pipefail

source "$(dirname "$0")/../repro_common.sh"

workDir=$(mktemp -d)
trap 'rm -rf "$workDir"' EXIT

windowsClassesDir="$workDir/windows/bin/server"
macClassesDir="$workDir/mac/Contents/Home/lib/server"
mkdir -p "$windowsClassesDir" "$macClassesDir"

touch "$windowsClassesDir/classes_nocoh.jsa" "$windowsClassesDir/classes_nocoops_nocoh.jsa"
touch "$macClassesDir/classes_nocoh.jsa" "$macClassesDir/classes_nocoops_nocoh.jsa"

removeGeneratedClasses "$workDir/windows" "CYGWIN"
removeGeneratedClasses "$workDir/mac" "Darwin"

for archive in \
  "$windowsClassesDir/classes_nocoh.jsa" \
  "$windowsClassesDir/classes_nocoops_nocoh.jsa" \
  "$macClassesDir/classes_nocoh.jsa" \
  "$macClassesDir/classes_nocoops_nocoh.jsa"; do
  if [[ -e "$archive" ]]; then
    echo "FAIL: archive was not removed: $archive"
    exit 1
  fi
done

echo "PASS: generated CDS archives are removed for Windows and macOS"
