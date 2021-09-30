#!/bin/bash

################################################################################
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
################################################################################

################################################################################
#
# createJRE.sh
#
# Creates a JRE-like runtime using jlink
# Usage ./createJRE.sh <directory_to_create_jre>
#
################################################################################

# Get's the top level directory of the JDK
jdkDirectory=$(dirname "$0")

if [ -z "$1" ]; then
    # Throw error if output directory is not defined
    echo "Please specify the path for the generated JRE"
    echo "e.g ./makeJRE.sh /home/user/jreruntime"
    exit 1
fi

jreDirectory="$1"
binPath="$jdkDirectory/bin"

"$binPath/jlink" --add-modules ALL-MODULE-PATH \
    --strip-debug \
    --strip-debug \
    --no-man-pages \
    --no-header-files \
    --compress=2 \
    --output "$jreDirectory"

echo "Testing generated JRE"
"$jreDirectory/bin/java" --version
echo -e "Java Version test passed ✅\n"

echo "Success: You're JRE runtime is available at $jreDirectory"