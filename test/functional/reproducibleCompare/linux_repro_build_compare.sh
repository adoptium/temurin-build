#!/bin/sh
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

# This script examines the given SBOM metadata file, and then builds the exact same binary
# and then compares with the Temurin JDK for the same build version, or the optionally supplied TARBALL_URL.

installPrereqs() {
  if test -r /etc/redhat-release; then
    yum install -y gcc gcc-c++ make autoconf unzip zip alsa-lib-devel cups-devel libXtst-devel libXt-devel libXrender-devel libXrandr-devel libXi-devel
    yum install -y file fontconfig fontconfig-devel systemtap-sdt-devel # Not included above ...
    yum install -y git bzip2 xz openssl pigz which jq # pigz/which not strictly needed but help in final compression
    if grep -i release.6 /etc/redhat-release; then
      if [ ! -r /usr/local/bin/autoconf ]; then
        curl https://ftp.gnu.org/gnu/autoconf/autoconf-2.69.tar.gz | tar xpfz - || exit 1
        (cd autoconf-2.69 && ./configure --prefix=/usr/local && make install)
      fi
    fi
  fi
}

# ant required for --create-sbom
downloadAnt() {
  if [ ! -r /usr/local/apache-ant-${ANT_VERSION}/bin/ant ]; then
    echo Downloading ant for SBOM creation:
    curl https://archive.apache.org/dist/ant/binaries/apache-ant-${ANT_VERSION}-bin.zip > /tmp/apache-ant-${ANT_VERSION}-bin.zip
    (cd /usr/local && unzip -qn /tmp/apache-ant-${ANT_VERSION}-bin.zip)
    rm /tmp/apache-ant-${ANT_VERSION}-bin.zip
    echo Downloading ant-contrib-${ANT_CONTRIB_VERSION}:
    curl -L https://sourceforge.net/projects/ant-contrib/files/ant-contrib/${ANT_CONTRIB_VERSION}/ant-contrib-${ANT_CONTRIB_VERSION}-bin.zip > /tmp/ant-contrib-${ANT_CONTRIB_VERSION}-bin.zip
    (unzip -qnj /tmp/ant-contrib-${ANT_CONTRIB_VERSION}-bin.zip ant-contrib/ant-contrib-${ANT_CONTRIB_VERSION}.jar -d /usr/local/apache-ant-${ANT_VERSION}/lib)
    rm /tmp/ant-contrib-${ANT_CONTRIB_VERSION}-bin.zip
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

cleanBuildInfo() {
  # BUILD_INFO name of OS level build was built on will likely differ
  sed -i '/^BUILD_INFO=.*$/d' "${originalJDKDir}/release"
  sed -i '/^BUILD_INFO=.*$/d' "compare.$$/jdk-${TEMURIN_VERSION}/release"
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

originalJDKDir=""
workDir="$PWD"

if [ $# -lt 1 ]; then
  if [ -d "/home/jenkins/jdkbinary" ]; then
    find /home/jenkins/jdkbinary -type f -name '*sbom*.json' -exec cp {} "${workDir}" \;
    SBOM=$(find /home/jenkins/jdkbinary -type f -name '*sbom*.json' -exec basename {} \;)
    echo "SBOM is ${SBOM}"
  else
    echo "Usage: $0 SBOM_URL TARBALL_URL" && exit 1
  fi
else
  SBOM_URL=$1
  TARBALL_URL=$2
  echo "Retrieving and parsing SBOM from $SBOM_URL"
  curl -LO "$SBOM_URL"
  SBOM=$(basename "$SBOM_URL")
fi

ANT_VERSION=1.10.5
ANT_CONTRIB_VERSION=1.0b3
installPrereqs
downloadAnt
ls
BOOTJDK_VERSION=$(jq -r '.metadata.tools[] | select(.name == "BOOTJDK") | .version' "$SBOM")
GCCVERSION=$(jq -r '.metadata.tools[] | select(.name == "GCC") | .version' "$SBOM" | sed 's/.0$//')
LOCALGCCDIR=/usr/local/gcc$(echo "$GCCVERSION" | cut -d. -f1)
TEMURIN_BUILD_SHA=$(jq -r '.components[] | .properties[] | select (.name == "Temurin Build Ref") | .value' "$SBOM" | awk -F/ '{print $NF}')
TEMURIN_BUILD_ARGS=$(jq -r '.components[] | .properties[] | select (.name == "makejdk_any_platform_args") | .value' "$SBOM" | cut -d\" -f4 | sed -e "s/--disable-warnings-as-errors --enable-dtrace --without-version-pre --without-version-opt/'--disable-warnings-as-errors --enable-dtrace --without-version-pre --without-version-opt'/" -e "s/ --disable-warnings-as-errors --enable-dtrace/ '--disable-warnings-as-errors --enable-dtrace'/" -e 's/\\n//g' -e "s,--jdk-boot-dir [^ ]*,--jdk-boot-dir /usr/lib/jvm/jdk-$BOOTJDK_VERSION,g")
TEMURIN_VERSION=$(jq -r '.metadata.component.version' "$SBOM" | sed 's/-beta//' | cut -f1 -d"-")
NATIVE_API_ARCH=$(uname -m)
if [ "${NATIVE_API_ARCH}" = "x86_64" ]; then NATIVE_API_ARCH=x64; fi
if [ "${NATIVE_API_ARCH}" = "armv7l" ]; then NATIVE_API_ARCH=arm; fi

checkAllVariablesSet

downloadTooling
setEnvironment

if [ $# -lt 1 ]; then
  javacPath=$(find /home/jenkins/jdkbinary -name javac | grep -E 'bin/javac$')
  if [ "$javacPath" != "" ]; then
    originalJDKDir=$(dirname "${javacPath}")/../
  fi
fi

if [ -z "${originalJDKDir}" ] && [ ! -d "jdk-${TEMURIN_VERSION}" ]; then
  if [ -z "$TARBALL_URL" ]; then
      TARBALL_URL="https://api.adoptium.net/v3/binary/version/jdk-${TEMURIN_VERSION}/linux/${NATIVE_API_ARCH}/jdk/hotspot/normal/eclipse?project=jdk"
  fi
  echo Retrieving original tarball from adoptium.net && curl -L "$TARBALL_URL" | tar xpfz - && ls -lart "$PWD/jdk-${TEMURIN_VERSION}" || exit 1
  originalJDKDir="$PWD/jdk-${TEMURIN_VERSION}"
fi

echo "  cd temurin-build && ./makejdk-any-platform.sh $TEMURIN_BUILD_ARGS 2>&1 | tee build.$$.log" | sh

echo Comparing ...
mkdir compare.$$
tar xpfz temurin-build/workspace/target/OpenJDK*-jdk_*tar.gz -C compare.$$
cleanBuildInfo

rc=0
# shellcheck disable=SC2069
diff -r "${originalJDKDir}" "compare.$$/jdk-$TEMURIN_VERSION" 2>&1 > "reprotest.$(uname).$TEMURIN_VERSION.diff" || rc=$?

if [ $rc != 0 ]; then
  cat "reprotest.$(uname).$TEMURIN_VERSION.diff"
  echo "Differences found..., logged in: reprotest.$(uname).$TEMURIN_VERSION.diff"
else
  echo "Compare identical !"
fi

cp reprotest."$(uname)"."${TEMURIN_VERSION}".diff reprotest.diff
exit $rc