#!/bin/bash
# shellcheck disable=SC2086
# ********************************************************************************
# Copyright (c) 2024 Contributors to the Eclipse Foundation
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

TEMURIN_TOOLS_BINREPL="temurin.tools.BinRepl"

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
  echo "$(date +%T) : Expanding various components to enable comparisons ${JDK_DIR} (original files will be removed):"
  mkdir "${JDK_ROOT}_CP"
  cp -R ${JDK_ROOT}/* ${JDK_ROOT}_CP

  echo "$(date +%T) :   Using 'jimage extract' to expand lib/modules image into lib/modules_extracted"
  modulesFile="${JDK_DIR}/lib/modules"
  mkdir "${JDK_DIR}/lib/modules_extracted"
  extractedDir="${JDK_DIR}/lib/modules_extracted"
  if [[ "$OS" =~ CYGWIN* ]]; then
    modulesFile=$(cygpath -w $modulesFile)
    extractedDir=$(cygpath -w $extractedDir)
  fi
  "${JDK_BIN_DIR}/jimage" extract --dir "${extractedDir}" "${modulesFile}"
  rm "${JDK_DIR}/lib/modules"
  echo "$(date +%T) :   Unzipping lib/src.zip to normalize file permissions, then removing src.zip"
  unzip -q "${JDK_DIR}/lib/src.zip" -d "${JDK_DIR}/lib/src_zip_expanded"
  rm "${JDK_DIR}/lib/src.zip"

  echo "$(date +%T) :   Using 'jmod extract' to expand all jmods to jmods/expanded_ directories"
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

  echo "$(date +%T) :   Expanding lib/jrt-fs.jar to lib/jrt-fs-exanded to remove signatures from within.."
  mkdir "${JDK_DIR}/lib/jrt-fs-expanded"
  unzip -qd "${JDK_DIR}/lib/jrt-fs-expanded" "${JDK_DIR}/lib/jrt-fs.jar"
  rm "${JDK_DIR}/lib/jrt-fs.jar"

  mkdir -p "${JDK_DIR}/jmods/expanded_java.base.jmod/lib/jrt-fs-expanded"
  unzip -qd "${JDK_DIR}/jmods/expanded_java.base.jmod/lib/jrt-fs-expanded" "${JDK_DIR}/jmods/expanded_java.base.jmod/lib/jrt-fs.jar"
  rm "${JDK_DIR}/jmods/expanded_java.base.jmod/lib/jrt-fs.jar"

  echo "$(date +%T) :   Expanding lib/ct.sym to workaround zip timestamp differences (https://bugs.openjdk.org/browse/JDK-8327466)"
  mkdir "${JDK_DIR}/lib/ct-sym-expanded"
  unzip -qd "${JDK_DIR}/lib/ct-sym-expanded" "${JDK_DIR}/lib/ct.sym"
  rm "${JDK_DIR}/lib/ct.sym"
  mkdir -p "${JDK_DIR}/jmods/expanded_jdk.compiler.jmod/lib/ct-sym-expanded"
  unzip -qd "${JDK_DIR}/jmods/expanded_jdk.compiler.jmod/lib/ct-sym-expanded" "${JDK_DIR}/jmods/expanded_jdk.compiler.jmod/lib/ct.sym"
  rm "${JDK_DIR}/jmods/expanded_jdk.compiler.jmod/lib/ct.sym"

  rm -rf "${JDK_ROOT}_CP"
}

# jdk-25+ Jlink runtimelink files contain signed binary "hash" lines in fs_* runtimelink files
#  - remove hashes of binaries on Windows & Mac due to Signatures
#  - remove hashes of lib/security/cacerts as Temurin uses Mozilla cacerts and at re-build time Mozilla certs will likely differ
#  - sort files as they are not sorted
function removeJlinkRuntimelinkHashes() {
  local JDK_DIR="$1"
  local OS="$2"

  extractedDir="${JDK_DIR}/lib/modules_extracted/jdk.jlink/jdk/tools/jlink/internal/runtimelink"
  if [[ "$OS" =~ CYGWIN* ]]; then
    extractedDir=$(cygpath -w $extractedDir)
  fi

  FILES=$(find "${extractedDir}" -type f -name "fs_*files")
  for f in $FILES
    do
      # Remove the binary hashes
      if [[ "$OS" =~ Darwin* ]]; then
        sed -i "" -E 's/^([^|]+)\|([^|]+)\|[^|]+\|([^\.]+\.dylib$)/\1|\2||\3/g' "$f"
        sed -i "" -E 's/^([^|]+)\|([^|]+)\|[^|]+\|(bin\/.*$)/\1|\2||\3/g' "$f"
        sed -i "" -E 's/^([^|]+)\|([^|]+)\|[^|]+\|(lib\/security\/cacerts$)/\1|\2||\3/g' "$f"
      elif [[ "$OS" =~ CYGWIN* ]]; then
        sed -i -E 's/^([^|]+)\|([^|]+)\|[^|]+\|([^\.]+\.dll$)/\1|\2||\3/g' "$f"
        sed -i -E 's/^([^|]+)\|([^|]+)\|[^|]+\|([^\.]+\.exe$)/\1|\2||\3/g' "$f"
        sed -i -E 's/^([^|]+)\|([^|]+)\|[^|]+\|(lib\/security\/cacerts$)/\1|\2||\3/g' "$f"
      else
        # Linux binaries are identical, only cacerts will differ
        sed -i -E 's/^([^|]+)\|([^|]+)\|[^|]+\|(lib\/security\/cacerts$)/\1|\2||\3/g' "$f"
      fi

      # Sort file content
      sort "$f" > "$f.sorted"
      rm "$f"
    done
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
  systemModules="SystemModules\$0.class SystemModules\$all.class SystemModules\$default.class SystemModules\$1.class SystemModules\$2.class SystemModules\$3.class SystemModules\$4.class SystemModules\$5.class"
  local JDK_DIR="$1"
  local OS="$2"
  local work_JDK="$3"
  for systemModule in $systemModules
    do
      FILES=$(find "${JDK_DIR}" -type f -name "$systemModule")
      for f in $FILES
        do
          ff=$f
          if [[ "$OS" =~ CYGWIN* ]]; then
            ff=$(cygpath -w $f)
          fi
          "${work_JDK}"/bin/javap -v -sysinfo -l -p -c -s -constants "$ff" > "$f.javap.tmp"
          
          # Remove "instruction number:" prefix, so we can just match code
          if [[ "$OS" =~ Darwin* ]]; then
            sed -i "" -E 's/^[[:space:]]+[0-9]+:(.*)/\1/' "$f.javap.tmp"
          else
            sed -i -E 's/^[[:space:]]+[0-9]+:(.*)/\1/' "$f.javap.tmp"
          fi

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
          rm "$f"
        done
    done

  echo "$(date +%T) : Successfully removed all SystemModules jdk.jpackage hash differences from ${JDK_DIR}"
}

# Required for Vendor "Comparable Builds"
#
# Remove the Windows EXE/DLL timestamps and internal VS CRC and debug repro hex values
# The Windows PE format contains various values determined from the binary content
# which will vary due to the different Vendor branding
#   timestamp - Used to be an actual timestamp but MSFT changed this to a checksum determined from binary content
#   checksum  - A checksum value of the binary
#   reprohex  - A hex UUID to identify the binary version, again generated from binary content
function removeWindowsNonComparableData() {
 echo "$(date +%T) : Removing EXE/DLL timestamps, CRC and debug repro hex from ${JDK_DIR}"
 # We need to do this for all executables if patching VS_VERSION_INFO
 if [[ "$PATCH_VS_VERSION_INFO" = true ]]; then
    FILES=$(find "${JDK_DIR}" -type f -path '*.exe' && find "${JDK_DIR}" -type f -path '*.dll')
 else
    FILES=$(find "${JDK_DIR}" -type f -name 'jvm.dll')
 fi
 for ff in $FILES
  do
    f=$(cygpath -w $ff)
    echo "$(date +%T) : Removing EXE/DLL non-comparable timestamp, CRC, debug repro hex from $f"

    # Determine non-comparable data using dumpbin
    dmpfile="$ff.dumpbin.tmp"
    rm -f "$dmpfile"
    if ! dumpbin "$f" /HEADERS > "$dmpfile"; then
        echo "$(date +%T) :  FAILED == > dumpbin \"$f\" /ALL > $dmpfile"
        exit 1
    fi

    # Determine non-comparable stamps and hex codes from dumpbin output
    timestamp=$(grep "time date stamp" "$dmpfile" | head -1 | tr -s ' ' | cut -d' ' -f2)
    checksum=$(grep "checksum" "$dmpfile" | head -1 | tr -s ' ' | cut -d' ' -f2)
    reprohex=$(grep "${timestamp} repro" "$dmpfile" | head -1 | tr -s ' ' | cut -d' ' -f7-38 | tr ' ' ':' | tr -d '\r')
    reprohexhalf=$(grep "${timestamp} repro" "$dmpfile" | head -1 | tr -s ' ' | cut -d' ' -f7-22 | tr ' ' ':' | tr -d '\r')
    rm -f "$dmpfile"
    # Neutralize reprohex string
    if [ -n  "$reprohex" ]; then
      if ! java "$TEMURIN_TOOLS_BINREPL" --inFile "$f" --outFile "$f" --hex "${reprohex}-AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA"; then
        echo "  FAILED ==> java $TEMURIN_TOOLS_BINREPL --inFile \"$f\" --outFile \"$f\" --hex \"${reprohex}-AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA\""
        exit 1
      fi
    fi

    # Neutralize timestamp hex string
    hexstr="00000000"
    timestamphex=${hexstr:0:-${#timestamp}}$timestamp
    timestamphexLE="${timestamphex:6:2}:${timestamphex:4:2}:${timestamphex:2:2}:${timestamphex:0:2}"
    if ! java "$TEMURIN_TOOLS_BINREPL" --inFile "$f" --outFile "$f" --hex "${timestamphexLE}-AA:AA:AA:AA"; then
        echo "  FAILED ==> java $TEMURIN_TOOLS_BINREPL --inFile \"$f\" --outFile \"$f\" --hex \"${timestamphexLE}-AA:AA:AA:AA\""
        exit 1
    fi
    if [ -n "$reprohexhalf" ]; then
      if ! java "$TEMURIN_TOOLS_BINREPL" --inFile "$f" --outFile "$f" --hex "${reprohexhalf}-AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA"; then
        echo "  FAILED ==> java $TEMURIN_TOOLS_BINREPL --inFile \"$f\" --outFile \"$f\" --hex \"${reprohexhalf}-AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA\""
        exit 1
      fi
    fi

    # Neutralize checksum string
    # Prefix checksum to 8 digits
    hexstr="00000000"
    checksumhex=${hexstr:0:-${#checksum}}$checksum
    checksumhexLE="${checksumhex:6:2}:${checksumhex:4:2}:${checksumhex:2:2}:${checksumhex:0:2}"
    if ! java "$TEMURIN_TOOLS_BINREPL" --inFile "$f" --outFile "$f" --hex "${checksumhexLE}-AA:AA:AA:AA" --firstOnly --32bitBoundaryOnly; then
        echo "  FAILED ==> java $TEMURIN_TOOLS_BINREPL --inFile \"$f\" --outFile \"$f\" --hex \"${checksumhexLE}-AA:AA:AA:AA\" --firstOnly --32bitBoundaryOnly"
        exit 1
    fi
  done
 echo "Successfully removed all EXE/DLL timestamps, CRC and debug repro hex from ${JDK_DIR}"
}

# Required for Vendor "Comparable Builds"
#
# Remove the MACOS dylib non-comparable data
#   MacOS Mach-O format stores a uuid value that consists of a "hash" of the code and
#   the some length part of the user's build folder.
# See https://github.com/adoptium/temurin-build/issues/2899#issuecomment-1153757419
function removeMacOSNonComparableData() {
  echo "Removing MacOS dylib non-comparable UUID from ${JDK_DIR}"
  MAC_JDK_ROOT="${JDK_DIR}/../../Contents"
  FILES=$(find "${MAC_JDK_ROOT}" \( -type f -and -path '*.dylib' -or -path '*/bin/*' -or -path '*/lib/jspawnhelper' -not -path '*/modules_extracted/*' -or -path '*/jpackageapplauncher*' \))
  for f in $FILES
  do
    uuid=$(otool -l "$f" | grep "uuid" | tr -s " " | tr -d "-" | cut -d" " -f3)
    if [ -z "$uuid" ]; then
      echo "  FAILED ==> otool -l \"$f\" | grep \"uuid\" | tr -s \" \" | tr -d \"-\" | cut -d\" \" -f3"
      exit 1
    else
      # Format uuid for BINREPL
      uuidhex="${uuid:0:2}:${uuid:2:2}:${uuid:4:2}:${uuid:6:2}:${uuid:8:2}:${uuid:10:2}:${uuid:12:2}:${uuid:14:2}:${uuid:16:2}:${uuid:18:2}:${uuid:20:2}:${uuid:22:2}:${uuid:24:2}:${uuid:26:2}:${uuid:28:2}:${uuid:30:2}"
      if ! java "$TEMURIN_TOOLS_BINREPL" --inFile "$f" --outFile "$f" --hex "${uuidhex}-AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA" --firstOnly; then
        echo "  FAILED ==> java \"$TEMURIN_TOOLS_BINREPL\" --inFile \"$f\" --outFile \"$f\" --hex \"${uuidhex}-AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA\" --firstOnly"
        exit 1
      fi
    fi
  done

  echo "Successfully removed all MacOS dylib non-comparable UUID from ${JDK_DIR}"
}

