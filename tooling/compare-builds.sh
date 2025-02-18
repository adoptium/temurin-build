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
# useful variables: DO_BREAK         if true, one of the jdks will be crippled on purpose
#                   DO_TAPS DO_JUNIT if true, one/both tap/jtreg results will be generated
#                   RFAT             if you generate tap/jtreg results, library is downloaded.
#                                    RFAT may contain path to already cloned library
#                   DO_DEPS          will dnf install crucial dependencies
#                   JAVA_HOME        points to third JDK used to run java binaries. If not set
#                                    one of the JDKs is copied again and used
#######################################################################################################################

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
      echo "It is useful to have JAVA_HOME pointing to some other JDK used to compile and run supporting files"
      echo "otherwise one of the provided JDKs will be duplicated, and used"
      echo "There are two types of compare - IDENTICAL and COMPARABLE. if COMP_TYPE is not set, ID is used."
      echo "  Use COMP_TYPE=ID or COMP_TYPE=COMP to determine between them"
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
      echo "JAVA_HOME is set to ${JAVA_HOME} and will be used as independent jdk"
    else
      if [ -d "${1}"  ] ; then
         export JAVA_HOME="${1}"
         echo "JAVA_HOME was set to ${JAVA_HOME} and will be used as independent jdk"
      elif [ -d "${2}"  ] ; then
         export JAVA_HOME="${2}"
         echo "JAVA_HOME was set to ${JAVA_HOME} and will be used as independent jdk"
      else
        if [ -f "${1}"  ] ; then
          echo "${1} will be unpacked second times and used as JAVA_HOME."
        else
          echo "once ${1} is downloaded, will be unpacked second times and used as JAVA_HOME"
        fi
         echo "We recommend to to set JAVA_HOME for next time."
      fi
    fi
  if [ -z "${COMP_TYPE:-}" ] ; then
    COMP_TYPE="ID"
  fi
  echo "COMP_TYPE is $COMP_TYPE"
  if [ "${COMP_TYPE}" = "ID" ] ; then
    echo "  jdks are compared as IDENTICAL"
  elif [ "${COMP_TYPE}" = "COMP" ] ; then
    echo "  jdks are compared as COMPARABLE"
  else
    echo "  unknown value. ID or COMP is accepted only. Exiting"
    exit 1
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
    " > setupEnvAndCompile.bat
    chmod 755 setupEnvAndCompile.bat
    ./setupEnvAndCompile.bat
    # copy it to any dir on path or add this dir to path
    mv WindowsUpdateVsVersionInfo.exe "$FUTURE_PATH_ADDITIONS"
    rm WindowsUpdateVsVersionInfo.obj setupEnvAndCompile.bat
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
      echo "warning, Cygwin on NOT x86_64 - $(uname -m) - the MSVSC tools are arch dependent. Unless you improve this script, you should set:"
      echo "MSBASE_PATH  WINKIT  MSVSCBUILDTOOLS and *especially* the  MSVSC variables"
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
	  echo "AQA api returned nothing! See available versions below"
      getSurroundingReleases "${ADOPTIUM_ARCH}" "${OS}" '"release_name"' "${TAG_NON_URL}" "${TAG_NON_URL}"
	  echo "AQA api returned nothing! See available versions above"
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
	  echo "AQA api downloaded nothing! See available versions below"
      getSurroundingReleases "${ADOPTIUM_ARCH}" "${OS}" '"link"' "${TAG_NON_URL}" "${TAG_NON_URL}"
	  echo "AQA api downloaded nothing! See available versions above"
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
  if [ "${COMP_TYPE}" = "COMP" ] ; then
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
  fi
  if [ "${DO_BREAK:-}" == "true" ] ; then
    echo "dead" > "${WORKDIR}/${JDK_INFO["first_name"]}/bin/java"
    echo "dead" > "${WORKDIR}/${JDK_INFO["first_name"]}/lib/server/libjvm.so"
  fi
  GLOBAL_RESULT=0
  if [ "${COMP_TYPE}" = "COMP" ] ; then
    # this tells repro_compare to skipp all the preprocessing. If not set, the repro_compare.sh on top of comparable_patch.sh  brings false negatives
    export PREPROCESS="no"
  fi
  bash ./repro_compare.sh openjdk "${WORKDIR}/${JDK_INFO["first_name"]}" openjdk "${WORKDIR}/${JDK_INFO["second_name"]}" 2>&1 | tee -a "${LOG}" || GLOBAL_RESULT=$?
  diflog="${WORKDIR}/differences.log"
  totlog="${WORKDIR}/totalfiles.log"
  set +e
    {
      grep "Number of differences" -A 1 "${LOG}"
      echo "Warning, the files which are only in one of the JDKs may be missing in this summary:"
      grep "Only in" "${LOG}" | sed "s|${WORKDIR}||g"
      echo -n "Only in: "
      ## shellcheck disable=SC2126
      grep -c "Only in " "${LOG}"
    } > "${diflog}"
    grep "Number of files" "${LOG}" > "${totlog}"
  set -e
popd

diffFile="${COMPARE_WAPPER_SCRIPT_DIR}/reproducible/reprotest.diff"
if [ "${DO_TAPS:-}" == "true" ] || [ "${DO_JUNIT:-}" == "true" ] ; then
  source ${COMPARE_WAPPER_SCRIPT_DIR}/compare-builds-postfunctions.sh
  tapsAndJunits "${diffFile}" "${diflog}" "${totlog}"
else
  ls "${diffFileParam}"
  cat "${diffFileParam}"
fi
cp "${diffFile}" "${WORKDIR}"
pwd
ls -l "$(pwd)"

if [ "${DO_TAPS:-}" == "true" ] || [ "${DO_JUNIT:-}" == "true" ] ; then
  # the result will be changed via tap plugin or jtreg plugin
  exit 0
else
  exit ${GLOBAL_RESULT}
fi
