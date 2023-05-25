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
###############################################################################

# Expand JDK jmods & zips to process binaries within
function expandJDK() {
  local JDK_DIR="$1"

  echo "Expanding the 'modules' Image to remove signatures from within.."
  jimage extract --dir "${JDK_DIR}/lib/modules_extracted" "${JDK_DIR}/lib/modules"
  rm "${JDK_DIR}/lib/modules"

  echo "Expanding the 'src.zip' to normalize file permissions"
  unzip "${JDK_DIR}/lib/src.zip" -d "${JDK_DIR}/lib/src_zip_expanded"
  rm "${JDK_DIR}/lib/src.zip"

  echo "Expanding jmods to process binaries within"
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

  echo "Expanding the 'jrt-fs.jar' to remove signatures from within.."
  mkdir "${JDK_DIR}/lib/jrt-fs-expanded"
  unzip -d "${JDK_DIR}/lib/jrt-fs-expanded" "${JDK_DIR}/lib/jrt-fs.jar"
  rm "${JDK_DIR}/lib/jrt-fs.jar"

  mkdir "${JDK_DIR}/jmods/expanded_java.base.jmod/lib/jrt-fs-expanded"
  unzip -d "${JDK_DIR}/jmods/expanded_java.base.jmod/lib/jrt-fs-expanded" "${JDK_DIR}/jmods/expanded_java.base.jmod/lib/jrt-fs.jar"
  rm "${JDK_DIR}/jmods/expanded_java.base.jmod/lib/jrt-fs.jar"
}

# Remove all Signatures
function removeSignatures() {
  local JDK_DIR="$1"
  local OS="$2"

  if [[ "$OS" =~ CYGWIN* ]]; then
    echo "Removing all Signatures from ${JDK_DIR}"
    FILES=$(find "${JDK_DIR}" -type f -path '*.exe' && find "${JDK_DIR}" -type f -path '*.dll')
    for f in $FILES
     do
      echo "Removing signature from $f"
      if signtool remove /s "$f"; then
          echo "  ==> Successfully removed signature from $f"
      else
          echo "  ==> $f contains no signature"
      fi
     done
  elif [[ "$OS" =~ Darwin* ]]; then
    MAC_JDK_ROOT="${JDK_DIR}/../.."
    echo "Removing all Signatures from ${MAC_JDK_ROOT}"

    if [ ! -d "${MAC_JDK_ROOT}/Contents" ]; then
        echo "Error: ${MAC_JDK_ROOT} does not contain the MacOS JDK Contents directory"
        exit 1
    fi

    # Remove any extended app attr
    xattr -c "${MAC_JDK_ROOT}"

    FILES=$(find "${MAC_JDK_ROOT}" \( -type f -and -path '*.dylib' -or -path '*/bin/*' -or -path '*/lib/jspawnhelper' -not -path '*/modules_extracted/*' -or -path '*/jpackageapplauncher*' \))
    for f in $FILES
    do
        echo "Removing signature from $f"
        codesign --remove-signature "$f"
    done
  fi
}

# Sign with temporary Signature, which when removed results in determinisitic binary length
function tempSign() {
  local JDK_DIR="$1"
  local OS="$2"
  local SELF_CERT="$3"
  local SELF_CERT_PASS="$4"

  if [[ "$OS" =~ CYGWIN* ]]; then
    echo "Adding temp Signatures for ${JDK_DIR}"
    FILES=$(find "${JDK_DIR}" -type f -path '*.exe' && find "${JDK_DIR}" -type f -path '*.dll')
    for f in $FILES
     do
      echo "Signing $f"
      if signtool sign /f "$SELF_CERT" /p "$SELF_CERT_PASS" "$f" ; then
          echo "  ==> Successfully signed $f"
      else
          echo "  ==> $f failed to be signed!!"
          exit 1
      fi
     done
  elif [[ "$OS" =~ Darwin* ]]; then
    MAC_JDK_ROOT="${JDK_DIR}/../../Contents"
    echo "Adding temp Signatures for ${MAC_JDK_ROOT}"

    FILES=$(find "${MAC_JDK_ROOT}" \( -type f -and -path '*.dylib' -or -path '*/bin/*' -or -path '*/lib/jspawnhelper' -not -path '*/modules_extracted/*' -or -path '*/jpackageapplauncher*' \))
    for f in $FILES
    do
        echo "Signing $f with a local certificate"
        # Sign both with same local Certificate, this adjusts __LINKEDIT vmsize identically
        codesign -s "$SELF_CERT" --options runtime -f --timestamp "$f"
    done
  fi
}

