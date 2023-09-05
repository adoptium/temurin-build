#!/bin/bash
# shellcheck disable=SC1091
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
##############################################################################

source repro_common.sh

set -eu

#
# Script to remove "vendor" specific strings and Signatures, as well as neutralizing
# differing build timestamps, and other non-identical Vendor binary content.
#
# Upon successful completion of processing a jdk folder for a jdk-21+ openjdk build
# of the identical source, built reproducibly (same --with-source-date), a diff
# of two processed jdk folders should be identical.
#

TEMURIN_TOOLS_BINREPL="temurin.tools.BinRepl"

JDK_DIR="$1"
VERSION_REPL="$2"
VENDOR_NAME="$3"
VENDOR_URL="$4"
VENDOR_BUG_URL="$5"
VENDOR_VM_BUG_URL="$6"

# Remove excluded files known to differ
function removeExcludedFiles() {
  if [[ "$OS" =~ CYGWIN* ]] || [[ "$OS" =~ Darwin* ]]; then
    excluded="NOTICE cacerts classes.jsa classes_nocoops.jsa SystemModules\$0.class SystemModules\$all.class SystemModules\$default.class"
  else
    excluded="NOTICE cacerts classes.jsa classes_nocoops.jsa"
  fi
  echo "Removing excluded files known to differ: ${excluded}"
  for exclude in $excluded
    do
      FILES=$(find "${JDK_DIR}" -type f -name "$exclude")
      for f in $FILES
        do
          echo "Removing $f"
          rm "$f"
        done
    done

  if [[ "$OS" =~ CYGWIN* ]] || [[ "$OS" =~ Darwin* ]]; then
    echo "Removing java.base module-info.class, known to differ by jdk.jpackage module hash"
    rm "${JDK_DIR}/jmods/expanded_java.base.jmod/classes/module-info.class"
    rm "${JDK_DIR}/lib/modules_extracted/java.base/module-info.class"
  fi
  echo "Successfully removed all excluded files from ${JDK_DIR}"
}

