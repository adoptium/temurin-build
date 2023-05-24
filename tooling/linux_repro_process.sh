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

set -e

JDK_DIR="$1"

if [ ! -d "${JDK_DIR}" ]; then
  echo "$JDK_DIR does not exist"
  exit 1
fi

echo "Expanding the 'modules' Image to compare within.."
jimage extract --dir "${JDK_DIR}/lib/modules_extracted" "${JDK_DIR}/lib/modules"
rm "${JDK_DIR}/lib/modules"

echo "Expanding the 'src.zip' to normalize file permissions"
unzip "${JDK_DIR}/lib/src.zip" -d "${JDK_DIR}/lib/src_zip_expanded"
rm "${JDK_DIR}/lib/src.zip"

echo "Expanding jmods to compare within"
FILES=$(find "${JDK_DIR}" -type f -path '*.jmod')
for f in $FILES
  do
    echo "Unzipping $f"
    base=$(basename "$f")
    dir=$(dirname "$f")
    expand_dir="${dir}/expanded_${base}"
    mkdir -p "${expand_dir}"
    jmod extract --dir "${expand_dir}" "$f"
    rm "$f"
  done

echo "Expanding the 'jrt-fs.jar' to compare within.."
mkdir "${JDK_DIR}/lib/jrt-fs-expanded"
unzip -d "${JDK_DIR}/lib/jrt-fs-expanded" "${JDK_DIR}/lib/jrt-fs.jar"
rm "${JDK_DIR}/lib/jrt-fs.jar"

mkdir "${JDK_DIR}/jmods/expanded_java.base.jmod/lib/jrt-fs-expanded"
unzip -d "${JDK_DIR}/jmods/expanded_java.base.jmod/lib/jrt-fs-expanded" "${JDK_DIR}/jmods/expanded_java.base.jmod/lib/jrt-fs.jar"
rm "${JDK_DIR}/jmods/expanded_java.base.jmod/lib/jrt-fs.jar"

echo "Removing jrt-fs.jar MANIFEST.MF BootJDK vendor string lines"
sed -i '/^Implementation-Vendor:.*$/d' "${JDK_DIR}/lib/jrt-fs-expanded/META-INF/MANIFEST.MF"
sed -i '/^Created-By:.*$/d' "${JDK_DIR}/lib/jrt-fs-expanded/META-INF/MANIFEST.MF"
sed -i '/^Implementation-Vendor:.*$/d' "${JDK_DIR}/jmods/expanded_java.base.jmod/lib/jrt-fs-expanded/META-INF/MANIFEST.MF"
sed -i '/^Created-By:.*$/d' "${JDK_DIR}/jmods/expanded_java.base.jmod/lib/jrt-fs-expanded/META-INF/MANIFEST.MF"

echo "***********"
echo "SUCCESS :-)"
echo "***********"

