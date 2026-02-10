#!/bin/bash
# shellcheck disable=SC2001
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

# Shellcheck SC2001 disable added as suggested anti-glob quoting does not work as required

set -e

# Adoptium's public GPG key used for GPG signatures
ADOPTIUM_PUBLIC_GPG_KEY="0x3B04D753C9050D9A5D343F39843C48A565F8F04B"

ANT_VERSION=1.10.5
ANT_SHA=9028e2fc64491cca0f991acc09b06ee7fe644afe41d1d6caf72702ca25c4613c
ANT_CONTRIB_VERSION=1.0b3
ANT_CONTRIB_SHA=4d93e07ae6479049bb28071b069b7107322adaee5b70016674a0bffd4aac47f9
USING_DEVKIT="false"
ScriptPath=$(dirname "$(realpath "$0")")

# Read Parameters
SBOM_PARAM=""
JDK_PARAM=""
USER_DEVKIT_LOCATION=""
ATTESTATION_VERIFY=false

while [[ $# -gt 0 ]] ; do
  opt="$1";
  shift;

  echo "Parsing opt: ${opt}"
  case "$opt" in
    "--sbom-url" )
    SBOM_PARAM="$1"; shift;;

    "--jdk-url" )
    JDK_PARAM="$1"; shift;;

    "--user-devkit-location" )
    USER_DEVKIT_LOCATION="$1"; shift;;

    "--attestation-verify" )
    ATTESTATION_VERIFY=true;;

    *) echo >&2 "Invalid option: ${opt}"; exit 1;;
  esac
done

# Check All Required Params Are Supplied
if [ -z "$SBOM_PARAM" ] || [ -z "$JDK_PARAM" ]; then
  echo "Usage: linux_repro_build_compare.sh [Params]"
  echo "Parameters:"
  echo "  Required:"
  echo "    --sbom-url [SBOM_URL/SBOM_PATH] : should be the FULL path OR a URL to a Temurin JDK SBOM JSON file in CycloneDX Format"
  echo "    --jdk-url [JDKZIP_URL/JDKZIP_PATH] : should be the FULL path OR a URL to a Temurin Linux JDK tarball file"
  echo "  Optional:"
  echo "    --user-devkit-location [USER_DEVKIT_LOCATION] : FULL path OR a URL location of tarball of a user built Linux gcc DevKit"
  echo "    --attestation-verify : Enables Attestation Verification mode, where native OpenJDK source and make used rather than temurin-build scripts"
  exit 1
fi

# For an Attestation verification build a local secure build of the devkit must be used
if [ "$ATTESTATION_VERIFY" == true ] && [ -z "$USER_DEVKIT_LOCATION" ]; then
  echo "--user-devkit-location [USER_DEVKIT_LOCATION] must be specified when using --attestation-verify"
  exit 1
fi