# Normalize the following ModuleAttributes that can be ordered differently
# depending on how the vendor has signed and re-packed the JMODs
#   - ModuleResolution:
#   - ModuleTarget:
# java.base also requires the dependent module "hash:" values to be excluded
# as they differ due to the Signatures
function processModuleInfo() {
  local JDK_DIR="$1"
  local OS="$2"
  local work_JDK="$3"
  echo "$(date +%T) : Process Module Info from ${JDK_DIR}" 
  echo "$(date +%T) : Normalizing ModuleAttributes order in module-info.class, converting to javap"
  moduleAttr="ModuleResolution ModuleTarget"
  FILES=$(find "${JDK_DIR}" -type f -name "module-info.class")
  for f in $FILES
  do
    ff=$f
    if [[ "$OS" =~ CYGWIN* ]]; then
      ff=$(cygpath -w $f)
    fi
    "${work_JDK}"/bin/javap -v -sysinfo -l -p -c -s -constants "$ff" > "$f.javap.tmp"
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
    rm "$f"
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
}

# Remove windows and mac generated CDS jdk/bin/server/classes.jsa & jdk/bin/server/classes_nocoops.jsa as will differ due to Signatures
function removeGeneratedClasses() {
  local JDK_DIR="$1"
  local OS="$2"

  if [[ "$OS" =~ CYGWIN* ]] || [[ "$OS" =~ Darwin* ]]; then
    rm -rf "$JDK_DIR/bin/server/classes.jsa"
    rm -rf "$JDK_DIR/bin/server/classes_nocoops.jsa"
    rm -rf "$JDK_DIR/bin/server/classes_coh.jsa"
    rm -rf "$JDK_DIR/bin/server/classes_nocoops_coh.jsa"
  fi
}

