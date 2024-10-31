#!/bin/bash
# shellcheck disable=SC1091
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

JDK_DIR=""
VERSION_REPL=""
VENDOR_NAME=""
VENDOR_URL=""
VENDOR_BUG_URL=""
VENDOR_VM_BUG_URL=""
PATCH_VS_VERSION_INFO=false

# Parse arguments
while [[ $# -gt 0 ]] && [[ ."$1" = .-* ]] ; do
  opt="$1";
  shift;

  case "$opt" in
        "--jdk-dir" )
        JDK_DIR="$1"; shift;;

        "--version-string" )
        VERSION_REPL="$1"; shift;;

        "--vendor-name" )
        VENDOR_NAME="$1"; shift;;

        "--vendor_url" )
        VENDOR_URL="$1"; shift;;

        "--vendor-bug-url" )
        VENDOR_BUG_URL="$1"; shift;;

        "--vendor-vm-bug-url" )
        VENDOR_VM_BUG_URL="$1"; shift;;

        "--patch-vs-version-info" )
        PATCH_VS_VERSION_INFO=true;;

        *) echo >&2 "Invalid option: ${opt}"
        echo 'Syntax: comparable_patch.sh --jdk-dir "<jdk_home_dir>" --version-string "<version_str>" --vendor-name "<vendor_name>" --vendor_url "<vendor_url>" --vendor-bug-url "<vendor_bug_url>" --vendor-vm-bug-url "<vendor_vm_bug_url>" [--patch-vs-version-info]'; exit 1;;
  esac
done

if [ -z "$JDK_DIR" ] || [ -z "$VERSION_REPL" ] || [ -z "$VENDOR_NAME" ] || [ -z "$VENDOR_URL" ] || [ -z "$VENDOR_BUG_URL" ] || [ -z "$VENDOR_VM_BUG_URL" ]; then
  echo "Error: Missing argument"
  echo 'Syntax: comparable_patch.sh --jdk-dir "<jdk_home_dir>" --version-string "<version_str>" --vendor-name "<vendor_name>" --vendor_url "<vendor_url>" --vendor-bug-url "<vendor_bug_url>" --vendor-vm-bug-url "<vendor_vm_bug_url>" [--patch-vs-version-info]'
  exit 1
fi

echo "Patching:"
echo "  JDK_DIR=$JDK_DIR"
echo "  VERSION_REPL=$VERSION_REPL"
echo "  VENDOR_NAME=$VENDOR_NAME"
echo "  VENDOR_URL=$VENDOR_URL"
echo "  VENDOR_BUG_URL=$VENDOR_BUG_URL"
echo "  VENDOR_VM_BUG_URL=$VENDOR_VM_BUG_URL"
echo "  PATCH_VS_VERSION_INFO=$PATCH_VS_VERSION_INFO"

# Remove excluded files known to differ
#  NOTICE - Vendor specfic notice text file
#  cacerts - Vendors use different cacerts
#  classlist - Used to generate CDS archives, can vary due to different build machine environment
#  classes.jsa, classes_nocoops.jsa - CDS archive caches will differ due to Vendor string differences
function removeExcludedFiles() {
  excluded="NOTICE cacerts classlist classes.jsa classes_nocoops.jsa"

  echo "Removing excluded files known to differ: ${excluded}"
  for exclude in $excluded
    do
      FILES=$(find "${JDK_DIR}" -type f -name "$exclude")
      for f in $FILES
        do
          echo "Removing $f"
          rm -f "$f"
        done
    done

  echo "Successfully removed all excluded files from ${JDK_DIR}"
}

