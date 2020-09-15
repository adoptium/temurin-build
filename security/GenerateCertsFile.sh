#!/bin/bash
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

# Delete any existing file
rm -f certdata.txt*

# Grab our certificate information to use from the Mozilla site
wget https://hg.mozilla.org/mozilla-central/raw-file/tip/security/nss/lib/ckfw/builtins/certdata.txt .

# Call the script to generate our crt file
perl mk-ca-bundle.pl -n > ca-bundle.crt

# Finally use the keyutil application
java -jar keyutil-0.4.0.jar --import --new-keystore trustStore.jks --password changeit --force-new-overwrite --import-pem-file ca-bundle.crt
