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

assertEquals() {
  local expected="$1"
  local actual="$2"
  local message="$3"

  if [ "$expected" != "$actual" ]; then
    echo "FAIL: $message"
    echo "  expected: $expected"
    echo "  actual  : $actual"
    exit 1
  fi
}

extractSbomPandocValue() {
  local sbom="$1"
  jq -r '.formulation[]? | select(."bom-ref" == "Build Dependencies") | .components[]? | select(.name == "Build tool non-package dependencies") | .properties[]? | select(.name | startswith("pandoc")) | .value' "$sbom" | head -n 1
}

extractSbomPandocVersion() {
  local value="$1"
  echo "$value" | sed -E 's/^pandoc[[:space:]]+([^[:space:]]+).*$/\1/'
}

workDir=$(mktemp -d)
trap 'rm -rf "$workDir"' EXIT

cat > "$workDir/example_sbom.json" <<'JSON'
{
  "formulation": [
    {
      "bom-ref": "Build Dependencies",
      "components": [
        {
          "name": "Build tool non-package dependencies",
          "properties": [
            {
              "name": "pandoc 3.8.2",
              "value": "pandoc 3.8.2"
            }
          ]
        }
      ]
    }
  ]
}
JSON

sbomPandocValue=$(extractSbomPandocValue "$workDir/example_sbom.json")
assertEquals "pandoc 3.8.2" "$sbomPandocValue" "SBOM pandoc property extraction"

sbomPandocVersion=$(extractSbomPandocVersion "$sbomPandocValue")
assertEquals "3.8.2" "$sbomPandocVersion" "SBOM pandoc version parsing"

cat > "$workDir/malformed_sbom.json" <<'JSON'
{
  "formulation": [
    {
      "bom-ref": "Build Dependencies",
      "components": [
        {
          "name": "Build tool non-package dependencies",
          "properties": [
            {
              "name": "pandoc",
              "value": "3.8.2"
            }
          ]
        }
      ]
    }
  ]
}
JSON

malformedValue=$(extractSbomPandocValue "$workDir/malformed_sbom.json")
malformedVersion=$(extractSbomPandocVersion "$malformedValue")
assertEquals "$malformedValue" "$malformedVersion" "Malformed SBOM pandoc value remains unparsed"

cat > "$workDir/missing_pandoc_sbom.json" <<'JSON'
{
  "formulation": [
    {
      "bom-ref": "Build Dependencies",
      "components": [
        {
          "name": "Build tool non-package dependencies",
          "properties": []
        }
      ]
    }
  ]
}
JSON

missingPandocValue=$(extractSbomPandocValue "$workDir/missing_pandoc_sbom.json")
assertEquals "" "$missingPandocValue" "Missing pandoc SBOM property returns empty value"

echo "PASS: standalone pandoc SBOM unit test"