# If performing a reproducible compare to a non temurin build-scripts built JDK
# then remove certain Temurin build-script added metadata or different files
function cleanTemurinFiles() {
  local DIR="$1"

  echo "Cleaning Temurin build-scripts specific files and metadata from ${DIR}"

  echo "Removing Temurin NOTICE file from $DIR"
  rm "${DIR}"/NOTICE

  if [[ $(uname) =~ Darwin* ]]; then
    echo "Removing Temurin specific lines from release file in $DIR"
    sed -i "" '/^BUILD_SOURCE=.*$/d' "${DIR}/release"
    sed -i "" '/^BUILD_SOURCE_REPO=.*$/d' "${DIR}/release"
    sed -i "" '/^SOURCE_REPO=.*$/d' "${DIR}/release"
    sed -i "" '/^FULL_VERSION=.*$/d' "${DIR}/release"
    sed -i "" '/^SEMANTIC_VERSION=.*$/d' "${DIR}/release"
    sed -i "" '/^BUILD_INFO=.*$/d' "${DIR}/release"
    sed -i "" '/^JVM_VARIANT=.*$/d' "${DIR}/release"
    sed -i "" '/^JVM_VERSION=.*$/d' "${DIR}/release"
    sed -i "" '/^IMAGE_TYPE=.*$/d' "${DIR}/release"
  
    echo "Removing SOURCE= from ${DIR}/release file, as Temurin builds from Adoptium mirror repo _adopt tag"
    sed -i "" '/^SOURCE=.*$/d' "${DIR}/release"
  else
    echo "Removing Temurin specific lines from release file in $DIR"
    sed -i '/^BUILD_SOURCE=.*$/d' "${DIR}/release"
    sed -i '/^BUILD_SOURCE_REPO=.*$/d' "${DIR}/release"
    sed -i '/^SOURCE_REPO=.*$/d' "${DIR}/release"
    sed -i '/^FULL_VERSION=.*$/d' "${DIR}/release"
    sed -i '/^SEMANTIC_VERSION=.*$/d' "${DIR}/release"
    sed -i '/^BUILD_INFO=.*$/d' "${DIR}/release"
    sed -i '/^JVM_VARIANT=.*$/d' "${DIR}/release"
    sed -i '/^JVM_VERSION=.*$/d' "${DIR}/release"
    sed -i '/^IMAGE_TYPE=.*$/d' "${DIR}/release"

    echo "Removing SOURCE= from ${DIR}/release file, as Temurin builds from Adoptium mirror repo _adopt tag"
    sed -i '/^SOURCE=.*$/d' "${DIR}/release"
  fi

  echo "Removing cacerts file, as Temurin builds with different Mozilla cacerts"
  find "${DIR}" -type f -name "cacerts" -delete

  echo "Removing any JDK image files not shipped by Temurin(*.pdb, *.pdb, demo) in $DIR"
  find "${DIR}" -type f -name "*.pdb" -delete
  find "${DIR}" -type f -name "*.map" -delete
  rm -rf "${DIR}/demo"
}

# Temurin release file metadata BUILD_INFO/SOURCE can/will be different
function cleanTemurinBuildInfo() {
  local DIR="$1"
  
  echo "Cleaning any Temurin build-scripts release file BUILD_INFO from ${DIR}"

  if [[ $(uname) =~ Darwin* ]]; then
    sed -i "" '/^BUILD_SOURCE=.*$/d' "${DIR}/release"
    sed -i "" '/^BUILD_SOURCE_REPO=.*$/d' "${DIR}/release"
    sed -i "" '/^BUILD_INFO=.*$/d' "${DIR}/release"
  else
    sed -i '/^BUILD_SOURCE=.*$/d' "${DIR}/release"
    sed -i '/^BUILD_SOURCE_REPO=.*$/d' "${DIR}/release" 
    sed -i '/^BUILD_INFO=.*$/d' "${DIR}/release"
  fi
}

# Patch the Vendor strings from the BootJDK in jrt-fs/jar MANIFEST
function patchManifests() {
  local JDK_DIR="$1"

  if [[ $(uname) =~ Darwin* ]]; then
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
}