# Remove all Signatures
function removeSignatures() {
  local JDK_DIR="$1"
  local OS="$2"

  if [[ "$OS" =~ CYGWIN* ]]; then
    # signtool should be on PATH
    signToolPath="signtool"
    echo "$(date +%T) : Removing all signatures from exe and dll files in ${JDK_DIR}"
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
    echo "Generating temp signatures with openssl and adding them to exe/dll files in ${JDK_DIR}"
    selfCert="test"

    # semgrep needs to ignore this as it objects to the password, but that
    # is only used for generating a temporary dummy signature required for
    # the comparison and not used for validating anything
    # nosemgrep
    openssl req -x509 -quiet -newkey rsa:4096 -sha256 -days 3650 -passout pass:test -keyout $selfCert.key -out $selfCert.crt -subj "/CN=example.com" -addext "subjectAltName=DNS:example.com,DNS:*.example.com,IP:10.0.0.1"
    # nosemgrep
    openssl pkcs12 -export -passout pass:test -passin pass:test -out $selfCert.pfx -inkey $selfCert.key -in $selfCert.crt
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

  echo "$(date +%T): Cleaning Temurin NOTICE file and build-scripts specific files and metadata from ${DIR}"
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

  echo "Removing any JDK image files not shipped by Temurin(*.pdb, *.pdb, *.debuginfo, demo) in $DIR"
  find "${DIR}" -type f -name "*.pdb" -delete
  find "${DIR}" -type f -name "*.map" -delete
  find "${DIR}" -type f -name "*.debuginfo" -delete
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
