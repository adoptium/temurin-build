#!/bin/sh
# ********************************************************************************
# Copyright (c) 2023 Contributors to the Eclipse Foundation
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

# Check if JDK-17 is installed and set as the default JDK
if ! java -version 2>&1 | grep -q '"17.'; then
  echo "Error: JDK-17 is not installed or not set as the default JDK. Please install JDK-17 and set it as the default JDK before running this script."
  exit 1
fi

# Set the SCRIPT_DIR variable
SCRIPT_DIR=$(cd "$(dirname "$0")" || exit; pwd)

# Add executable permission to signSBOM.sh and sbom.sh scripts
chmod +x /github/workspace/build-farm/signSBOM.sh
chmod +x /github/workspace/sbin/common/sbom.sh

# Call signSBOMFile function in sbom.sh
"${SCRIPT_DIR}"/../sbin/common/sbom.sh signSBOMFile

# Call verifySBOMSignature function in sbom.sh
"${SCRIPT_DIR}"/../sbin/common/sbom.sh verifySBOMSignature

# Run the ant build command to build the org.webpki.json openkeystore code and call the signSBOMFile() function in sbom.sh
if ! ant -buildfile "${SCRIPT_DIR}"/../cyclonedx-lib/build.xml buildSignSBOM; then
  echo "Error: The ant build command to build the org.webpki.json openkeystore code failed."
  exit 1
fi

echo "Success: The org.webpki.json openkeystore code was built and signed successfully using JDK-17."