# Neutralize Windows VS_VERSION_INFO CompanyName from the resource compiled PE section
function neutraliseVsVersionInfo() {
  echo "Updating EXE/DLL VS_VERSION_INFO in ${JDK_DIR}"
  FILES=$(find "${JDK_DIR}" -type f -path '*.exe' && find "${JDK_DIR}" -type f -path '*.dll')
  for f in $FILES
    do
      echo "Removing EXE/DLL VS_VERSION_INFO from $f"
      f=$(cygpath -w "$f")

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

# Remove Vendor name from executables
#   If patching VS_VERSION_INFO, then all executables need patching,
#   otherwise just jvm library that contains the Vendor string differences.
function removeVendorName() {
  echo "Removing Vendor name: $VENDOR_NAME from executables from ${JDK_DIR}"

  if [[ "$OS" =~ CYGWIN* ]]; then
    # We need to do this for all executables if patching VS_VERSION_INFO
    if [[ "$PATCH_VS_VERSION_INFO" = true ]]; then
      FILES=$(find "${JDK_DIR}" -type f -path '*.exe' && find "${JDK_DIR}" -type f -path '*.dll')
    else
      FILES=$(find "${JDK_DIR}" -type f -name 'jvm.dll')
    fi
  elif [[ "$OS" =~ Darwin* ]]; then
   FILES=$(find "${JDK_DIR}" -type f -name 'libjvm.dylib')
  else
   FILES=$(find "${JDK_DIR}" -type f -name 'libjvm.so')
  fi
  for f in $FILES
    do
      # Neutralize vendor string with 0x00 to same length
      echo "Neutralizing $VENDOR_NAME in $f"
      if [[ "$OS" =~ CYGWIN* ]]; then
          f=$(cygpath -w "$f")
      fi
      if ! java "$TEMURIN_TOOLS_BINREPL" --inFile "$f" --outFile "$f" --string "${VENDOR_NAME}=" --pad 00; then
          echo "  Not found ==> java $TEMURIN_TOOLS_BINREPL --inFile \"$f\" --outFile \"$f\" --string \"${VENDOR_NAME}=\" --pad 00"
      fi
    done

  if [[ "$OS" =~ Darwin* ]]; then
    plist="${JDK_DIR}/../Info.plist"
    echo "Removing vendor string from ${plist}"
    sed -i "" "s=${VENDOR_NAME}=AAAAAA=g" "${plist}"
  fi

  echo "Successfully removed all Vendor name: $VENDOR_NAME from executables from ${JDK_DIR}"
}

# Neutralise VersionProps.class/.java vendor strings
function neutraliseVersionProps() {
  echo "Dissassemble and remove vendor string lines from all VersionProps.class from ${JDK_DIR}"

  FILES=$(find "${JDK_DIR}" -type f -name 'VersionProps.class')
  for f in $FILES
    do
      echo "javap and remove vendor string lines from $f"
      if [[ "$OS" =~ CYGWIN* ]]; then
        ff=$(cygpath -w "$f")
      else
	ff=$f
      fi
      javap -v -sysinfo -l -p -c -s -constants "$ff" > "$f.javap.tmp"
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
    # Remove Vendor versions
    sed -i "" "s=$VERSION_REPL==g" "${JDK_DIR}/release"
    sed -i "" "s=$VENDOR_NAME==g" "${JDK_DIR}/release"

    # Temurin BUILD_* likely different since built on different machines and bespoke to Temurin
    sed -i "" "/^BUILD_INFO/d" "${JDK_DIR}/release"
    sed -i "" "/^BUILD_SOURCE/d" "${JDK_DIR}/release"
    sed -i "" "/^BUILD_SOURCE_REPO/d" "${JDK_DIR}/release"

    # Remove bespoke Temurin fields
    sed -i "" "/^SOURCE/d" "${JDK_DIR}/release"
    sed -i "" "/^FULL_VERSION/d" "${JDK_DIR}/release"
    sed -i "" "/^SEMANTIC_VERSION/d" "${JDK_DIR}/release"
    sed -i "" "/^JVM_VARIANT/d" "${JDK_DIR}/release"
    sed -i "" "/^JVM_VERSION/d" "${JDK_DIR}/release"
    sed -i "" "/^JVM_VARIANT/d" "${JDK_DIR}/release"
    sed -i "" "/^IMAGE_TYPE/d" "${JDK_DIR}/release"
  else
    # Remove Vendor versions
    sed -i "s=$VERSION_REPL==g" "${JDK_DIR}/release"
    sed -i "s=$VENDOR_NAME==g" "${JDK_DIR}/release"

    # Temurin BUILD_* likely different since built on different machines and bespoke to Temurin
    sed -i "/^BUILD_INFO/d" "${JDK_DIR}/release"
    sed -i "/^BUILD_SOURCE/d" "${JDK_DIR}/release"
    sed -i "/^BUILD_SOURCE_REPO/d" "${JDK_DIR}/release"

    # Remove bespoke Temurin fields
    sed -i "/^SOURCE/d" "${JDK_DIR}/release"
    sed -i "/^FULL_VERSION/d" "${JDK_DIR}/release"
    sed -i "/^SEMANTIC_VERSION/d" "${JDK_DIR}/release"
    sed -i "/^JVM_VARIANT/d" "${JDK_DIR}/release"
    sed -i "/^JVM_VERSION/d" "${JDK_DIR}/release"
    sed -i "/^JVM_VARIANT/d" "${JDK_DIR}/release"
    sed -i "/^IMAGE_TYPE/d" "${JDK_DIR}/release"
  fi
}

# The last four bytes of a .gnu_debuglink ELF section contains a
# 32-bit cyclic redundancy check (CRC32) of the separate .debuginfo
# file.  A given .debuginfo file will differ when compiled in
# different environments.  Specifically, if some declaration in a
# system header is referenced by OpenJDK source code, and that
# declaration's line number changes between environments, the
# .debuginfo files will have many bytewise differences.  Even
# seemingly inconsequential header changes will result in large
# .debuginfo differences, for example, additions of new preprocessor
# macros, or comment additions and deletions.  The CRC32 is thus
# sensitive to almost any textual changes to system headers.  This
# function changes the four bytes to zeroes.
function neutraliseDebuglinkCRCs() {
  if [[ "$OS" =~ CYGWIN* ]] || [[ "$OS" =~ Darwin* ]]; then
    # Assume Cygwin and Darwin toolchains do not produce .gnu_debuglink sections.
    return
  fi
  elf_magic="^7f454c46$"
  # Does not handle filenames with newlines because the hexdump format does not support \0. 
  find "${JDK_DIR}" -type f \! -name '*.debuginfo' -print -exec hexdump -n 4 -e '4/1 "%.2x" "\n"' '{}' ';' \
    | grep --no-group-separator -B 1 "${elf_magic}" | grep -v "${elf_magic}" \
    | while read -r -d $'\n' file; do
    if objdump -Fsj .gnu_debuglink "${file}" >/dev/null 2>&1; then
      echo "Zeroing .gnu_debuglink cyclic redundancy check bytes in ${file}"
      section="$(objdump -Fsj .gnu_debuglink "${file}")"
      section_offset_within_file=$((16#$(echo "${section}" | awk '/^Contents of section/ { sub(/\x29/, ""); sub(/0x/, ""); print $9; }')))
      contents_line="$(echo "${section}" | sed '/^Contents of section.*$/q' | wc -l)"
      section_bytes_in_hex="$(echo "${section}" | tail -q -n +$((contents_line + 1)) | cut -b 7-41 | tr -d ' \n')"
      check_length=4
      hex_chars_per_byte=2
      check_offset_within_section="$((${#section_bytes_in_hex} / hex_chars_per_byte - check_length))"
      check_offset_within_file="$((section_offset_within_file + check_offset_within_section))"
      printf "%0.s\0" $(seq 1 "${check_length}") | dd of="${file}" bs=1 seek="${check_offset_within_file}" count="${check_length}" conv=notrunc status=none
    fi
  done
}

# Remove some non-JDK files that some Vendors distribute
# - NEWS : Some Vendors provide a NEWS text file
# - demo : Not all vendors distribute the demo examples 
function removeNonJdkFiles() {
  echo "Removing non-JDK files"
  
  rm -f  "${JDK_DIR}/NEWS"
  rm -rf "${JDK_DIR}/demo"
}

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

# Needed due to vendor variation in jmod re-packing after signing, putting attributes in different order
# Comparable patch, as per read-me, requires java on path
processModuleInfo "${JDK_DIR}" "${OS}" "$(dirname "$(dirname "$(readlink -f  "$(which java)")")")"

# Patch Windows VS_VERSION_INFO[COMPANY_NAME]
if [[ "$OS" =~ CYGWIN* ]] && [[ "$PATCH_VS_VERSION_INFO" = true ]]; then
  # Neutralise COMPANY_NAME
  neutraliseVsVersionInfo
fi

if [[ "$OS" =~ CYGWIN* ]] || [[ "$OS" =~ Darwin* ]]; then
  # SystemModules$*.class's differ due to hash differences from Windows COMPANY_NAME and Signatures
  removeSystemModulesHashBuilderParams "${JDK_DIR}" "${OS}" "$(dirname "$(dirname "$(readlink -f  "$(which java)")")")"
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

neutraliseDebuglinkCRCs

removeNonJdkFiles

echo "***********"
echo "SUCCESS :-)"
echo "***********"

