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
USING_DEVKIT="false"
ScriptPath=$(dirname "$(realpath "$0")")

installPrereqs() {
  if test -r /etc/redhat-release; then
    # Replace mirrorlist to vault as centos7 reached EOL.
    sed -i -e 's!mirrorlist!#mirrorlist!g' /etc/yum.repos.d/CentOS-Base.repo
    sed -i 's|#baseurl=http://mirror.centos.org/|baseurl=http://vault.centos.org/|' /etc/yum.repos.d/CentOS-Base.repo
    yum install -y gcc gcc-c++ make autoconf unzip zip alsa-lib-devel cups-devel libXtst-devel libXt-devel libXrender-devel libXrandr-devel libXi-devel
    yum install -y file fontconfig fontconfig-devel systemtap-sdt-devel epel-release # Not included above ...
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

setNonDevkitGccEnvironment() {
  export CC="${LOCALGCCDIR}/bin/gcc-${GCCVERSION}"
  export CXX="${LOCALGCCDIR}/bin/g++-${GCCVERSION}"
  export LD_LIBRARY_PATH="${LOCALGCCDIR}/lib64"
}

setAntEnvironment() {
  export PATH="${LOCALGCCDIR}/bin:/usr/local/bin:/usr/bin:$PATH:/usr/local/apache-ant-${ANT_VERSION}/bin"
}

setTemurinBuildArgs() {
  local buildArgs="$1"
  local bootJdk="$2"
  local timeStamp="$3"
  local ignoreOptions=("--enable-sbom-strace ")
  for ignoreOption in "${ignoreOptions[@]}"; do
    buildArgs="${buildArgs/${ignoreOption}/}"
  done
  # set --build-reproducible-date if not yet
  if [[ "${buildArgs}" != *"--build-reproducible-date"* ]]; then
    buildArgs="--build-reproducible-date \"${timeStamp}\" ${buildArgs}" 
  fi
  #reset --jdk-boot-dir
  # shellcheck disable=SC2001
  buildArgs="$(echo "$buildArgs" | sed -e "s|--jdk-boot-dir [^ ]*|--jdk-boot-dir /usr/lib/jvm/jdk-${bootJdk}|")"
  echo "${buildArgs}"
}

downloadTooling() {
  local using_DEVKIT=$1

  if [ ! -r "/usr/lib/jvm/jdk-${BOOTJDK_VERSION}/bin/javac" ]; then
    echo "Retrieving boot JDK $BOOTJDK_VERSION" && mkdir -p /usr/lib/jvm && curl -L "https://api.adoptium.net/v3/binary/version/jdk-${BOOTJDK_VERSION}/linux/${NATIVE_API_ARCH}/jdk/hotspot/normal/eclipse?project=jdk" | (cd /usr/lib/jvm && tar xpzf -)
  fi
  if [[ "${using_DEVKIT}" == "false" ]]; then
    if [ ! -r "${LOCALGCCDIR}/bin/g++-${GCCVERSION}" ]; then
      echo "Retrieving gcc $GCCVERSION" && curl "https://ci.adoptium.net/userContent/gcc/gcc$(echo "$GCCVERSION" | tr -d .).$(uname -m).tar.xz" | (cd /usr/local && tar xJpf -) || exit 1
    fi
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

if [[ $SBOM_PARAM =~ ^https?:// ]]; then
  echo "Retrieving and parsing SBOM from $SBOM_PARAM"
  curl -LO "$SBOM_PARAM"
  SBOM=$(basename "$SBOM_PARAM")
else
  SBOM=$SBOM_PARAM
fi

BOOTJDK_VERSION=$(jq -r '.metadata.tools.components[] | select(.name == "BOOTJDK") | .version' "$SBOM" | sed -e 's#-LTS$##')
GCCVERSION=$(jq -r '.metadata.tools.components[] | select(.name == "GCC") | .version' "$SBOM" | sed 's/.0$//')
LOCALGCCDIR=/usr/local/gcc$(echo "$GCCVERSION" | cut -d. -f1)
TEMURIN_BUILD_SHA=$(jq -r '.components[0] | .properties[] | select (.name == "Temurin Build Ref") | .value' "$SBOM" | awk -F/ '{print $NF}')
TEMURIN_VERSION=$(jq -r '.metadata.component.version' "$SBOM" | sed 's/-beta//' | cut -f1 -d"-")
BUILDSTAMP=$(jq -r '.components[0].properties[] | select(.name == "Build Timestamp") | .value' "$SBOM")
TEMURIN_BUILD_ARGS=$(jq -r '.components[0] | .properties[] | select (.name == "makejdk_any_platform_args") | .value' "$SBOM")

# Using old method to escape configure-args in SBOM (build PR 3835)", can be removed later.
if echo "$TEMURIN_BUILD_ARGS" | grep -v configure-args\ \\\"; then
  TEMURIN_BUILD_ARGS=$(echo "$TEMURIN_BUILD_ARGS" | \
        cut -d\" -f4 | \
        sed -e "s/--with-jobs=[0-9]*//g" \
         -e "s/--disable-warnings-as-errors --enable-dtrace --without-version-pre --without-version-opt/'--disable-warnings-as-errors --enable-dtrace --without-version-pre --without-version-opt'/" \
         -e "s/--disable-warnings-as-errors --enable-dtrace *--with-version-opt=ea/'--disable-warnings-as-errors --enable-dtrace --with-version-opt=ea'/" \
         -e "s/ --disable-warnings-as-errors --enable-dtrace/ '--disable-warnings-as-errors --enable-dtrace'/" \
         -e 's/\\n//g')
fi

NATIVE_API_ARCH=$(uname -m)
if [ "${NATIVE_API_ARCH}" = "x86_64" ]; then NATIVE_API_ARCH=x64; fi
if [ "${NATIVE_API_ARCH}" = "armv7l" ]; then NATIVE_API_ARCH=arm; fi
if [[ "$TEMURIN_BUILD_ARGS" =~ .*"--use-adoptium-devkit".* ]]; then
  USING_DEVKIT="true"
fi

checkAllVariablesSet
downloadTooling "$USING_DEVKIT"
if [[ "${USING_DEVKIT}" == "false" ]]; then
  setNonDevkitGccEnvironment
fi
setAntEnvironment
echo "original temurin build args is ${TEMURIN_BUILD_ARGS}"
TEMURIN_BUILD_ARGS=$(setTemurinBuildArgs "$TEMURIN_BUILD_ARGS" "$BOOTJDK_VERSION" "$BUILDSTAMP")

if [ -z "$JDK_PARAM" ] && [ ! -d "jdk-${TEMURIN_VERSION}" ] ; then
    JDK_PARAM="https://api.adoptium.net/v3/binary/version/jdk-${TEMURIN_VERSION}/linux/${NATIVE_API_ARCH}/jdk/hotspot/normal/eclipse?project=jdk"
fi

sourceJDK="jdk-${TEMURIN_VERSION}"
mkdir "${sourceJDK}"
if [[ $JDK_PARAM =~ ^https?:// ]]; then
  echo Retrieving original tarball from adoptium.net && curl -L "$JDK_PARAM" | tar xpfz - && ls -lart "$PWD/jdk-${TEMURIN_VERSION}" || exit 1
elif [[ $JDK_PARAM =~ tar.gz ]]; then
  tar xpfz "$JDK_PARAM" --strip-components=1 -C "$PWD/jdk-${TEMURIN_VERSION}"
else
  # Local jdk dir
  cp -R "${JDK_PARAM}"/* "${sourceJDK}"
fi

echo "Rebuild args for makejdk_any_platform.sh are: $TEMURIN_BUILD_ARGS"
echo " cd temurin-build && ./makejdk-any-platform.sh $TEMURIN_BUILD_ARGS > build.log 2>&1" | sh

echo Comparing ...
mkdir tarJDK
tar xpfz temurin-build/workspace/target/OpenJDK*-jdk_*tar.gz -C tarJDK
cp temurin-build/workspace/target/OpenJDK*-jdk_*tar.gz reproJDK.tar.gz
cp "$SBOM" SBOM.json
cp temurin-build/build.log build.log

cp "$ScriptPath"/repro_*.sh "$PWD"
chmod +x "$PWD"/repro_*.sh
rc=0
set +e
./repro_compare.sh temurin "$sourceJDK" temurin tarJDK/jdk-"$TEMURIN_VERSION" Linux 2>&1 || rc=$?
set -e

if [ $rc -eq 0 ]; then
  echo "Compare identical !"
else
  echo "Differences found..., logged in: reprotest.diff"
fi

exit $rc
