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
#  classes.jsa, classes_nocoops.jsa - CDS archive caches will differ due to Vendor string differences
function removeExcludedFiles() {
  excluded="NOTICE cacerts classes.jsa classes_nocoops.jsa"

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

  echo "Successfully removed all excluded files from ${JDK_DIR}"
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
      echo "javap and re-order ModuleAttributes for $f"
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
  echo "Removing SystemModules ModulesHashes\$Builder differences"
  for systemModule in $systemModules
    do
      FILES=$(find "${JDK_DIR}" -type f -name "$systemModule")
      for f in $FILES
        do
          echo "Processing $f"
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
              echo "==> Found $module ModuleHashes\$Builder function, skipping hash parameter"
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

# Remove the Windows EXE/DLL timestamps and internal VS CRC and debug repro hex values
# The Windows PE format contains various values determined from the binary content
# which will vary due to the different Vendor branding
#   timestamp - Used to be an actual timestamp but MSFT changed this to a checksum determined from binary content
#   checksum  - A checksum value of the binary
#   reprohex  - A hex UUID to identify the binary version, again generated from binary content
function removeWindowsNonComparableData() {
 echo "Removing EXE/DLL timestamps, CRC and debug repro hex from ${JDK_DIR}"

 # We need to do this for all executables if patching VS_VERSION_INFO
 if [[ "$PATCH_VS_VERSION_INFO" = true ]]; then
    FILES=$(find "${JDK_DIR}" -type f -path '*.exe' && find "${JDK_DIR}" -type f -path '*.dll')
 else
    FILES=$(find "${JDK_DIR}" -type f -name 'jvm.dll')
 fi
 for f in $FILES
  do
    echo "Removing EXE/DLL non-comparable timestamp, CRC, debug repro hex from $f"

    # Determine non-comparable data using dumpbin
    dmpfile="$f.dumpbin.tmp"
    rm -f "$dmpfile"
    if ! dumpbin "$f" /ALL > "$dmpfile"; then
        echo "  FAILED == > dumpbin \"$f\" /ALL > $dmpfile"
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

# Neutralize Windows VS_VERSION_INFO CompanyName from the resource compiled PE section
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
processModuleInfo

# Patch Windows VS_VERSION_INFO[COMPANY_NAME]
if [[ "$OS" =~ CYGWIN* ]] && [[ "$PATCH_VS_VERSION_INFO" = true ]]; then
  # Neutralise COMPANY_NAME
  neutraliseVsVersionInfo

  # SystemModules$*.class's differ due to hash differences from COMPANY_NAME
  removeSystemModulesHashBuilderParams
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

removeNonJdkFiles

echo "***********"
echo "SUCCESS :-)"
echo "***********"

