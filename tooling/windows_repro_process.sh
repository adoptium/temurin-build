#!/bin/bash
# shellcheck disable=SC2086
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
SELF_CERT_FILE="$2"
SELF_CERT_PASS="$3"

removeSignatures() {
  echo "Removing Signatures from ${JDK_DIR}"
  FILES=$(find "${JDK_DIR}" -type f -path '*.exe' && find "${JDK_DIR}" -type f -path '*.dll')
  for f in $FILES
    do
      echo "Removing signature from $f"
      if signtool remove /s $f ; then
        echo "  ==> Successfully removed signature from $f"
      else
        echo "  ==> $f contains no signature"
      fi
    done
  echo "Successfully removed all Signatures from ${JDK_DIR}"
}

# This script unpacks the JDK_DIR and removes windows signing Signatures in a neutral way
# ensuring identical output once Signature is removed.

if [[ ! -d "${JDK_DIR}" ]] || [[ ! -d "${JDK_DIR}/bin"  ]]; then
  echo "$JDK_DIR does not exist or does not point at a JDK"
  exit 1
fi

echo "Expanding the 'modules' Image to remove signatures from within.."
jimage extract --dir "${JDK_DIR}/lib/modules_extracted" "${JDK_DIR}/lib/modules"
rm ${JDK_DIR}/lib/modules

echo "Expanding the 'src.zip' to normalize file permissions"
unzip ${JDK_DIR}/lib/src.zip -d ${JDK_DIR}/lib/src_zip_expanded
rm ${JDK_DIR}/lib/src.zip

echo "Expanding jmods to process exe/dll within"
FILES=$(find "${JDK_DIR}" -type f -path '*.jmod')
for f in $FILES
  do
    echo "Unzipping $f"
    base=$(basename $f)
    dir=$(dirname $f)
    expand_dir="${dir}/expanded_${base}"
    mkdir -p "${expand_dir}"
    jmod extract --dir "${expand_dir}" "$f"
    rm "$f"
  done

echo "Expanding the 'jrt-fs.jar' to remove signatures from within.."
mkdir ${JDK_DIR}/lib/jrt-fs-expanded
unzip -d ${JDK_DIR}/lib/jrt-fs-expanded ${JDK_DIR}/lib/jrt-fs.jar
rm ${JDK_DIR}/lib/jrt-fs.jar

mkdir ${JDK_DIR}/jmods/expanded_java.base.jmod/lib/jrt-fs-expanded
unzip -d ${JDK_DIR}/jmods/expanded_java.base.jmod/lib/jrt-fs-expanded ${JDK_DIR}/jmods/expanded_java.base.jmod/lib/jrt-fs.jar
rm ${JDK_DIR}/jmods/expanded_java.base.jmod/lib/jrt-fs.jar

# Remove existing signature
removeSignatures

# Add the SELF_SIGN temporary signature
echo "Adding SELF_SIGN Signatures for ${JDK_DIR}"
FILES=$(find "${JDK_DIR}" -type f -path '*.exe' && find "${JDK_DIR}" -type f -path '*.dll')
for f in $FILES
  do
    echo "Signing $f"
    if signtool sign /f $SELF_CERT_FILE /p $SELF_CERT_PASS $f ; then
        echo "  ==> Successfully signed $f"
    else
        echo "  ==> $f failed to be signed!!"
        exit 1
    fi
  done

echo "Successfully SELF_CERT signed all Signatures in ${JDK_DIR}"

# Remove temporary SELF_SIGN signature, which will then normalize binary length
removeSignatures

echo "Removing jrt-fs.jar MANIFEST.MF BootJDK vendor string lines"
sed -i '/^Implementation-Vendor:.*$/d' "${JDK_DIR}/lib/jrt-fs-expanded/META-INF/MANIFEST.MF"
sed -i '/^Created-By:.*$/d' "${JDK_DIR}/lib/jrt-fs-expanded/META-INF/MANIFEST.MF"
sed -i '/^Implementation-Vendor:.*$/d' "${JDK_DIR}/jmods/expanded_java.base.jmod/lib/jrt-fs-expanded/META-INF/MANIFEST.MF"
sed -i '/^Created-By:.*$/d' "${JDK_DIR}/jmods/expanded_java.base.jmod/lib/jrt-fs-expanded/META-INF/MANIFEST.MF"

echo "Removing SOURCE= from ${JDK_DIR}/release file, as Temurin builds from mirror _adopt tag"
sed -i '/^SOURCE=.*$/d' "${JDK_DIR}/release"

echo "Removing cacerts file, as Temurin builds with different Mozilla cacerts"
find "${JDK_DIR}" -type f -name "cacerts" -delete

echo "***********"
echo "SUCCESS :-)"
echo "***********"

