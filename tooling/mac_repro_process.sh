#!/bin/bash
# shellcheck disable=SC2086,SC1091
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
###############################################################################

source repro_common.sh

set -e

JDK_DIR="$1"
SELF_CERT="$2"
SELF_CERT_PASS="$3"

# This script unpacks the JDK_DIR and removes windows signing Signatures in a neutral way
# ensuring identical output once Signature is removed.

if [[ ! -d "${JDK_DIR}" ]] || [[ ! -d "${JDK_DIR}/bin"  ]]; then
  echo "$JDK_DIR does not exist or does not point at a JDK"
  exit 1
fi

OS=$("uname")

expandJDK "$JDK_DIR"

# Remove existing signature
removeSignatures "$JDK_DIR" "$OS"

# Add the SELF_SIGN temporary signature
tempSign "$JDK_DIR" "$OS" "$SELF_CERT" "$SELF_CERT_PASS"

# Remove temporary SELF_SIGN signature, which will then normalize binary length
removeSignatures "$JDK_DIR" "$OS"

patchManifests "${JDK_DIR}"

echo "***********"
echo "SUCCESS :-)"
echo "***********"