# Function to check if a string is a valid URL
is_url() {
  local url=$1
  if [[ $url =~ ^https?:// ]]; then
    return 0  # URL
  else
    return 1  # Not a URL
  fi
} 

installPrereqs() {
  if test -r /etc/redhat-release; then
    if grep -i release.7 /etc/redhat-release; then
      # Replace mirrorlist to vault as centos7 reached EOL.
      if [ -f /etc/yum.repos.d/CentOS-Base.repo ]; then
        sed -i -e 's!mirrorlist!#mirrorlist!g' /etc/yum.repos.d/CentOS-Base.repo
        sed -i 's|#baseurl=http://mirror.centos.org/|baseurl=http://vault.centos.org/|' /etc/yum.repos.d/CentOS-Base.repo
      fi
    elif grep -i release.8 /etc/redhat-release; then
      # Replace mirrorlist to vault as centos8 reached EOL.
      if ls /etc/yum.repos.d/CentOS-Linux-*.repo >/dev/null 2>&1; then
        sed -i -e 's!mirrorlist!#mirrorlist!g' /etc/yum.repos.d/CentOS-Linux-*.repo
        sed -i 's|#baseurl=http://mirror.centos.org/|baseurl=http://vault.centos.org/|' /etc/yum.repos.d/CentOS-Linux-*.repo
      fi
      yum install -y diffutils
    fi
    yum install -y procps-ng binutils cpio
    yum install -y make autoconf unzip zip file systemtap-sdt-devel
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

installNonDevKitPrereqs() {
  if test -r /etc/redhat-release; then
    yum install -y gcc gcc-c++ alsa-lib-devel cups-devel libXtst-devel libXt-devel libXrender-devel libXrandr-devel libXi-devel
    yum install -y fontconfig fontconfig-devel epel-release
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

setOpenJDKConfigureArgs() {
  # reset --jdk-boot-dir and remove --with-cacerts-src
  adoptiumConfigureArgs="$(echo "$adoptiumConfigureArgs" | sed -e "s|--with-boot-jdk=[^ ]*|--with-boot-jdk=${BOOTJDK_HOME}|")"
  adoptiumConfigureArgs="$(echo "$adoptiumConfigureArgs" | sed -e "s|--with-cacerts-src=[^ ]*||")"

  # Extract user devkit
  mkdir -p "devkit"
  echo "Unpacking ${USER_DEVKIT_LOCATION} into $PWD/devkit"
  if is_url "${USER_DEVKIT_LOCATION}" ; then
    local tmp_devkit_tarball="$(basename "${USER_DEVKIT_LOCATION}")"
    curl -L "${USER_DEVKIT_LOCATION}" --output "$tmp_devkit_tarball"
    tar -xf "$tmp_devkit_tarball" -C "$PWD/devkit"
    rm "$tmp_devkit_tarball"
  else
    tar -xf "${USER_DEVKIT_LOCATION}" -C "$PWD/devkit"
  fi  
  adoptiumConfigureArgs="$(echo "$adoptiumConfigureArgs" | sed -e "s|--with-devkit=[^ ]*|--with-devkit=${PWD}/devkit|")"
      
  echo ""
  echo "OpenJDK Configure Argument List = "
  echo "$adoptiumConfigureArgs"
  echo ""
}

setTemurinBuildArgs() {
  local buildArgs="$1"
  local bootJdk="$2"
  local timeStamp="$3"
  local using_DEVKIT="$4"
  local userDevkitLocation="$5"
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
  buildArgs="$(echo "$buildArgs" | sed -e "s|--jdk-boot-dir [^ ]*|--jdk-boot-dir ${BOOTJDK_HOME}|")"

  if [[ "${using_DEVKIT}" == "true" ]] && [[ -n "${userDevkitLocation}" ]]; then
    buildArgs="--user-devkit-location ${userDevkitLocation} ${buildArgs}"
  fi

  echo "${buildArgs}"
}

downloadTooling() {
  local using_DEVKIT=$1

  if [ ! -r "/usr/lib/jvm/jdk-${BOOTJDK_VERSION}/bin/javac" ]; then
    local api_query="https://api.adoptium.net/v3/binary/version/jdk-${BOOTJDK_VERSION}/linux/${NATIVE_API_ARCH}/jdk/hotspot/normal/eclipse?project=jdk"
    echo "Trying to get BootJDK jdk-${BOOTJDK_VERSION} from ${api_query}"
    if ! curl --fail -L -o bootjdk.tar.gz "${api_query}"; then
      echo "Unable to download BootJDK version jdk-${BOOTJDK_VERSION} from ${api_query}"
      local major_version
      major_version=$(echo "${BOOTJDK_VERSION}" | cut -d'.' -f1)
      api_query="https://api.adoptium.net/v3/binary/latest/${major_version}/ga/linux/${NATIVE_API_ARCH}/jdk/hotspot/normal/eclipse"
      echo "Trying to get latest GA for version ${major_version} from ${api_query}"
      if ! curl --fail -L -o bootjdk.tar.gz "${api_query}"; then
        echo "Unable to download BootJDK version jdk-${BOOTJDK_VERSION} from ${api_query}"
        api_query="https://api.adoptium.net/v3/binary/latest/${major_version}/ea/linux/${NATIVE_API_ARCH}/jdk/hotspot/normal/adoptium"
        echo "Trying to get latest EA for version ${major_version} from ${api_query}"
        if ! curl --fail -L -o bootjdk.tar.gz "${api_query}"; then
          echo "Unable to download BootJDK version jdk-${BOOTJDK_VERSION} from ${api_query}"
          exit 2
        fi
      fi
    fi
    # Update BOOTJDK_VERSION with actual one downloaded
    BOOTJDK_VERSION=$(tar -tf bootjdk.tar.gz | cut -d/ -f1 | head -n 1 | sed 's/^jdk-//')

    echo "Downloading gpg signature for ${BOOTJDK_VERSION}.."
    local sig_query="https://api.adoptium.net/v3/signature/version/jdk-${BOOTJDK_VERSION}/linux/${NATIVE_API_ARCH}/jdk/hotspot/normal/eclipse?project=jdk"
    if ! curl --fail -L -o bootjdk.tar.gz.sig "${sig_query}"; then
      echo "Unable to download BootJDK gpg signature for jdk-${BOOTJDK_VERSION} from ${sig_query}"
      exit 2
    fi

    echo "Obtaining Adoptium's public GPG key.."
    curl -sSL "https://keyserver.ubuntu.com/pks/lookup?op=get&search=${ADOPTIUM_PUBLIC_GPG_KEY}" --output "adoptium.gpg.key"
    gpg --import "adoptium.gpg.key"
    rm "adoptium.gpg.key"
    if ! gpg --verify "bootjdk.tar.gz.sig" "bootjdk.tar.gz"; then
      echo "GPG Verify of bootjdk.tar.gz failed"
      exit 1
    fi

    echo "Using downloaded BOOTJDK_VERSION=${BOOTJDK_VERSION}"
    mkdir -p "$PWD/bootjdk" && tar -xzf bootjdk.tar.gz -C "$PWD/bootjdk"
    export PATH=$PWD/bootjdk/jdk-${BOOTJDK_VERSION}/bin:$PATH
    export BOOTJDK_HOME=$PWD/bootjdk/jdk-${BOOTJDK_VERSION}
    rm bootjdk.tar.gz
    rm bootjdk.tar.gz.sig
  else
    export BOOTJDK_HOME=/usr/lib/jvm/jdk-${BOOTJDK_VERSION}
  fi

  if [ "$ATTESTATION_VERIFY" == false ]; then
    if [[ "${using_DEVKIT}" == "false" ]]; then
      if [ ! -r "${LOCALGCCDIR}/bin/g++-${GCCVERSION}" ]; then
        echo "Retrieving gcc $GCCVERSION" && curl "https://ci.adoptium.net/userContent/gcc/gcc$(echo "$GCCVERSION" | tr -d .).$(uname -m).tar.xz" | (cd /usr/local && tar xJpf -) || exit 1
      fi
    fi
    if [ ! -r temurin-build ]; then
      # Shallow clone
      git clone --depth 1 https://github.com/adoptium/temurin-build || exit 1
    fi
    # Checkout required SHA only
    (cd temurin-build && git fetch --depth 1 origin "$TEMURIN_BUILD_SHA" && git checkout "$TEMURIN_BUILD_SHA")
  fi
}

checkAllVariablesSet() {
  if [ "$ATTESTATION_VERIFY" == true ]; then
    if [ -z "$SBOM" ] || [ -z "${BOOTJDK_VERSION}" ] || [ -z "${adoptiumConfigureArgs}" ] || [ -z "${TEMURIN_VERSION}" ] || [ -z "${buildScmRef}" ] || [ -z "${openjdkSourceRepo}" ] || [ -z "${openjdkSourceTag}" ]; then
      echo "Could not determine one of the variables - run with sh -x to diagnose" && sleep 10 && exit 1
    fi
  else
    if [ -z "$SBOM" ] || [ -z "${BOOTJDK_VERSION}" ] || [ -z "${TEMURIN_BUILD_SHA}" ] || [ -z "${TEMURIN_BUILD_ARGS}" ] || [ -z "${TEMURIN_VERSION}" ]; then
      echo "Could not determine one of the variables - run with sh -x to diagnose" && sleep 10 && exit 1
    fi
  fi
}

getBuildParams() {
  BOOTJDK_VERSION=$(jq -r '.metadata.tools.components[] | select(.name == "BOOTJDK") | .version' "$SBOM" | sed -e 's#-LTS$##')
  GCCVERSION=$(jq -r '.metadata.tools.components[] | select(.name == "GCC") | .version' "$SBOM" | sed 's/.0$//')
  LOCALGCCDIR=/usr/local/gcc$(echo "$GCCVERSION" | cut -d. -f1)
  TEMURIN_BUILD_SHA=$(jq -r '.components[0] | .properties[] | select (.name == "Temurin Build Ref") | .value' "$SBOM" | awk -F/ '{print $NF}')
  TEMURIN_VERSION=$(jq -r '.metadata.component.version' "$SBOM" | sed 's/-beta//' | cut -f1 -d"-")
  BUILDSTAMP=$(jq -r '.components[0].properties[] | select(.name == "Build Timestamp") | .value' "$SBOM")
  TEMURIN_BUILD_ARGS=$(jq -r '.components[0] | .properties[] | select (.name == "makejdk_any_platform_args") | .value' "$SBOM")

  if [ "$ATTESTATION_VERIFY" == true ]; then
    adoptiumSrcCommitUrl=$(jq -r '.components[0].properties[] | select(.name == "OpenJDK Source Commit") | .value' "$SBOM")
    buildScmRef=$(jq -r '.components[0].properties[] | select(.name == "SCM Ref") | .value' "$SBOM")
    adoptiumConfigureArgs=$(jq -r '.components[0].properties[] | select(.name == "configure_args") | .value' "$SBOM")

    # Check if the adoptiumSrcCommitUrl, buildScmRef and configure_args were found
    if [ -n "$adoptiumSrcCommitUrl" ] && [ -n "$buildScmRef" ] && [ -n "$adoptiumConfigureArgs" ]; then
      adoptiumRepo="${adoptiumSrcCommitUrl%/commit/*}"
      openjdkSourceRepo="${adoptiumRepo/adoptium/openjdk}"
      openjdkSourceTag="${buildScmRef%_adopt}"

      echo "Performing an Attestation Verification Build from $openjdkSourceRepo with tag $openjdkSourceTag"
      echo "Adoptium OpenJDK configure argmuents from original Temurin build:"
      echo "    $adoptiumConfigureArgs"
      echo ""
      export openjdkSourceRepo
      export openjdkSourceTag
      export adoptiumConfigureArgs
    else
      echo "ERROR: Adoptium OpenJDK Source Commit, SCM Ref and configure_args must be specified in the SBOM."
      echo "These Are Mandatory Elements"
      exit 1
    fi
  fi

  # Remove any --with-jobs, let local user system determine
  # shellcheck disable=SC2001
  TEMURIN_BUILD_ARGS=$(echo "$TEMURIN_BUILD_ARGS" | sed -e "s/--with-jobs=[0-9]*//g")

  NATIVE_API_ARCH=$(uname -m)
  if [ "${NATIVE_API_ARCH}" = "x86_64" ]; then NATIVE_API_ARCH=x64; fi
  if [ "${NATIVE_API_ARCH}" = "armv7l" ]; then NATIVE_API_ARCH=arm; fi
  if [[ "$TEMURIN_BUILD_ARGS" =~ .*"--use-adoptium-devkit".* ]]; then
    USING_DEVKIT="true"
  elif [ "$ATTESTATION_VERIFY" == true ]; then
    echo "The original JDK must be built using a DevKit when using --attestation-verify"
    exit 1
  fi
}

buildUsingTemurinBuild() {
  echo "Building JDK using temurin-build scripts..."

  echo "Rebuild args for makejdk_any_platform.sh are: $TEMURIN_BUILD_ARGS"
  if ! echo "cd temurin-build && ./makejdk-any-platform.sh $TEMURIN_BUILD_ARGS > build.log 2>&1" | sh; then
    # Echo build.log
    cat temurin-build/build.log || true
    echo "makejdk-any-platform.sh build failure, exiting"
    exit 1
  fi

  # Echo build.log
  cat temurin-build/build.log

  mkdir reproJDK
  tar xpfz temurin-build/workspace/target/OpenJDK*-jdk_*tar.gz -C reproJDK
  cp temurin-build/workspace/target/OpenJDK*-jdk_*tar.gz reproJDK.tar.gz
  cp "$SBOM" SBOM.json
  cp temurin-build/build.log build.log
}

attestationBuildUsingOpenJDK() {
  echo "Building JDK using OpenJDK configure and make..."

  echo "Cloning OpenJDK source Repository: $openjdkSourceRepo into openjdk"
  git clone -q "$openjdkSourceRepo" "openjdk" || exit 1
  echo "Switching To OpenJDK tag : $openjdkSourceTag"
  (cd "openjdk" && git checkout -q "$openjdkSourceTag")

  echo "Executing: bash ./configure $adoptiumConfigureArgs"
  if ! echo "cd openjdk && bash ./configure $adoptiumConfigureArgs > repro_configure.log 2>&1" | sh; then
    cat openjdk/repro_configure.log || true
    echo "OpenJDK configure failure, exiting"
    exit 1
  fi

  cat openjdk/repro_configure.log

  echo "Executing: make images"
  if ! echo "cd openjdk/build/* && make images > ../../repro_build.log 2>&1" | sh; then
    cat openjdk/repro_build.log || true
    echo "OpenJDK make images failure, exiting"
    exit 1
  fi

  cat openjdk/repro_build.log

  mv openjdk/build/*/images/jdk "openjdk/build/$openjdkSourceTag"
  (cd openjdk/build && tar -czf ../../reproJDK.tar.gz "$openjdkSourceTag")
  mkdir reproJDK && tar xpfz reproJDK.tar.gz -C reproJDK
  cp  openjdk/repro_configure.log build.log
  cat openjdk/repro_build.log  >> build.log
  cp "$SBOM" SBOM.json
}

######################################
############## MAIN ##################
######################################

if [ "$ATTESTATION_VERIFY" == false ]; then
  installPrereqs
  downloadAnt
fi

if [[ $SBOM_PARAM =~ ^https?:// ]]; then
  echo "Retrieving and parsing SBOM from $SBOM_PARAM"
  curl -LO "$SBOM_PARAM"
  SBOM=$(basename "$SBOM_PARAM")
else
  SBOM=$SBOM_PARAM
fi

getBuildParams
checkAllVariablesSet

downloadTooling "$USING_DEVKIT"
if [[ "${USING_DEVKIT}" == "false" ]]; then
  installNonDevKitPrereqs
  setNonDevkitGccEnvironment
fi

if [ "$ATTESTATION_VERIFY" == false ]; then
  setAntEnvironment
fi

if [ "$ATTESTATION_VERIFY" == true ]; then
  setOpenJDKConfigureArgs
else
  echo "original temurin build args is ${TEMURIN_BUILD_ARGS}"
  TEMURIN_BUILD_ARGS=$(setTemurinBuildArgs "$TEMURIN_BUILD_ARGS" "$BOOTJDK_VERSION" "$BUILDSTAMP" "$USING_DEVKIT" "$USER_DEVKIT_LOCATION")
fi

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

if [ "$ATTESTATION_VERIFY" == true ]; then
  attestationBuildUsingOpenJDK  
else
  buildUsingTemurinBuild
fi

echo Comparing ...
cp "$ScriptPath"/repro_*.sh "$PWD"
chmod +x "$PWD"/repro_*.sh
rc=0
set +e
if [ "$ATTESTATION_VERIFY" == true ]; then
  ./repro_compare.sh temurin "$sourceJDK" openjdk reproJDK/jdk-"$TEMURIN_VERSION" Linux 2>&1 || rc=$?
else
  ./repro_compare.sh temurin "$sourceJDK" temurin reproJDK/jdk-"$TEMURIN_VERSION" Linux 2>&1 || rc=$?
fi
set -e

if [ $rc -eq 0 ]; then
  echo "Compare identical !"
else
  echo "Differences found..., logged in: reprotest.diff"
fi

exit $rc