# Remove the Windows EXE/DLL timestamps and internal VS CRC and debug repro hex values
function removeWindowsNonComparableData() {
 echo "Removing EXE/DLL timestamps, CRC and debug repro hex from ${JDK_DIR}"
 FILES=$(find "${JDK_DIR}" -type f -path '*.exe' && find "${JDK_DIR}" -type f -path '*.dll')
 for f in $FILES
  do
    echo "Removing EXE/DLL non-comparable timestamp, CRC, debug repro hex from $f"
    rm -f dumpbin.tmp
    if ! dumpbin "$f" /ALL > dumpbin.tmp; then
        echo "  FAILED == > dumpbin \"$f\" /ALL > dumpbin.tmp"
        exit 1
    fi
    timestamp=$(grep "time date stamp" dumpbin.tmp | head -1 | tr -s ' ' | cut -d' ' -f2)
    checksum=$(grep "checksum" dumpbin.tmp | head -1 | tr -s ' ' | cut -d' ' -f2)
    reprohex=$(grep "${timestamp} repro" dumpbin.tmp | head -1 | tr -s ' ' | cut -d' ' -f7-38 | tr ' ' ':' | tr -d '\r')
    reprohexhalf=$(grep "${timestamp} repro" dumpbin.tmp | head -1 | tr -s ' ' | cut -d' ' -f7-22 | tr ' ' ':' | tr -d '\r')
    if [ -n  "$reprohex" ]; then
      if ! java "$TEMURIN_TOOLS_BINREPL" --inFile "$f" --outFile "$f" --hex "${reprohex}-AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA"; then
        echo "  FAILED ==> java $TEMURIN_TOOLS_BINREPL --inFile \"$f\" --outFile \"$f\" --hex \"${reprohex}-AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA\""
        exit 1
      fi
    fi
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

# Remove the MACOS dylib non-comparable data
#   MacOS Mach-O format stores a uuid value that consists of a "hash" of the code and
#   the some length part of the user's build folder.
# See https://github.com/adoptium/temurin-build/issues/2899#issuecomment-1153757419
function removeMacOSNonComparableData() {
  echo "Removing MacOS dylib non-comparable UUID from ${JDK_DIR}"

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

# Neutralize Windows VS_VERSION_INFO CompanyName
function neutraliseVsVersionInfo() {
  echo "Updating EXE/DLL VS_VERSION_INFO in ${JDK_DIR}"
  FILES=$(find "${JDK_DIR}" -type f -path '*.exe' && find "${JDK_DIR}" -type f -path '*.dll')
  for f in $FILES
    do
      echo "Removing EXE/DLL VS_VERSION_INFO from $f"

      # Neutralize CompanyName
      WindowsUpdateVsVersionInfo "$f" "CompanyName=AAAAAA"

      # Replace rdata section reference to .rsrc$ string with a neutral value
      # ???? is a length of the referenced rsrc resource section. Differing Version Info resource length means this length differs
      # fuzzy search: "????\.rsrc\$" in hex:
      if ! java "$TEMURIN_TOOLS_BINREPL" --inFile "$f" --outFile "$f" --hex "?:?:?:?:2e:72:73:72:63:24-AA:AA:AA:AA:2e:72:73:72:63:24"; then
          echo "  No .rsrc$ rdata reference found in $f"
      fi
    done

  echo "Successfully updated all EXE/DLL VS_VERSION_INFO in ${JDK_DIR}"
}

# Remove Vendor name from all binaries
function removeVendorName() {
  echo "Removing Vendor name: $VENDOR_NAME from binaries from ${JDK_DIR}"
  if [[ "$OS" =~ CYGWIN* ]]; then
   FILES=$(find "${JDK_DIR}" -type f -path '*.exe' && find "${JDK_DIR}" -type f -path '*.dll')
  elif [[ "$OS" =~ Darwin* ]]; then
   FILES=$(find "${JDK_DIR}" -type f -path '*.dylib')
  else
   FILES=$(find "${JDK_DIR}" -type f -path '*.so')
  fi
  for f in $FILES
    do
      # Neutralize vendor string with 0x00 to same length
      echo "Neutralizing $VENDOR_NAME in $f"
      if ! java "$TEMURIN_TOOLS_BINREPL" --inFile "$f" --outFile "$f" --string "${VENDOR_NAME}=" --pad 00; then
          echo "  Not found ==> java $TEMURIN_TOOLS_BINREPL --inFile \"$f\" --outFile \"$f\" --string \"${VENDOR_NAME}=\" --pad 00"
      fi
    done

  if [[ "$OS" =~ Darwin* ]]; then
    plist="${JDK_DIR}/../Info.plist"
    echo "Removing vendor string from ${plist}"
    sed -i "" "s=${VENDOR_NAME}=AAAAAA=g" "${plist}"
  fi

  echo "Successfully removed all Vendor name: $VENDOR_NAME from binaries from ${JDK_DIR}"
}

# Neutralise VersionProps.class/.java vendor strings
function neutraliseVersionProps() {
  echo "Dissassemble and remove vendor string lines from all VersionProps.class from ${JDK_DIR}"

  FILES=$(find "${JDK_DIR}" -type f -name 'VersionProps.class')
  for f in $FILES
    do
      echo "javap and remove vendor string lines from $f"
      javap -v -sysinfo -l -p -c -s -constants "$f" > "$f.javap.tmp"
      rm "$f"
      grep -v "Last modified\|$VERSION_REPL\|$VENDOR_NAME\|$VENDOR_URL\|$VENDOR_BUG_URL\|$VENDOR_VM_BUG_URL\|Classfile\|SHA-256" "$f.javap.tmp" > "$f.javap"
      rm "$f.javap.tmp"
    done

  echo "Removing vendor string lines from VersionProps.java from ${JDK_DIR}"
  FILES=$(find "${JDK_DIR}" -type f -name 'VersionProps.java')
  for f in $FILES
    do
      echo "Removing version and vendor string lines from $f"
      grep -v "$VERSION_REPL\|$VENDOR_NAME\|$VENDOR_URL\|$VENDOR_BUG_URL\|$VENDOR_VM_BUG_URL" "$f" > "$f.tmp"
      rm "$f"
      mv "$f.tmp" "$f"
    done

  echo "Successfully removed all VersionProps vendor strings from ${JDK_DIR}"
}

# Neutralise manifests Created-By from jrt-fs.jar which is built using BootJDK
function neutraliseManifests() {
  echo "Removing BootJDK Created-By: and Vendor strings from jrt-fs.jar MANIFEST.MF from ${JDK_DIR}"

  grep -v "Created-By:\|$VENDOR_NAME" "${JDK_DIR}/lib/jrt-fs-expanded/META-INF/MANIFEST.MF" > "${JDK_DIR}/lib/jrt-fs-expanded/META-INF/MANIFEST.MF.tmp"
  rm "${JDK_DIR}/lib/jrt-fs-expanded/META-INF/MANIFEST.MF"
  mv "${JDK_DIR}/lib/jrt-fs-expanded/META-INF/MANIFEST.MF.tmp" "${JDK_DIR}/lib/jrt-fs-expanded/META-INF/MANIFEST.MF"

  grep -v "Created-By:\|$VENDOR_NAME" "${JDK_DIR}/jmods/expanded_java.base.jmod/lib/jrt-fs-expanded/META-INF/MANIFEST.MF" > "${JDK_DIR}/jmods/expanded_java.base.jmod/lib/jrt-fs-expanded/META-INF/MANIFEST.MF.tmp"
  rm "${JDK_DIR}/jmods/expanded_java.base.jmod/lib/jrt-fs-expanded/META-INF/MANIFEST.MF"
  mv "${JDK_DIR}/jmods/expanded_java.base.jmod/lib/jrt-fs-expanded/META-INF/MANIFEST.MF.tmp" "${JDK_DIR}/jmods/expanded_java.base.jmod/lib/jrt-fs-expanded/META-INF/MANIFEST.MF"
}

# Neutralise vendor strings and build machine env from release file
function neutraliseReleaseFile() {
  echo "Removing Vendor strings from release file ${JDK_DIR}/release"

  if [[ "$OS" =~ Darwin* ]]; then
    sed -i "" "s=$VERSION_REPL==g" "${JDK_DIR}/release"
    sed -i "" "s=$VENDOR_NAME==g" "${JDK_DIR}/release"

    # BUILD_INFO likely different since built on different machines
    sed -i "" "s=^BUILD_INFO.*$==g" "${JDK_DIR}/release"

    # BUILD_SOURCE possibly built not using temurin build scripts
    sed -i "" "s=^BUILD_SOURCE.*$==g" "${JDK_DIR}/release"
    sed -i "" "s=^BUILD_SOURCE_REPO.*$==g" "${JDK_DIR}/release"

    # Temurin JVM_VARIANT has capital "Hotspot"
    sed -i "" "s,^JVM_VARIANT=\"Hotspot\",JVM_VARIANT=\"hotspot\",g" "${JDK_DIR}/release"
  else
    sed -i "s=$VERSION_REPL==g" "${JDK_DIR}/release"
    sed -i "s=$VENDOR_NAME==g" "${JDK_DIR}/release"

    # BUILD_INFO likely different since built on different machines
    sed -i "s=^BUILD_INFO.*$==g" "${JDK_DIR}/release"

    # BUILD_SOURCE possibly built not using temurin build scripts
    sed -i "s=^BUILD_SOURCE.*$==g" "${JDK_DIR}/release"
    sed -i "s=^BUILD_SOURCE_REPO.*$==g" "${JDK_DIR}/release"

    # Temurin JVM_VARIANT has capital "Hotspot"
    sed -i "s,^JVM_VARIANT=\"Hotspot\",JVM_VARIANT=\"hotspot\",g" "${JDK_DIR}/release"
  fi
}

if [ "$#" -ne 6 ]; then
  echo "Syntax: cmd <jdk_dir> <version_str> <vendor_name> <vendor_url> <vendor_bug_url> <vendor_vm_bug_url>"
  exit 1
fi

if [ ! -d "${JDK_DIR}" ]; then
  echo "$JDK_DIR does not exist"
  exit 1
fi

OS=$("uname")
if [[ "$OS" =~ CYGWIN* ]]; then
  echo "On Windows"
elif [[ "$OS" =~ Linux* ]]; then
  echo "On Linux"
elif [[ "$OS" =~ Darwin* ]]; then
  echo "On MacOS"
  JDK_DIR="${JDK_DIR}/Contents/Home"
else
  echo "Do not recognise OS: $OS"
  exit 1
fi

expandJDK "$JDK_DIR" "$OS"

echo "Removing all Signatures from ${JDK_DIR} in a deterministic way"

# Remove original certs
removeSignatures "$JDK_DIR" "$OS"

# Sign with temporary cert, so we can remove it and end up with a deterministic result
tempSign "$JDK_DIR" "$OS"

# Remove temporary cert
removeSignatures "$JDK_DIR" "$OS"

echo "Successfully removed all Signatures from ${JDK_DIR}"

removeExcludedFiles

if [[ "$OS" =~ CYGWIN* ]]; then
  neutraliseVsVersionInfo
fi

if [[ "$OS" =~ CYGWIN* ]]; then
 removeWindowsNonComparableData
fi

if [[ "$OS" =~ Darwin* ]]; then
  removeMacOSNonComparableData
fi

removeVendorName

neutraliseVersionProps

neutraliseManifests

neutraliseReleaseFile

echo "***********"
echo "SUCCESS :-)"
echo "***********"

