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

# This script examines the given SBOM metadata file, and then builds the exact same binary
# and then compares with the supplied TARBALL_PARAM.

set -e

[ $# -lt 1 ] && echo "Usage: $0 SBOM_PARAM JDK_PARAM" && exit 1
SBOM_PARAM=$1
JDK_PARAM=$2
ANT_VERSION=1.10.5
ANT_SHA=9028e2fc64491cca0f991acc09b06ee7fe644afe41d1d6caf72702ca25c4613c
ANT_CONTRIB_VERSION=1.0b3
ANT_CONTRIB_SHA=4d93e07ae6479049bb28071b069b7107322adaee5b70016674a0bffd4aac47f9
isJdkDir=false

installPrereqs() {
  if test -r /etc/redhat-release; then
    yum install -y gcc gcc-c++ make autoconf unzip zip alsa-lib-devel cups-devel libXtst-devel libXt-devel libXrender-devel libXrandr-devel libXi-devel
    yum install -y file fontconfig fontconfig-devel systemtap-sdt-devel epel-release strace # Not included above ...
    yum install -y git bzip2 xz openssl pigz which jq # pigz/which not strictly needed but help in final compression
    if grep -i release.6 /etc/redhat-release; then
      if [ ! -r /usr/local/bin/autoconf ]; then
        curl --output ./autoconf-2.69.tar.gz https://ftp.gnu.org/gnu/autoconf/autoconf-2.69.tar.gz
        ACSHA256=954bd69b391edc12d6a4a51a2dd1476543da5c6bbf05a95b59dc0dd6fd4c2969
        ACCHKSHA=$(sha256sum ./autoconf-2.69.tar.gz|cut -d" " -f1)
        if [ "$ACSHA256" = "$ACCHKSHA" ]; then
          echo "Hi"
          tar xpfz ./autoconf-2.69.tar.gz || exit 1
          (cd autoconf-2.69 && ./configure --prefix=/usr/local && make install)
        else
          echo "ERROR - Checksum For AutoConf Download Is Incorrect"
          exit 1;
        fi
      fi
    fi
  fi
}

# ant required for --create-sbom
downloadAnt() {
  if [ ! -r "/usr/local/apache-ant-${ANT_VERSION}/bin/ant" ]; then
    echo "Downloading ant for SBOM creation..."
    curl -o "/tmp/apache-ant-${ANT_VERSION}-bin.zip" "https://archive.apache.org/dist/ant/binaries/apache-ant-${ANT_VERSION}-bin.zip"
    ANTCHKSHA=$(sha256sum "/tmp/apache-ant-${ANT_VERSION}-bin.zip" | cut -d" " -f1)
    if [ "$ANT_SHA" = "$ANTCHKSHA" ]; then
      (cd /usr/local && unzip -qn "/tmp/apache-ant-${ANT_VERSION}-bin.zip")
      rm "/tmp/apache-ant-${ANT_VERSION}-bin.zip"
    else
      echo "ERROR - Checksum for Ant download is incorrect"
      exit 1
    fi
    echo "Downloading ant-contrib-${ANT_CONTRIB_VERSION}..."
    curl -Lo "/tmp/ant-contrib-${ANT_CONTRIB_VERSION}-bin.zip" "https://sourceforge.net/projects/ant-contrib/files/ant-contrib/${ANT_CONTRIB_VERSION}/ant-contrib-${ANT_CONTRIB_VERSION}-bin.zip"
    ANTCTRCHKSHA=$(sha256sum "/tmp/ant-contrib-${ANT_CONTRIB_VERSION}-bin.zip" | cut -d" " -f1)
    if [ "$ANT_CONTRIB_SHA" = "$ANTCTRCHKSHA" ]; then
      (unzip -qnj "/tmp/ant-contrib-${ANT_CONTRIB_VERSION}-bin.zip" "ant-contrib/ant-contrib-${ANT_CONTRIB_VERSION}.jar" -d "/usr/local/apache-ant-${ANT_VERSION}/lib")
      rm "/tmp/ant-contrib-${ANT_CONTRIB_VERSION}-bin.zip"
    else
      echo "ERROR - Checksum for Ant Contrib download is incorrect"
      exit 1
    fi
  fi
}

setEnvironment() {
  export CC="${LOCALGCCDIR}/bin/gcc-${GCCVERSION}"
  export CXX="${LOCALGCCDIR}/bin/g++-${GCCVERSION}"
  export LD_LIBRARY_PATH="${LOCALGCCDIR}/lib64"
  # /usr/local/bin required to pick up the new autoconf if required
  export PATH="${LOCALGCCDIR}/bin:/usr/local/bin:/usr/bin:$PATH:/usr/local/apache-ant-${ANT_VERSION}/bin"
  ls -ld "$CC" "$CXX" "/usr/lib/jvm/jdk-${BOOTJDK_VERSION}/bin/javac" || exit 1
}

# Function to check if a value is in the array
containsElement () {
  # shellcheck disable=SC3043
  local e
  # shellcheck disable=SC3057
  for e in "${@:2}"; do
    if [ "$e" = "$1" ]; then
      return 0  # Match found
    fi
  done
  return 1  # No match found
}

setBuildArgs() {
  # shellcheck disable=SC3043,SC3030
  local CONFIG_ARGS=("--disable-warnings-as-errors" "--enable-dtrace" "--without-version-pre" "--without-version-opt" "--with-version-opt")
  # shellcheck disable=SC3043,SC3030
  local NOTUSE_ARGS=("--configure-args")
  export BOOTJDK_HOME="/usr/lib/jvm/jdk-${BOOTJDK_VERSION}"
  echo "Parsing Make JDK Any Platform ARGS For Build"
  # Split the string into an array of words
  IFS=' ' read -ra words <<< "$TEMURIN_BUILD_ARGS"

  # Add The Build Time Stamp In Case It Wasnt In The SBOM ARGS
  words+=("--build-reproducible-date")
  # shellcheck disable=SC3024
  words+=("\"$BUILDSTAMP\"")

  # Initialize variables
  param=""
  value=""
  params=()

  # Loop through the words
  for word in "${words[@]}"; do
    # Check if the word starts with '--'
    if [[ $word == --* ]] || [[ $word == -b* ]]; then
      # If a parameter already exists, store it in the params array
      if [[ -n $param ]]; then
        params+=("$param=$value")
      fi
      # Reset variables for the new parameter
      param="$word"
      value=""
    else
      value+="$word "
    fi
  done
  
    # Add the last parameter to the array
  params+=("$param=$value")

  # Read the separated parameters and values into a new array
  export fixed_param=""
  export fixed_value=""
  export fixed_params=()
  export new_params=""
  CONFIG_ARRAY=()
  BUILD_ARRAY=()
  IGNORED_ARRAY=()

  for p in "${params[@]}"; do
    IFS='=' read -ra parts <<< "$p"
    prefixed_param=${parts[0]}
    fixed_param="${prefixed_param%%[[:space:]]}"
    prepped_value=${parts[1]}
    fixed_value=$(echo "$prepped_value" | awk '{$1=$1};1')
    # Handle Special parameters
    if [ "$fixed_param" = "--jdk-boot-dir" ]; then fixed_value="$BOOTJDK_HOME" ; fi
    
    # Fix Build Variant Parameter To Strip JDK Version
    if [ "$fixed_param" = "--build-variant" ] ; then
      # Remove Leading White Space
      trimmed_value=$(echo "$prepped_value" | awk '{$1=$1};1')
      IFS=' ' read -r variant jdk <<< "$trimmed_value"
      if [[ $jdk == jdk* ]]; then
        variant="$variant "
      else
        temp="$variant "
        variant="$jdk"
        jdk="$temp"
      fi
      fixed_value=$variant
    fi

    # Check if fixed_param is in CONFIG_ARGS
    if containsElement "$fixed_param" "${CONFIG_ARGS[@]}"; then
      # Add Config Arg To New Array
      if [ "$fixed_param" == "--with-version-opt" ] ; then
        STRINGTOADD="$fixed_param=$fixed_value"
        CONFIG_ARRAY+=("$STRINGTOADD")
      else
        STRINGTOADD="$fixed_param"
        CONFIG_ARRAY+=("$STRINGTOADD")
      fi
    elif containsElement "$fixed_param" "${NOTUSE_ARGS[@]}"; then
      # Strip Parameters To Be Ignored
      STRINGTOADD="$fixed_param $fixed_value"
      IGNORED_ARRAY+=("$STRINGTOADD")
    else
      # Not A Config Param Nor Should Be Ignored, So Add To Build Array
      STRINGTOADD="$fixed_param $fixed_value"
      BUILD_ARRAY+=("$STRINGTOADD")
    fi
  done

  IFS=' ' build_string="${BUILD_ARRAY[*]}"
  IFS=' ' config_string=$"${CONFIG_ARRAY[*]}"
  final_params="$build_string --configure-args \"$config_string\" $jdk"

  echo "Make JDK Any Platform Argument List = "
  echo "$final_params"
}

cleanBuildInfo() {
  # shellcheck disable=SC3043
  local DIR="$1"
  # BUILD_INFO name of OS level build was built on will likely differ
  sed -i '/^BUILD_INFO=.*$/d' "${DIR}/release"
}

downloadTooling() {
  if [ ! -r "/usr/lib/jvm/jdk-${BOOTJDK_VERSION}/bin/javac" ]; then
    echo "Retrieving boot JDK $BOOTJDK_VERSION" && mkdir -p /usr/lib/jvm && curl -L "https://api.adoptium.net/v3/binary/version/jdk-${BOOTJDK_VERSION}/linux/${NATIVE_API_ARCH}/jdk/hotspot/normal/eclipse?project=jdk" | (cd /usr/lib/jvm && tar xpzf -)
  fi
  if [ ! -r "${LOCALGCCDIR}/bin/g++-${GCCVERSION}" ]; then
    echo "Retrieving gcc $GCCVERSION" && curl "https://ci.adoptium.net/userContent/gcc/gcc$(echo "$GCCVERSION" | tr -d .).$(uname -m).tar.xz" | (cd /usr/local && tar xJpf -) || exit 1
  fi
  if [ ! -r temurin-build ]; then
    git clone https://github.com/adoptium/temurin-build || exit 1
  fi
  (cd temurin-build && git checkout "$TEMURIN_BUILD_SHA")
}

checkAllVariablesSet() {
  if [ -z "$SBOM" ] || [ -z "${BOOTJDK_VERSION}" ] || [ -z "${TEMURIN_BUILD_SHA}" ] || [ -z "${TEMURIN_BUILD_ARGS}" ] || [ -z "${TEMURIN_VERSION}" ]; then
      echo "Could not determine one of the variables - run with sh -x to diagnose" && sleep 10 && exit 1
  fi
}

installPrereqs
downloadAnt

# shellcheck disable=SC3010
if [[ $SBOM_PARAM =~ ^https?:// ]]; then
  echo "Retrieving and parsing SBOM from $SBOM_PARAM"
  curl -LO "$SBOM_PARAM"
  SBOM=$(basename "$SBOM_PARAM")
else
  SBOM=$SBOM_PARAM
fi

BOOTJDK_VERSION=$(jq -r '.metadata.tools[] | select(.name == "BOOTJDK") | .version' "$SBOM" | sed -e 's#-LTS$##')
GCCVERSION=$(jq -r '.metadata.tools[] | select(.name == "GCC") | .version' "$SBOM" | sed 's/.0$//')
LOCALGCCDIR=/usr/local/gcc$(echo "$GCCVERSION" | cut -d. -f1)
TEMURIN_BUILD_SHA=$(jq -r '.components[0] | .properties[] | select (.name == "Temurin Build Ref") | .value' "$SBOM" | awk -F/ '{print $NF}')
TEMURIN_BUILD_ARGS=$(jq -r '.components[0] | .properties[] | select (.name == "makejdk_any_platform_args") | .value' "$SBOM")
TEMURIN_VERSION=$(jq -r '.metadata.component.version' "$SBOM" | sed 's/-beta//' | cut -f1 -d"-")
BUILDSTAMP=$(jq -r '.components[0].properties[] | select(.name == "Build Timestamp") | .value' "$SBOM")
NATIVE_API_ARCH=$(uname -m)
if [ "${NATIVE_API_ARCH}" = "x86_64" ]; then NATIVE_API_ARCH=x64; fi
if [ "${NATIVE_API_ARCH}" = "armv7l" ]; then NATIVE_API_ARCH=arm; fi

checkAllVariablesSet
downloadTooling
setEnvironment
setBuildArgs

if [ -z "$JDK_PARAM" ] && [ ! -d "jdk-${TEMURIN_VERSION}" ] ; then
    JDK_PARAM="https://api.adoptium.net/v3/binary/version/jdk-${TEMURIN_VERSION}/linux/${NATIVE_API_ARCH}/jdk/hotspot/normal/eclipse?project=jdk"
fi

# shellcheck disable=SC3010
if [[ $JDK_PARAM =~ ^https?:// ]]; then
  echo Retrieving original tarball from adoptium.net && curl -L "$JDK_PARAM" | tar xpfz - && ls -lart "$PWD/jdk-${TEMURIN_VERSION}" || exit 1
elif [[ $JDK_PARAM =~ tar.gz ]]; then
  mkdir "$PWD/jdk-${TEMURIN_VERSION}"
  tar xpfz "$JDK_PARAM" --strip-components=1 -C "$PWD/jdk-${TEMURIN_VERSION}"
else
  echo "Local jdk dir"
  isJdkDir=true
fi

comparedDir="jdk-${TEMURIN_VERSION}"
if [ "${isJdkDir}" = true ]; then
  comparedDir=$JDK_PARAM
fi

echo " cd temurin-build && ./makejdk-any-platform.sh $final_params 2>&1 | tee build.$$.log" | sh

echo Comparing ...
mkdir compare.$$
tar xpfz temurin-build/workspace/target/OpenJDK*-jdk_*tar.gz -C compare.$$
cp temurin-build/workspace/target/OpenJDK*-jdk_*tar.gz reproJDK.tar.gz
cp "$SBOM" SBOM.json

cleanBuildInfo "${comparedDir}"
cleanBuildInfo "compare.$$/jdk-$TEMURIN_VERSION"
rc=0
# shellcheck disable=SC2069
diff -r "${comparedDir}" "compare.$$/jdk-$TEMURIN_VERSION" 2>&1 > "reprotest.diff" || rc=$?

if [ $rc -eq 0 ]; then
  echo "Compare identical !"
else
  cat "reprotest.diff"
  echo "Differences found..., logged in: reprotest.diff"
fi

exit $rc
