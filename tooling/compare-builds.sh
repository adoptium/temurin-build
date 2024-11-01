#!/bin/bash
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

#
# useful variables: DO_BREAK DO_RESULTS
#                   DO_DEPS RFAT
#                   JAVA_HOME               

#######################################################################################################################
# This is top level script for comparing two jdks.  It 
# This script expects exactly two args - tag:os.arch/dir/archive, two times
# eg: compare_builds.sh  /usr/lib/jvm/java-21-openjdk /my/home/my_custom_tarball.tar.xz
# eg: compare_builds.sh  /my/custom/dir/with_jdk jdk-21.0.4+7:windows.x64
# if the parameter is tag, the temurin jdk of given tag:os.arch is downloaded
# yo can omit the :os.arch part, then it will be guessed... but you may know better
# It copies and creates all in CWD!!!!
# Pass the files/dirs as absolute values, it should not be that hard
# It is useful to have JAVA_HOME pointing to some other JDK used to compile and run supporting files
# otherwise one of the provided JDKs will be duplicated, and used
# for your own safety, do not run it as root
#
# The JDK you are comparing is launched to get various info about itself
# If you need to compare jdks on different platform then they are for, you need to go manually.
#######################################################################################################################

## shellcheck disable=SC2126
## resolve folder of this script, following all symlinks,
## http://stackoverflow.com/questions/59895/can-a-bash-script-tell-what-directory-its-stored-in
SCRIPT_SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SCRIPT_SOURCE" ]; do # resolve $SOURCE until the file is no longer a symlink
  SCRIPT_DIR="$( cd -P "$( dirname "$SCRIPT_SOURCE" )" && pwd )"
  SCRIPT_SOURCE="$(readlink "$SCRIPT_SOURCE")"
  # if $SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
  [[ $SCRIPT_SOURCE != /* ]] && SCRIPT_SOURCE="$SCRIPT_DIR/$SCRIPT_SOURCE"
done
COMPARE_WAPPER_SCRIPT_DIR="$( cd -P "$( dirname "$SCRIPT_SOURCE" )" && pwd )"
readonly COMPARE_WAPPER_SCRIPT_DIR

set -euxo pipefail

function processArgs() {
  set +x
    if [ ! "$#" -eq 2 ] ; then
      echo "This script expects exactly two args - tag/dir/archive, two times"
      echo "eg: compare_builds.sh  /usr/lib/jvm/java-21-openjdk /my/home/my_custom_tarball.tar.xz"
      echo "eg: compare_builds.sh  /my/custom/dir/with_jdk jdk-21.0.4+7"
      echo "if the parameter is tag, the temurin jdk of given tag:os.arch is downloaded"
      echo " yo can omit the :os.arch part, then it will be guessed... but you may know better"
      echo "It copies and creates all in CWD!!!! $(pwd)"
      echo "Pass the files/dirs as absolute values, it should not be that hard"
      echo "It is usefull to have JAVA_HOME pointing to some other JDK used to compile and runn supporting files"
      echo "otherwise one of the provided jdks will be duplicated, and used"
      echo "# for your own safety, do not run it as root"
      exit 1
    fi
    JDK1_STRING="${1}"
    JDK2_STRING="${2}"
    local r=0
    initialInfo "${JDK1_STRING}" || r=$?
    if [ $r -eq 1 ] ; then
      JDK1_STRING="${JDK1_STRING}:${DECTED_OS}.${DECTED_ARCH}"
      echo "Using autodetected: $JDK1_STRING"
    fi
    local r=0
    initialInfo "${JDK2_STRING}" || r=$?
    if [ $r -eq 1 ] ; then
      JDK2_STRING="${JDK2_STRING}:${DECTED_OS}.${DECTED_ARCH}"
      echo "Using autodetected: $JDK2_STRING"
    fi
    if [ -n "${JAVA_HOME:-}" ] ; then
      echo "JAVA_HOME is set to ${JAVA_HOME} and will be used as independnet jdk"
    else
      if [ -d "${1}"  ] ; then
         export JAVA_HOME="${1}"
         echo "JAVA_HOME was set to ${JAVA_HOME} and will be used as independnet jdk"
      elif [ -d "${2}"  ] ; then
         export JAVA_HOME="${2}"
         echo "JAVA_HOME was set to ${JAVA_HOME} and will be used as independnet jdk"
      else
        if [ -f "${1}"  ] ; then
          echo "${1} will be unpacked second times and used as JAVA_HOME."
        else
          echo "once ${1} is downloaded, will be unpacked second times and used as JAVA_HOME"
        fi
         echo "We recommend to to set JAVA_HOME for next time."
      fi
    fi
  set -x
}

function detectOsAndArch() {
  DECTED_OS=linux
  DECTED_ARCH=$(uname -m)
  if [ "${DECTED_ARCH}" == "x86_64" ]  ; then
    DECTED_ARCH=x64
  fi
  if uname | grep "CYGWIN" ; then
    DECTED_OS=windows
  fi
  echo "${DECTED_OS}.${DECTED_ARCH}"
}

function initialInfo() {
  if [ -d "${1}" ] ; then
    echo "${1} is directory, will be copied"
  elif [ -f "${1}" ] ; then
    echo "${1} is file, will be unpacked"
  else
    echo "${1} is tag:os.arch, will be downloaded and unpacked"
    # this works only with pipefail
    if ! echo "${1}" | grep -F . | grep -F : ; then
      echo -n "it is not tag:os.arch, missing :os.arch? Autodetecting: "
      detectOsAndArch
      return 1
    fi    
  fi
  return 0
}


function getReleases() {
  local mver="${1}"
  local eaga="${2}"
  local arch="${3}"
  local ooss="${4}"
  curl -sLkX 'GET' \
  "https://api.adoptium.net/v3/assets/version/${mver}?architecture=${arch}&heap_size=normal&image_type=jdk&jvm_impl=hotspot&os=${ooss}&page=0&page_size=10&project=jdk&release_type=${eaga}&semver=false&sort_method=DEFAULT&sort_order=DESC&vendor=eclipse" \
  -H 'accept: application/json' |  grep "$5"
}

function getSurroundingReleases() {
  local arch="${1}"
  local ooss="${2}"
  local pattern="${3}"
  local human_tag="${4}"
  local url_tag="${5}"
  for x in ea ga; do
    echo "$x [,$human_tag] (so X<=$human_tag) ${arch} ${ooss}"
    getReleases "%5B%2C${url_tag}%5D" "${x}" "${arch}" "${ooss}" "${pattern}"
    echo "$x [$human_tag,] (so X>=$human_tag) ${arch} ${ooss}"
    getReleases "%5B${url_tag}%2C%5D" "${x}" "${arch}" "${ooss}" "${pattern}"
  done
}

function initWindowsTools() {
  set +u
    if [ -z "${MSBASE_PATH}" ] ; then
      MSBASE_PATH="/cygdrive/c/Program Files/Microsoft Visual Studio/"
    fi
    test -d "${MSBASE_PATH}"
    if [ -z "${MSVSC}" ] ; then
      MSVSC=$(find "$MSBASE_PATH" -type d | grep Hostx64/x64$ | head -n 1 )
    fi
    test -d "${MSVSC}"
    if [ -z "${WINKIT}" ] ; then
      WINKIT=$(dirname "$(find '/cygdrive/c/Program Files (x86)/Windows Kits' | grep  x64/signtool.exe$ | head -n 1)")
    fi
    test -d "${WINKIT}"
    if [ -z "${MSVSCBUILDTOOLS}" ] ; then
      MSVSCBUILDTOOLS=$(find "$MSBASE_PATH" -type d | grep Auxiliary/Build$ | head -n 1 )
    fi
    test -d "${MSVSCBUILDTOOLS}"
  set -u
}

function setMsvscToPath() {
  # should add cl.exe and dumpbin.exe which are necessary to patch binaries
  export PATH="$MSVSC:$PATH_BACKUP_MSVC"
  # should add signtool.exe to path to do the same
  export PATH="$WINKIT:$PATH"
  export PATH="$FUTURE_PATH_ADDITIONS:$PATH"
}

function compileAndSetToFuturePath() {
  pushd "$MSVSCBUILDTOOLS"
    rm -f WindowsUpdateVsVersionInfo.obj
    # withotu call, the vcvars64.bat crates subshell (sub cmd)
    echo "
      call vcvars64.bat
      cl $(cygpath -m "${COMPARE_WAPPER_SCRIPT_DIR}/src/c/WindowsUpdateVsVersionInfo.c") version.lib
    " > bat.bat
    chmod 777 bat.bat
    ./bat.bat
    # copy it to any dir on path or add this dir to path
    mv WindowsUpdateVsVersionInfo.exe  "$FUTURE_PATH_ADDITIONS"
    rm WindowsUpdateVsVersionInfo.obj bat.bat
  popd
}

# on windows/cygwin it is weird
# shoudl eb needed only on that "third" jdk if copied/extracted
function chmod777() {
  local JDK_DIR="${1}"
  test -f "${JDK_DIR}/bin/java"
  chmod -R 777 "${JDK_DIR}"
}


function getKeysForComparablePatch() {
  local JDK_DIR="${1}"
  set +e
    JAVA_VENDOR="$("$JDK_DIR/bin/java" -XshowSettings 2>&1| grep 'java.vendor = ' | sed 's/.* = //' | sed 's/\r.*//' )"
    JAVA_VENDOR_URL="$("$JDK_DIR/bin/java" -XshowSettings 2>&1| grep 'java.vendor.url = ' | sed 's/.* = //' | sed 's/\r.*//')"
    JAVA_VENDOR_URL_BUG="$("$JDK_DIR/bin/java" -XshowSettings 2>&1| grep 'java.vendor.url.bug = ' | sed 's/.* = //' | sed 's/\r.*//')"
    JAVA_VENDOR_VERSION="$("$JDK_DIR/bin/java" -XshowSettings 2>&1| grep 'java.vendor.version = ' | sed 's/.* = //' | sed 's/\r.*//')"
  set -e
}

function deps() {
  if uname | grep "CYGWIN" ; then
    if uname -m | grep "x86_64" ; then
      echo "Cygwin x86_64"
      echo "The detection of MS tools is fragile, consider setting up following variables:"
      echo "MSBASE_PATH  WINKIT  MSVSCBUILDTOOLS and MSVSC"
    else
      echo "warning, Cygwin on NOT x86_64 - $(uname -m) - the MSVSC tools are arch dependent. You unless you improve this script, you should set:"
      echo "MSBADONOT_DEPSSE_PATH  WINKIT  MSVSCBUILDTOOLS and *especially* the  MSVSC variables"
    fi
  else
    if [ "${DO_DEPS:-}" == "true" ] ; then
      sudo dnf install --skip-broken curl diffutils || echo "unzip/tar already there or windows?"    
      sudo dnf install --skip-broken unzip tar || echo "unzip/tar already there or windows?"
    fi
  fi
}

function setMainVariables() {
  PATH_BACKUP_MSVC="$PATH"
  FUTURE_PATH_ADDITIONS=$(mktemp -d)
  WORKDIR="$(pwd)"
  LOG="${WORKDIR}/log.txt"
  date > "$LOG"
}


# tag:os.arch
function getTag() {
  echo "${1%%:*}"
}

# tag:os.arch
function getOsArch() {
  echo "${1##*:}"
}

# tag:os.arch
function getOs() {
  osArch=$(getOsArch "${1}")
  local osArch="$osArch"
  echo "${osArch%%.*}"
}

# tag:os.arch
function getArch() {
  osArch=$(getOsArch "${1}")
  local osArch="$osArch"
  echo "${osArch##*.}"
}

function getDiff() {
  diff -u3 before  after  | grep -v after | grep "^+" | sed "s/^.//" || echo "always $?"  1>&2
  rm before after
}

function downloadAdoptiumReleases() {
  TAG_NON_URL=$(getTag "${1}")
  TAG=${TAG_NON_URL/+/%2B}
  ADOPTIUM_ARCH=$(getArch "${1}")
  OS=$(getOs "${1}")
  ADOPTIUM_JSON="adoptium.json"
  local TAG_NON_URL="${TAG_NON_URL}"
  local TAG="${TAG}"
  local ADOPTIUM_ARCH="${ADOPTIUM_ARCH}"
  local OS="${OS}"
  local ADOPTIUM_JSON="${ADOPTIUM_JSON}"
  curl -X 'GET' \
    "https://api.adoptium.net/v3/assets/release_name/eclipse/${TAG}?architecture=${ADOPTIUM_ARCH}&heap_size=normal&image_type=jdk&project=jdk&os=${OS}" \
    -H 'accept: application/json' > $ADOPTIUM_JSON
  if [ ! -s $ADOPTIUM_JSON ]; then
    set +x
	  echo "AQA api returned nothing! See avaialble versions below"
      getSurroundingReleases "${ADOPTIUM_ARCH}" "${OS}" '"release_name"' "${TAG_NON_URL}" "${TAG_NON_URL}"
	  echo "AQA api returned nothing! See avaialble versions above"
    set -x
    exit 1
  fi
  cat ${ADOPTIUM_JSON}
  LAST_ADOPTIUM_JSON=${ADOPTIUM_JSON}
  ls > before
  curl -OLJSks "https://api.adoptium.net/v3/binary/version/${TAG}/${OS}/${ADOPTIUM_ARCH}/jdk/hotspot/normal/eclipse?project=jdk"
  ls > after
  ORIG_LAST_DOWNLOADED_FILE=$(getDiff)
  local ORIG_LAST_DOWNLOADED_FILE="${ORIG_LAST_DOWNLOADED_FILE}"
  LAST_DOWNLOADED_FILE="ojdk$(date +%s)_${ORIG_LAST_DOWNLOADED_FILE}"
  mv "${ORIG_LAST_DOWNLOADED_FILE}" "${LAST_DOWNLOADED_FILE}"
  if [ ! -e "${LAST_DOWNLOADED_FILE}" ]; then
    set +x
	  echo "AQA api downloaded nothing! See avaialble versions below"
      getSurroundingReleases "${ADOPTIUM_ARCH}" "${OS}" '"link"' "${TAG_NON_URL}" "${TAG_NON_URL}"
	  echo "AQA api downloaded nothing! See avaialble versions above"
    set -x
    exit 1
  fi
}

function copyJdk () {
  local jdk_source="${1}"
  local jdk_name="${2}"
  echo "${jdk_source} is directory, will be copied AS ${jdk_name}"
  readlink -f "${jdk_source}"
  rm -rf "${jdk_name}"
  cp -rL "${jdk_source}" "${jdk_name}"
}

function unpackJdk() {
  local jdk_source="${1}"
  local jdk_name="${2}"
  echo "${jdk_source} is file, will be unpacked and moved *as* ${jdk_name}"
  readlink -f "${jdk_source}"
  ls > before
  if echo "${jdk_source}" | grep "\.zip" ; then
    unzip "${jdk_source}"
  else
    tar -xf "${jdk_source}"
  fi
  ls > after
  unpacked=$(getDiff)
  local unpacked=${unpacked}
  rm -rf "${jdk_name}"
  mv "${unpacked}" "${jdk_name}"
}

function prepareAlternateJavaHome() {
  local tag_os_arch="${1}"
  local existing_archive="${2}"
  futur_java_home="future_boot_jdk"
  if [ -e "${futur_java_home}" ] ; then
    rm -rf "${futur_java_home}"
  fi
  if [ -f "${existing_archive}" ] ; then
    echo "${tag_os_arch} is there as ${existing_archive}, will be reused"
    unpackJdk "${existing_archive}" "${futur_java_home}"
  else
    echo "${tag_os_arch} is tag:os.arch, will be downloaded and unpacked"
    downloadAdoptiumReleases "${tag_os_arch}"
    unpackJdk "${LAST_DOWNLOADED_FILE}" "${futur_java_home}"
  fi
  if uname | grep CYGWIN ; then
    chmod777 "${futur_java_home}"
  fi
  JAVA_HOME=$(readlink -f "${futur_java_home}");
  export JAVA_HOME="${JAVA_HOME}"
}

function tapsAndJunits() {
  local diffFileParam="${1}"
  local differencesFile="${2}"
  local totalFile="${3}"
  if [ ! "${DO_RESULTS:-}" == "false" ] ; then
    if [ -z "${RFAT:-}" ] ; then
      if [ ! -e run-folder-as-tests ] ; then
        git clone "https://github.com/rh-openjdk/run-folder-as-tests.git"
      fi
      RFAT="$(pwd)/run-folder-as-tests"
    fi
    # shellcheck disable=SC1091
    source "${RFAT}/jtreg-shell-xml.sh"
    # shellcheck disable=SC1091
    source "${RFAT}/tap-shell-tap.sh"
    resultsTapFile="${WORKDIR}/compare-comparable-builds.tap"
    unitFile="compare-comparable-builds.jtr.xml"
    unitFileArchive="$unitFile.tar.xz"
    set +x
    echo "writing $unitFileArchive"
    local total=4
    local passed=0
    local failed=0
    if [ $GLOABL_RESULT -eq 0 ] ; then
      passed=$(("${passed}"+1))
    else
       failed=$(("${failed}"+1))
    fi
    local totalDiffs
    # warning, this do not work without pipefail
    # shellcheck disable=SC2002
    totalDiffs=$(cat "${differencesFile}" | grep "Number of" | sed "s/[^0-9]\+//" || echo "999999999") # if there is no record we need to fail
    local totalFiles
    # shellcheck disable=SC2002
    totalFiles=$(cat "${totalFile}" | grep "Number of" | sed "s/[^0-9]\+//" || echo "0") # if there is no record we need to fail
    local totalOnlyIn
    # shellcheck disable=SC2002
    totalOnlyIn=$(cat "${differencesFile}" | grep "Only in:" | sed "s/[^0-9]\+//" || echo "0") #if there is non, we eant to pass
    if [ "${totalDiffs}" -eq 0 ] ; then
      passed=$(("${passed}"+1))
    else
      failed=$(("${failed}"+1))
    fi
    if [ "${totalFiles}" -ne 0 ] ; then
      passed=$(("${passed}"+1))
    else
      failed=$(("${failed}"+1))
    fi
    if [ "${totalOnlyIn}" -eq 0 ] ; then
      passed=$(("${passed}"+1))
    else
      failed=$(("${failed}"+1))
    fi
    total=$(("${passed}"+"${failed}"))
    printXmlHeader "${passed}" "${failed}" "${total}" 0 "compare-comparable-builds" > "${unitFile}"
    tapHeader "${total}"  "$(date)" > "${resultsTapFile}"
    if [ "${totalDiffs}" -eq 0 ] ; then
      printXmlTest "compare" "differences-count" "1" "" "../artifact/$(basename "${differencesFile}")" >> "${unitFile}"
      tapTestStart "ok" "1" "differences-count" >> "${resultsTapFile}"
      echo "-- no differences --"
    else
      printXmlTest "compare" "differences-count" "1" "${differencesFile}" "../artifact/$(basename "${differencesFile}")" >> "${unitFile}"
      tapTestStart "not ok" "1" "differences-count" >> "${resultsTapFile}"
      echo "-- differences count: $totalDiffs --"
    fi
    set +e
      tapFromWholeFile "${differencesFile}" "${differencesFile}" >> "${resultsTapFile}"
      tapTestEnd >> "${resultsTapFile}"
    set -e
    if [ "${totalFiles}" -ne 0 ] ; then
      printXmlTest "compare" "compared-files-count" "2" "" "../artifact/$(basename "${totalFile}")" >> "${unitFile}"
      tapTestStart "ok" "2" "compared-files-count" >> "${resultsTapFile}"
      echo "-- files compared: $totalFiles --"
    else
      printXmlTest "compare" "compared-files-count" "2" "${totalFile}" "../artifact/$(basename "${totalFile}")" >> "${unitFile}"
      tapTestStart "not ok" "2" "compared-files-count" >> "${resultsTapFile}"
      echo "-- no files compared --"
    fi
    set +e
      tapFromWholeFile "${totalFile}" "${totalFile}" >> "${resultsTapFile}"
      tapTestEnd >> "${resultsTapFile}"
    set -e
    if [ "${totalOnlyIn}" -eq 0 ] ; then
      printXmlTest "compare" "onlyin-count" "3" "" "../artifact/$(basename "${differencesFile}")" >> "${unitFile}"
      tapTestStart "ok" "3" "onlyin-count" >> "${resultsTapFile}"
      echo "-- no onlyin files --"
    else
      printXmlTest "compare" "onlyin-count" "3" "${differencesFile}" "../artifact/$(basename "${differencesFile}")" >> "${unitFile}"
      tapTestStart "not ok" "3" "onlyin-count" >> "${resultsTapFile}"
      echo "-- onlyin files count: $totalOnlyIn --"
    fi
    set +e
      tapFromWholeFile "${differencesFile}" "${differencesFile}" >> "${resultsTapFile}"
      tapTestEnd >> "${resultsTapFile}"
    set -e
    if [ $GLOABL_RESULT -eq 0 ] ; then
      printXmlTest "compare" "comparable-builds" "4" "" "../artifact/$(basename "${diffFileParam}")" >> "${unitFile}"
      tapTestStart "ok" "4" "comparable-builds" >> "${resultsTapFile}"
      echo "-- COMPARABLE --"
    else
      printXmlTest "compare" "comparable-builds" "4" "${diffFileParam}" "../artifact/$(basename "${diffFileParam}")" >> "${unitFile}"
      tapTestStart "not ok" "4" "comparable-builds" >> "${resultsTapFile}"
      echo "-- MISMATCH --"
    fi
    set +e
      # shellcheck disable=SC2002
      cat "${diffFileParam}" | sed "s|${WORKDIR}||g" > diffFileCopy || true
      tapFromWholeFile "diffFileCopy" "reprotest.diff" >> "${resultsTapFile}"
      tapTestEnd >> "${resultsTapFile}"
    set -e
    printXmlFooter >> "${unitFile}"
    set -x
    tar -cJf "${WORKDIR}/${unitFileArchive}"  "${unitFile}"
  else
    ls "${diffFileParam}"
    cat "${diffFileParam}"
  fi
}

###################### run ######################

processArgs "$@"
setMainVariables
deps

declare -A JDK_INFO
  JDK_INFO["first_source"]="${JDK1_STRING}"
  JDK_INFO["second_source"]="${JDK2_STRING}"
  JDK_INFO["first_id"]=$(basename "$(readlink -f "${JDK1_STRING}")")
  JDK_INFO["second_id"]=$(basename "$(readlink -f "${JDK2_STRING}")")
  JDK_INFO["first_tagonly"]="$(getTag "${JDK_INFO["first_id"]}")"
  JDK_INFO["second_tagonly"]="$(getTag "${JDK_INFO["second_id"]}")"
  # java do not work if there is colon in its dir!
  JDK_INFO["first_name"]=$(echo "${JDK_INFO["first_id"]}-ours" | sed "s/:/_/")
  JDK_INFO["second_name"]=$(echo "${JDK_INFO["second_id"]}-theirs" | sed "s/:/_/")
  JDK_INFO["first_json"]="adoptium1.json"
  JDK_INFO["second_json"]="adoptium2.json"

for id in "first" "second" ; do
  JDK_ID="${JDK_INFO["${id}_id"]}"  
  JDK_SOURCE="${JDK_INFO["${id}_source"]}"
  JDK_NAME="${JDK_INFO["${id}_name"]}"
  JDK_JSON="${JDK_INFO["${id}_json"]}"

  echo "Processing $id: ${JDK_SOURCE} (${JDK_ID})"
  if [ -d "${JDK_SOURCE}" ] ; then
    copyJdk "${JDK_SOURCE}" "${JDK_NAME}"
  elif [ -f "${JDK_SOURCE}" ] ; then
    unpackJdk "${JDK_SOURCE}" "${JDK_NAME}"
  else
    echo "${JDK_SOURCE} is tag:os.arch, will be downloaded and unpacked"
    downloadAdoptiumReleases "${JDK_ID}"
    mv "${LAST_ADOPTIUM_JSON}" "${JDK_JSON}"
    unpackJdk "${LAST_DOWNLOADED_FILE}" "${JDK_NAME}"
  fi
  ls -l "$(pwd)"

  if [ -z "${JAVA_HOME:-}" ] && [ "${id}" = "first" ] ; then
    prepareAlternateJavaHome "${JDK_ID}" "${LAST_DOWNLOADED_FILE}"
  fi
done

if uname | grep CYGWIN ; then
  initWindowsTools
  setMsvscToPath
  compileAndSetToFuturePath
fi

# comapre build can not run if not run from its pwd
pushd "${COMPARE_WAPPER_SCRIPT_DIR}/reproducible/"
  for jdkName in ${JDK_INFO["first_name"]} ${JDK_INFO["second_name"]} ; do
    # better to try them asap
    "${WORKDIR}/${jdkName}/bin/java" --version 
    "${WORKDIR}/${jdkName}/bin/javac" --version
    ftureDir="$(mktemp -d)/classes"
    if uname | grep CYGWIN ; then
      ftureDir=$(cygpath -m "${ftureDir}")
    fi
    # the java in java_home will be used later, try it
    "$JAVA_HOME/bin/java" --version
    "$JAVA_HOME/bin/javac" -d "${ftureDir}" "../../tooling/src/java/temurin/tools/BinRepl.java"
    CLASSPATH="${ftureDir}"
    export CLASSPATH
    if uname | grep CYGWIN ; then
      CLASSPATH=$(cygpath -m "${CLASSPATH}")
      export CLASSPATH="${CLASSPATH}"
    fi
    getKeysForComparablePatch "${WORKDIR}/${jdkName}"
    # we cannot use the JDK we are currently processing. It is broken by the patching
    PATH="${JAVA_HOME}/bin:${PATH}" bash ./comparable_patch.sh --jdk-dir "${WORKDIR}/${jdkName}" --version-string "$JAVA_VENDOR_VERSION" --vendor-name "$JAVA_VENDOR" --vendor_url "$JAVA_VENDOR_URL" --vendor-bug-url "$JAVA_VENDOR_URL_BUG" --vendor-vm-bug-url "$JAVA_VENDOR_URL_BUG"  2>&1 | tee -a "$LOG"
  done
  if [ "${DO_BREAK:-}" == "true" ] ; then
    echo "dead" > "${WORKDIR}/${JDK_INFO["first_name"]}/bin/java"
    echo "dead" > "${WORKDIR}/${JDK_INFO["first_name"]}/lib/server/libjvm.so"
  fi
  GLOABL_RESULT=0
  bash ./repro_compare.sh openjdk "${WORKDIR}/${JDK_INFO["first_name"]}" openjdk "${WORKDIR}/${JDK_INFO["second_name"]}" 2>&1 | tee -a "${LOG}" || GLOABL_RESULT=$?
  diflog="${WORKDIR}/differences.log"
  totlog="${WORKDIR}/totalfiles.log"
  # shellcheck disable=SC2002
  cat "${LOG}" | grep "Number of differences" -A 1 > "${diflog}"
  echo "Warning, the files which are only in one of the JDKs may be missing in this summary:" >> "${diflog}"
  set +e
  # shellcheck disable=SC2002
  cat "${LOG}" | grep "Only in" | sed "s|${WORKDIR}||g">> "${diflog}"
  echo -n "Only in: " >> "${diflog}"
  # shellcheck disable=SC2002
  cat "${LOG}" | grep "Only in " | wc -l  >> "${diflog}"
  # shellcheck disable=SC2002
  cat "${LOG}" | grep "Number of files" > "${totlog}"
  set -e
popd

diffFile="${COMPARE_WAPPER_SCRIPT_DIR}/reproducible/reprotest.diff"
tapsAndJunits "${diffFile}" "${diflog}" "${totlog}"
cp "${diffFile}" "${WORKDIR}"
pwd
ls -l "$(pwd)"

if [ ! "${DO_RESULTS:-}" == "false" ] ; then
  # the result will be changed via tap plugin or jtreg plugin
  exit 0
else
  exit ${GLOABL_RESULT}
fi
