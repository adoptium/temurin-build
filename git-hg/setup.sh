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
set -euo pipefail
rm -rf "$WORKSPACE/combined" "$WORKSPACE/hg"
mkdir "$WORKSPACE/combined"
mkdir "$WORKSPACE/hg"
cd "$WORKSPACE/combined" || exit 1
git init
git checkout -b root-commit || exit 1
git remote add github git@github.com:AdoptOpenJDK/openjdk-"${1}".git
cd - || exit 1
bash add-branch-without-modules.sh "${2:-jdk/jdk}"
