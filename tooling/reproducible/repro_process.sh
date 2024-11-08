#!/bin/bash
# ********************************************************************************
# Copyright (c) 2024 Contributors to the Eclipse Foundation
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

# shellcheck disable=SC1091
source "$(dirname "$0")"/repro_common.sh

JDK_DIR="$1"
OS="$2"

# This script unpacks the JDK_DIR and removes windows signing Signatures in a neutral way
# ensuring identical output once Signature is removed.

expandJDK "$JDK_DIR" "$OS"

removeGeneratedClasses "$JDK_DIR" "$OS"
if [[ "$OS" =~ CYGWIN* ]] || [[ "$OS" =~ Darwin* ]]; then

  # Remove existing signature
  removeSignatures "$JDK_DIR" "$OS"

  # Add the SELF_SIGN temporary signature
  tempSign "$JDK_DIR" "$OS"

  # Remove temporary SELF_SIGN signature, which will then normalize binary length
  removeSignatures "$JDK_DIR" "$OS"
fi

patchManifests "${JDK_DIR}"

echo "$(date +%T) : Pre-processing of ${JDK_DIR} SUCCESSFUL :-)"
echo "" # blank line separator in log file
