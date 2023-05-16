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
SELF_CERT_FILE="$2"
SELF_CERT_PASS="$3"
VERSION_REPL="$4"
VENDOR_NAME="$5"
VENDOR_URL="$6"
VENDOR_BUG_URL="$7"
VENDOR_VM_BUG_URL="$8"

if [ "$#" -ne 8 ]; then
  echo "Syntax: cmd <jdk_dir> <cert_file> <cert_pass> <version_str> <vendor_name> <vendor_url> <vendor_bug_url> <vendor_vm_bug_url>"
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
else
  echo "Do not recognise OS: $OS"
  exit 1
fi

echo "Expanding the 'modules' Image to remove signatures from within.."
jimage extract --dir "${JDK_DIR}/lib/modules_extracted" "${JDK_DIR}/lib/modules"
rm ${JDK_DIR}/lib/modules

echo "Expanding the 'src.zip' to normalize file permissions"
unzip ${JDK_DIR}/lib/src.zip -d ${JDK_DIR}/lib/src_zip_expanded
rm ${JDK_DIR}/lib/src.zip

echo "Expanding jmods to process binaries within"
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

echo "Removing all Signatures from ${JDK_DIR}"
if [[ "$OS" =~ CYGWIN* ]]; then
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

  echo "Removing all SELF_CERT Signatures from ${JDK_DIR}"
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
fi
echo "Successfully removed all SELF_CERT Signatures from ${JDK_DIR}"

if [[ "$OS" =~ CYGWIN* ]]; then
  excluded="cacerts classes.jsa classes_nocoops.jsa SystemModules\$0.class SystemModules\$all.class SystemModules\$default.class"
else
  excluded="cacerts classes.jsa classes_nocoops.jsa"
fi
echo "Removing excluded files known to differ: ${excluded}"
for exclude in $excluded
  do
    FILES=$(find "${JDK_DIR}" -type f -name "$exclude")
    for f in $FILES
      do
        echo "Removing $f"
	rm $f
      done
  done

if [[ "$OS" =~ CYGWIN* ]]; then
  echo "Removing java.base module-info.class, known to differ by jdk.jpackage module hash"
  rm "${JDK_DIR}/jmods/expanded_java.base.jmod/classes/module-info.class"
  rm "${JDK_DIR}/lib/modules_extracted/java.base/module-info.class"
fi

echo "Successfully removed all excluded files from ${JDK_DIR}"

if [[ "$OS" =~ CYGWIN* ]]; then
  echo "Updating EXE/DLL VS_VERSION_INFO in ${JDK_DIR}"
  FILES=$(find "${JDK_DIR}" -type f -path '*.exe' && find "${JDK_DIR}" -type f -path '*.dll')
  for f in $FILES
    do
      echo "Removing EXE/DLL VS_VERSION_INFO from $f"
      # Neutralize CompanyName
      oldVSInfoLen=$(WindowsUpdateVsVersionInfo "$f" "CompanyName=AAAAAA" | grep "OldLen" | tr -d ' ' | cut -d'=' -f2)
      # Replace rdata section reference to .rsrc$ string with a neutral value
      # ???? is a length of the referenced rsrc resource section. Differing Version Info resource length means this length differs
      # fuzzy search: "????\.rsrc\$" in hex:
      if ! java BinRepl --inFile "$f" --outFile "$f" --hex "?:?:?:?:2e:72:73:72:63:24-AA:AA:AA:AA:2e:72:73:72:63:24"; then
          echo "  No .rsrc$ rdata reference found in $f"
      fi
    done

  echo "Successfully updated all EXE/DLL VS_VERSION_INFO in ${JDK_DIR}"
fi

