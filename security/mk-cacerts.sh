#!/usr/bin/env bash
#
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
#
set -euo pipefail

PROGRAM_NAME="${0##*/}"
KEYTOOL="keytool" # By default, use keytool from PATH.
HELP=false
NO_KEYSTORE=false

while [[ "$#" -gt 0 ]]; do
    case $1 in
        -k|--keytool) KEYTOOL="$2"; shift ;;
        -h|--help) HELP=true ;;
        -n|--nokeystore) NO_KEYSTORE=true ;;
        *) echo "Unknown parameter passed: $1"; exit 1 ;;
    esac
    shift
done

if [ "$HELP" = true ] ; then
    echo "Usage: $PROGRAM_NAME [options]"
    echo ""
    echo "Generates a new cacerts keystore from certdata.txt in the working directory."
    echo ""
    echo "Options:"
    echo "-h, --help            Show this help message and exit."
    echo "-k, --keytool <path>  keytool to use to create the cacerts keystore."
    echo "-n, --nokeystore      only generate the certs/* files, do not create the cacerts keystore."
    exit 0
fi

# Remove files from last run if present
rm -f ca-bundle.crt cacerts
rm -rf certs && mkdir certs

# Abort if certdata.txt is not present because we do not want mk-ca-bundle.pl
# to download it. Otherwise we might have inconsistent certificate stores
# between builds.
if ! [ -f "certdata.txt" ] ; then
    echo "Local certdata.txt missing, aborting." >&2
    exit 1
fi

# Convert Mozilla's list of certificates into a PEM file. The -n switch makes
# it use the local certdata.txt in this folder.
./mk-ca-bundle.pl -v -n ca-bundle.crt

# Split them PEM file into individual files because keytool cannot do it on its
# own.
awk '
  split_after == 1 {close("certs/cert" n ".crt");n++;split_after=0}
  /-----END CERTIFICATE-----/ {split_after=1}
  {print > ("certs/cert" n ".crt")}' < ca-bundle.crt

# If generating the keystore, import each CA certificate individually into the keystore.
# As alias, we use the subject which looks like
# 
#     subject= /OU=GlobalSign Root CA - R2/O=GlobalSign/CN=GlobalSign
#
# We chop off `subject= /` and replace the forward slashes with commas.
#     `OU=GlobalSign Root CA - R2,O=GlobalSign,CN=GlobalSign`.
#
# If we are just generating the crt files for the openjdk build then also
# change spaces and [:()] to underscores. So it becomes:
#     `OU=GlobalSign_Root_CA_-_R2,O=GlobalSign,CN=GlobalSign`.
# Also rename each CA certificate file to the alias
# for import into the keystore by the openjdk make file.
#
# The full subject needs to be used to prevent alias collisions.

IMPORTED=('null')

for FILE in certs/*.crt; do
    SUBJECT=$(openssl x509 -subject -noout -in "$FILE")
    TRIMMED_SUBJECT="${SUBJECT#*subject= /}"
    if [ "$NO_KEYSTORE" = false ] ; then
        ALIAS="${TRIMMED_SUBJECT//\//,}"
    else
        # Remove/translate characters not valid in a filename
        ALIAS_NO_INVALID="${TRIMMED_SUBJECT//[ :()]/_}"
        ALIAS_NO_SPECIAL=$(echo "${ALIAS_NO_INVALID}" | tr -cd 'a-zA-Z,_')
        ALIAS="${ALIAS_NO_SPECIAL,,}"
    fi

    if [ "$NO_KEYSTORE" = false ] ; then
         if printf '%s\n' "${IMPORTED[@]}" | grep "${ALIAS}"; then
            echo "Skipping certificate with alias: $ALIAS as it already exists"
        else
            echo "Processing certificate with alias: $ALIAS"
            "$KEYTOOL" -noprompt \
            -import \
            -storetype JKS \
            -alias "$ALIAS" \
            -file "$FILE" \
            -keystore "cacerts" \
            -storepass "changeit"

            IMPORTED+=("${ALIAS}")
        fi
    else
         echo "Renaming $FILE to certs/$ALIAS"
         mv "$FILE" "certs/$ALIAS"
    fi
done
