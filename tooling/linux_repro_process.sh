#!/bin/bash
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

source repro_common.sh

set -e

JDK_DIR="$1"

if [ ! -d "${JDK_DIR}" ]; then
  echo "$JDK_DIR does not exist"
  exit 1
fi

expandJDK "$JDK_DIR"

if [[ `uname` =~ Darwin* ]]; then
  echo "Removing jrt-fs.jar MANIFEST.MF BootJDK vendor string lines"
  sed -i "" '/^Implementation-Vendor:.*$/d' "${JDK_DIR}/lib/jrt-fs-expanded/META-INF/MANIFEST.MF"
  sed -i "" '/^Created-By:.*$/d' "${JDK_DIR}/lib/jrt-fs-expanded/META-INF/MANIFEST.MF"
  sed -i "" '/^Implementation-Vendor:.*$/d' "${JDK_DIR}/jmods/expanded_java.base.jmod/lib/jrt-fs-expanded/META-INF/MANIFEST.MF"
  sed -i "" '/^Created-By:.*$/d' "${JDK_DIR}/jmods/expanded_java.base.jmod/lib/jrt-fs-expanded/META-INF/MANIFEST.MF"
else
  echo "Removing jrt-fs.jar MANIFEST.MF BootJDK vendor string lines"
  sed -i '/^Implementation-Vendor:.*$/d' "${JDK_DIR}/lib/jrt-fs-expanded/META-INF/MANIFEST.MF"
  sed -i '/^Created-By:.*$/d' "${JDK_DIR}/lib/jrt-fs-expanded/META-INF/MANIFEST.MF"
  sed -i '/^Implementation-Vendor:.*$/d' "${JDK_DIR}/jmods/expanded_java.base.jmod/lib/jrt-fs-expanded/META-INF/MANIFEST.MF"
  sed -i '/^Created-By:.*$/d' "${JDK_DIR}/jmods/expanded_java.base.jmod/lib/jrt-fs-expanded/META-INF/MANIFEST.MF"
fi

echo "***********"
echo "SUCCESS :-)"
echo "***********"

