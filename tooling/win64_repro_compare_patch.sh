#!/bin/bash

set -e

JDK_DIR="$1"
SELF_CERT_FILE="$2"
SELF_CERT_PASS="$3"

if [ ! -d "${JDK_DIR}" ]; then
  echo "$JDK_DIR does not exist"
  exit 1
fi

echo "Expanding the 'modules' Image to remove signatures from within.."
jimage extract --dir "${JDK_DIR}/lib/modules_extracted" "${JDK_DIR}/lib/modules"
rm ${JDK_DIR}/lib/modules

echo "Expanding the 'lib/jrt-fs.jar' to remove signatures from within.."
mkdir ${JDK_DIR}/lib/jrt-fs-expanded
unzip -d ${JDK_DIR}/lib/jrt-fs-expanded ${JDK_DIR}/lib/jrt-fs.jar
rm ${JDK_DIR}/lib/jrt-fs.jar

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

echo "Removing all Signatures from ${JDK_DIR}"
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

echo "Successfully removed all SELF_CERT Signatures from ${JDK_DIR}"

echo "Removing lib/security/cacerts as different ones are used by vendors"
rm ${JDK_DIR}/lib/security/cacerts


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

    # Remove version suffix, eg:17.0.6+10-LTS, this might not be present in the exe/dll
    java BinRepl --inFile "$f" --outFile "$f" --string "17.0.6+10-LTS=17.0.6+10" --pad "00"
  done

echo "Successfully removed all EXE/DLL timestamps, CRC and debug repro hex from ${JDK_DIR}"

echo "Removing EXE/DLL VS_VERSION_INFO from ${JDK_DIR}"
FILES=$(find "${JDK_DIR}" -type f -path '*.exe' && find "${JDK_DIR}" -type f -path '*.dll')
for f in $FILES
  do
    echo "Removing EXE/DLL VS_VERSION_INFO from $f"
    if ! java WinVersionInfoDel --inFile "$f" --outFile "$f"; then
        echo "  FAILED ==> java WinVersionInfoDel --inFile \"$f\" --outFile \"$f\""
	exit 1
    fi
  done

echo "Successfully removed all EXE/DLL VS_VERSION_INFO from ${JDK_DIR}"

echo "***********"
echo "SUCCESS :-)"
echo "***********"