if [[ "$OS" =~ CYGWIN* ]]; then
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
    if [ ! -z "$reprohex" ]; then
      if ! java BinRepl --inFile "$f" --outFile "$f" --hex "${reprohex}-AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA"; then
	echo "  FAILED ==> java BinRepl --inFile \"$f\" --outFile \"$f\" --hex \"${reprohex}-AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA\""
	exit 1
      fi
    fi
    hexstr="00000000"
    timestamphex=${hexstr:0:-${#timestamp}}$timestamp
    timestamphexLE="${timestamphex:6:2}:${timestamphex:4:2}:${timestamphex:2:2}:${timestamphex:0:2}"
    if ! java BinRepl --inFile "$f" --outFile "$f" --hex "${timestamphexLE}-AA:AA:AA:AA"; then
        echo "  FAILED ==> java BinRepl --inFile \"$f\" --outFile \"$f\" --hex \"${timestamphexLE}-AA:AA:AA:AA\""
	exit 1
    fi
    if [ ! -z "$reprohexhalf" ]; then
      if ! java BinRepl --inFile "$f" --outFile "$f" --hex "${reprohexhalf}-AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA"; then
        echo "  FAILED ==> java BinRepl --inFile \"$f\" --outFile \"$f\" --hex \"${reprohexhalf}-AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA\""
	exit 1
      fi
    fi

    # Prefix checksum to 8 digits
    hexstr="00000000"
    checksumhex=${hexstr:0:-${#checksum}}$checksum
    checksumhexLE="${checksumhex:6:2}:${checksumhex:4:2}:${checksumhex:2:2}:${checksumhex:0:2}"
    if ! java BinRepl --inFile "$f" --outFile "$f" --hex "${checksumhexLE}-AA:AA:AA:AA" --firstOnly --32bitBoundaryOnly; then
        echo "  FAILED ==> java BinRepl --inFile \"$f\" --outFile \"$f\" --hex \"${checksumhexLE}-AA:AA:AA:AA\" --firstOnly --32bitBoundaryOnly"
	exit 1
    fi
  done
 echo "Successfully removed all EXE/DLL timestamps, CRC and debug repro hex from ${JDK_DIR}"
fi

echo "Removing Vendor name: $VENDOR_NAME from binaries from ${JDK_DIR}"
if [[ "$OS" =~ CYGWIN* ]]; then
 FILES=$(find "${JDK_DIR}" -type f -path '*.exe' && find "${JDK_DIR}" -type f -path '*.dll')
else
 FILES=$(find "${JDK_DIR}" -type f -path '*.so')
fi
for f in $FILES
  do
    # Neutralize vendor string with 0x00 to same length
    echo "Neutralizing $VENDOR_NAME in $f"
    if ! java BinRepl --inFile "$f" --outFile "$f" --string "${VENDOR_NAME}=" --pad 00; then
        echo "  Not found ==> java BinRepl --inFile \"$f\" --outFile \"$f\" --string \"${VENDOR_NAME}=\" --pad 00"
    fi
  done

echo "Successfully removed all Vendor name: $VENDOR_NAME from binaries from ${JDK_DIR}"

echo "Dissassemble and remove vendor string lines from all VersionProps.class from ${JDK_DIR}"
FILES=$(find "${JDK_DIR}" -type f -name 'VersionProps.class')
for f in $FILES
  do
    echo "javap and remove vendor string lines from $f"
    javap -v -sysinfo -l -p -c -s -constants $f > $f.javap.tmp
    rm $f
    grep -v "Last modified\|$VERSION_REPL\|$VENDOR_NAME\|$VENDOR_URL\|$VENDOR_BUG_URL\|$VENDOR_VM_BUG_URL\|Classfile\|SHA-256" $f.javap.tmp > $f.javap
    rm $f.javap.tmp
  done

echo "Successfully removed all VersionProps.class vendor strings from ${JDK_DIR}"

echo "Remove all version and vendor string lines in VersionProps.java from ${JDK_DIR}"
FILES=$(find "${JDK_DIR}" -type f -name 'VersionProps.java')
for f in $FILES
  do
    echo "Removing version and vendor string lines from $f"
    grep -v "$VERSION_REPL\|$VENDOR_NAME\|$VENDOR_URL\|$VENDOR_BUG_URL\|$VENDOR_VM_BUG_URL" $f > $f.tmp
    rm $f
    mv $f.tmp $f
  done

echo "Successfully removed all VersionProps.java vendor strings from ${JDK_DIR}"

echo "Removing BootJDK Created-By: and Vendor strings from jrt-fs.jar MANIFEST.MF from ${JDK_DIR}"
grep -v "Created-By:\|$VENDOR_NAME" "${JDK_DIR}/lib/jrt-fs-expanded/META-INF/MANIFEST.MF" > "${JDK_DIR}/lib/jrt-fs-expanded/META-INF/MANIFEST.MF.tmp"
rm "${JDK_DIR}/lib/jrt-fs-expanded/META-INF/MANIFEST.MF"
mv "${JDK_DIR}/lib/jrt-fs-expanded/META-INF/MANIFEST.MF.tmp" "${JDK_DIR}/lib/jrt-fs-expanded/META-INF/MANIFEST.MF"

grep -v "Created-By:\|$VENDOR_NAME" "${JDK_DIR}/jmods/expanded_java.base.jmod/lib/jrt-fs-expanded/META-INF/MANIFEST.MF" > "${JDK_DIR}/jmods/expanded_java.base.jmod/lib/jrt-fs-expanded/META-INF/MANIFEST.MF.tmp"
rm "${JDK_DIR}/jmods/expanded_java.base.jmod/lib/jrt-fs-expanded/META-INF/MANIFEST.MF"
mv "${JDK_DIR}/jmods/expanded_java.base.jmod/lib/jrt-fs-expanded/META-INF/MANIFEST.MF.tmp" "${JDK_DIR}/jmods/expanded_java.base.jmod/lib/jrt-fs-expanded/META-INF/MANIFEST.MF"

echo "Removing Vendor strings from release file ${JDK_DIR}/release"
sed -i "s=$VERSION_REPL==g" "${JDK_DIR}/release"
sed -i "s=$VENDOR_NAME==g" "${JDK_DIR}/release"

echo "***********"
echo "SUCCESS :-)"
echo "***********"

