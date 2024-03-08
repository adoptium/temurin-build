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
  local OS="$2"
  local JDK_ROOT="$1"
  local JDK_BIN_DIR="${JDK_ROOT}_CP/bin"
  if [[ "$OS" =~ Darwin* ]]; then
    JDK_ROOT=$(realpath ${JDK_DIR}/../../)
    JDK_BIN_DIR="${JDK_ROOT}_CP/Contents/Home/bin"
  fi

  mkdir "${JDK_ROOT}_CP"
  cp -R ${JDK_ROOT}/* ${JDK_ROOT}_CP
  echo "Expanding the 'modules' Image to compare extracted files"
  modulesFile="${JDK_DIR}/lib/modules"
  mkdir "${JDK_DIR}/lib/modules_extracted"
  extractedDir="${JDK_DIR}/lib/modules_extracted"
  if [[ "$OS" =~ CYGWIN* ]]; then
    modulesFile=$(cygpath -w $modulesFile)
    extractedDir=$(cygpath -w $extractedDir)
  fi
  "${JDK_BIN_DIR}/jimage" extract --dir "${extractedDir}" "${modulesFile}"
  rm "${JDK_DIR}/lib/modules"
  echo "Expanding the 'src.zip' to normalize file permissions"
  unzip "${JDK_DIR}/lib/src.zip" -d "${JDK_DIR}/lib/src_zip_expanded" 1> /dev/null
  rm "${JDK_DIR}/lib/src.zip"

  echo "Expanding jmods to process binaries within"
  FILES=$(find "${JDK_DIR}" -type f -path '*.jmod')
  for f in $FILES
    do
      base=$(basename "$f")
      dir=$(dirname "$f")
      expand_dir="${dir}/expanded_${base}"
      mkdir -p "${expand_dir}"
      if [[ "$OS" =~ CYGWIN* ]]; then
        f=$(cygpath -w $f)
        expand_dir=$(cygpath -w $expand_dir)
      fi
      "${JDK_BIN_DIR}/jmod" extract --dir "${expand_dir}" "$f"
      rm "$f"
    done

  echo "Expanding the 'jrt-fs.jar' to remove signatures from within.."
  mkdir "${JDK_DIR}/lib/jrt-fs-expanded"
  unzip -d "${JDK_DIR}/lib/jrt-fs-expanded" "${JDK_DIR}/lib/jrt-fs.jar" 1> /dev/null
  rm "${JDK_DIR}/lib/jrt-fs.jar"

  mkdir -p "${JDK_DIR}/jmods/expanded_java.base.jmod/lib/jrt-fs-expanded"
  unzip -d "${JDK_DIR}/jmods/expanded_java.base.jmod/lib/jrt-fs-expanded" "${JDK_DIR}/jmods/expanded_java.base.jmod/lib/jrt-fs.jar" 1> /dev/null
  rm "${JDK_DIR}/jmods/expanded_java.base.jmod/lib/jrt-fs.jar"

  rm -rf "${JDK_ROOT}_CP"
}

# Process SystemModules classes to remove ModuleHashes$Builder differences due to Signatures
#   1. javap
#   2. search for line: // Method jdk/internal/module/ModuleHashes$Builder.hashForModule:(Ljava/lang/String;[B)Ljdk/internal/module/ModuleHashes$Builder;
#   3. followed 3 lines later by: // String <module>
#   4. then remove all lines until next: invokevirtual
#   5. remove Last modified, Classfile and SHA-256 checksum javap artefact statements
function removeSystemModulesHashBuilderParams() {
  # Key strings
  moduleHashesFunction="// Method jdk/internal/module/ModuleHashes\$Builder.hashForModule:(Ljava/lang/String;[B)Ljdk/internal/module/ModuleHashes\$Builder;"
  moduleString="// String "
  virtualFunction="invokevirtual"

  systemModules="SystemModules\$0.class SystemModules\$all.class SystemModules\$default.class"
  for systemModule in $systemModules
    do
      FILES=$(find "${JDK_DIR}" -type f -name "$systemModule")
      for f in $FILES
        do
          javap -v -sysinfo -l -p -c -s -constants "$f" > "$f.javap.tmp"
          rm "$f"

          # Remove "instruction number:" prefix, so we can just match code
          sed -i -E "s/^[[:space:]]+[0-9]+:(.*)/\1/" "$f.javap.tmp"

          cc=99
          found=false
          while IFS= read -r line
          do
            cc=$((cc+1))
            # Detect hashForModule function
            if [[ "$line" =~ .*"$moduleHashesFunction".* ]]; then
              cc=0
            fi
            # 3rd instruction line is the Module string to confirm entry
            if [[ "$cc" -eq 3 ]] && [[ "$line" =~ .*"$moduleString"[a-z\.]+.* ]]; then
              found=true
              module=$(echo "$line" | tr -s ' ' | tr -d '\r' | cut -d' ' -f6)
              export module
            fi
            # hasForModule function section finishes upon finding invokevirtual
            if [[ "$found" = true ]] && [[ "$line" =~ .*"$virtualFunction".* ]]; then
              found=false
            fi
            if [[ "$found" = false ]]; then
              echo "$line" >> "$f.javap.tmp2"
            fi
          done < "$f.javap.tmp"
          rm "$f.javap.tmp"
          grep -v "Last modified\|Classfile\|SHA-256 checksum" "$f.javap.tmp2" > "$f.javap"
          rm "$f.javap.tmp2"
        done
    done

  echo "Successfully removed all SystemModules jdk.jpackage hash differences from ${JDK_DIR}"
}

# Normalize the following ModuleAttributes that can be ordered differently
# depending on how the vendor has signed and re-packed the JMODs
#   - ModuleResolution:
#   - ModuleTarget:
# java.base also requires the dependent module "hash:" values to be excluded
# as they differ due to the Signatures
function processModuleInfo() {
  if [[ "$OS" =~ CYGWIN* ]] || [[ "$OS" =~ Darwin* ]]; then
    echo "Normalizing ModuleAttributes order in module-info.class, converting to javap"

    moduleAttr="ModuleResolution ModuleTarget"

    FILES=$(find "${JDK_DIR}" -type f -name "module-info.class")
    for f in $FILES
    do
      javap -v -sysinfo -l -p -c -s -constants "$f" > "$f.javap.tmp"
      rm "$f"

      cc=99
      foundAttr=false
      attrName=""
      # Clear any attr tmp files
      for attr in $moduleAttr
      do
        rm -f "$f.javap.$attr"
      done

      while IFS= read -r line
      do
        cc=$((cc+1))

        # Module attr have only 1 line definition
        if [[ "$foundAttr" = true ]] && [[ "$cc" -gt 1 ]]; then
          foundAttr=false
          attrName=""
        fi

        # If not processing an attr then check for attr
        if [[ "$foundAttr" = false ]]; then
          for attr in $moduleAttr
          do
            if [[ "$line" =~ .*"$attr:".* ]]; then
              cc=0
              foundAttr=true
              attrName="$attr"
            fi
          done
        fi

        # Echo attr to attr tmp file, otherwise to tmp2
        if [[ "$foundAttr" = true ]]; then
          echo "$line" >> "$f.javap.$attrName"
        else
          echo "$line" >> "$f.javap.tmp2"
        fi
      done < "$f.javap.tmp"
      rm "$f.javap.tmp"

      # Remove javap Classfile and timestamp and SHA-256 hash
      if [[ "$f" =~ .*"java.base".* ]]; then
        grep -v "Last modified\|Classfile\|SHA-256 checksum\|hash:" "$f.javap.tmp2" > "$f.javap"
      else
        grep -v "Last modified\|Classfile\|SHA-256 checksum" "$f.javap.tmp2" > "$f.javap"
      fi
      rm "$f.javap.tmp2"

      # Append any ModuleAttr tmp files
      for attr in $moduleAttr
      do
        if [[ -f "$f.javap.$attr" ]]; then
          cat "$f.javap.$attr" >> "$f.javap"
        fi
        rm -f "$f.javap.$attr"
      done
    done
  fi
}

# Remove all Signatures
function removeSignatures() {
  local JDK_DIR="$1"
  local OS="$2"

  if [[ "$OS" =~ CYGWIN* ]]; then
    # signtool should be on PATH
    signToolPath="signtool"
    echo "Removing all Signatures from ${JDK_DIR}"
    FILES=$(find "${JDK_DIR}" -type f -name '*.exe' -o -name '*.dll')
    for f in $FILES
     do
      f=$(cygpath -w $f)
      rc=0
      "$signToolPath" remove /s "$f" 1> /dev/null 2>&1 || rc=$?

      # if [ $rc -ne 0 ]; then
      #   echo "Removing signature from $f failed"
      # fi
     done
  elif [[ "$OS" =~ Darwin* ]]; then
    MAC_JDK_ROOT="${JDK_DIR}/../.."
    echo "Removing all Signatures from ${MAC_JDK_ROOT}"

    if [ ! -d "${MAC_JDK_ROOT}/Contents" ]; then
        echo "Error: ${MAC_JDK_ROOT} does not contain the MacOS JDK Contents directory"
        exit 1
    fi

    # Remove any extended app attr
    xattr -cr "${MAC_JDK_ROOT}"

    FILES=$(find "${MAC_JDK_ROOT}" \( -type f -and -path '*.dylib' -or -path '*/bin/*' -or -path '*/lib/jspawnhelper' -not -path '*/modules_extracted/*' -or -path '*/jpackageapplauncher*' \))
    for f in $FILES
    do
        echo "Removing signature from $f"
        codesign --remove-signature "$f" 1> /dev/null
    done
  fi
}

# Sign with temporary Signature, which when removed results in determinisitic binary length
function tempSign() {
  local JDK_DIR="$1"
  local OS="$2"

  if [[ "$OS" =~ CYGWIN* ]]; then
    # signtool should be on PATH
    signToolPath="signtool"
    echo "Adding temp Signatures for ${JDK_DIR}"
    selfCert="test"
    openssl req -x509 -newkey rsa:4096 -sha256 -days 3650 -nodes -keyout $selfCert.key -out $selfCert.crt -subj "/CN=example.com" -addext "subjectAltName=DNS:example.com,DNS:*.example.com,IP:10.0.0.1"
    openssl pkcs12 -export -passout pass:test -out $selfCert.pfx -inkey $selfCert.key -in $selfCert.crt
    FILES=$(find "${JDK_DIR}" -type f -name '*.exe' -o -name '*.dll')
    for f in $FILES
     do
      rc=0
      f=$(cygpath -w $f)
      "$signToolPath" sign /f $selfCert.pfx /p test /fd SHA256 $f 1> /dev/null || rc=$?
      if [ $rc -ne 0 ]; then
        echo "Adding Temp Signature for $f failed"
      fi
     done
  elif [[ "$OS" =~ Darwin* ]]; then
    MAC_JDK_ROOT="${JDK_DIR}/../../Contents"
    echo "Adding temp Signatures for ${MAC_JDK_ROOT}"
    FILES=$(find "${MAC_JDK_ROOT}" \( -type f -and -path '*.dylib' -or -path '*/bin/*' -or -path '*/lib/jspawnhelper' -not -path '*/modules_extracted/*' -or -path '*/jpackageapplauncher*' \))
    for f in $FILES
    do
        echo "Signing $f with ad-hoc signing"
        # Sign both with same local Certificate, this adjusts __LINKEDIT vmsize identically
        codesign -s "-" "$f"
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
