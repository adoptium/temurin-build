#!/bin/bash
# shellcheck disable=SC2155,SC2153,SC2038,SC1091,SC2116,SC2086
# ********************************************************************************
# Copyright (c) 2017, 2024 Contributors to the Eclipse Foundation
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

# Note that this script expects SCM_REF and TARGET_ARCH variables to be provided
# by the calling jenkins job

createMetadataFile() {
    metadata_file="$1"
    arch="$2"
    scm_ref="$3"
    build_src_file="$4"
    version_txt_file="$5"
    sha256="$6"
    
    echo "Creating metadata file: $metadata_file $arch $scm_ref $build_src_file $version_txt_file $sha256"

    ver_txt=$(cat $version_txt_file | sed 's/$/\\n/' | tr -d '\r\n' | sed 's/"/\\"/g')
    ver_pattern=".*Runtime Environment.*\(build ([0-9a-z_+-\\.]+).*OpenJDK.*"
    if [[ "$ver_txt" =~ .*$ver_pattern.* ]]; then
      ver=${BASH_REMATCH[1]}
    else
      echo "ERROR: Unable to find java version output build string"
      exit 1
    fi
    
    bin_type=$(echo $metadata_file | cut -d'-' -f2 | cut -d'_' -f1)

    release_pattern="1\.8\.0_([0-9]+)-b([0-9]+)"
    beta_pattern="1\.8\.0_([0-9]+)-([a-zA-Z]+)-([0-9]+)-b([0-9]+)"

    if [[ "$ver" =~ $release_pattern ]]; then
      update=${BASH_REMATCH[1]}
      build=${BASH_REMATCH[2]}
      pre="null"
      opt="null"
      adopt_build_num="null"
      ver_pre=""
      ver_opt=""
      semver_adopt_build_num=""
      semver_opt=""
      build_trim="${build##0}"
    elif [[ "$ver" =~ $beta_pattern ]]; then
      update=${BASH_REMATCH[1]}
      pre=$(printf '"%s"' "${BASH_REMATCH[2]}")
      opt=$(printf '"%s"' "${BASH_REMATCH[3]}")
      build=${BASH_REMATCH[4]}
      adopt_build_num="0"
      ver_pre="-${BASH_REMATCH[2]}"
      ver_opt="-${BASH_REMATCH[3]}"
      semver_adopt_build_num=".$adopt_build_num"
      semver_opt=".${BASH_REMATCH[3]}"
      build_trim="${build##0}"
    else
      echo "ERROR: Unable to determine metadata parameters"
      exit 1
    fi

    # Write metadata in one grouped redirect to avoid repeated >> operations
{
  echo '{'
  echo '"vendor": "Eclipse Adoptium",'
  echo '"os": "solaris",'
  echo "\"arch\": \"${arch}\","
  echo '"variant": "temurin",'
  echo '"version": {'
  echo '    "minor": 0,'
  echo '    "patch": null,'
  echo "    \"msi_product_version\": \"8.0.${update}.${build_trim}\","
  echo "    \"security\": ${update},"
  echo "    \"pre\": ${pre},"
  echo "    \"adopt_build_number\": ${adopt_build_num},"
  echo '    "major": 8,'
  echo "    \"version\": \"1.8.0_${update}${ver_pre}${ver_opt}-b${build}\","
  echo "    \"semver\": \"8.0.${update}${ver_pre}+${build_trim}${semver_adopt_build_num}${semver_opt}\","
  echo "    \"build\": ${build_trim},"
  echo "    \"opt\": ${opt}"
  echo '},'
  echo "\"scmRef\": \"${scm_ref}\","
  sed 's/^/"buildRef": "/' "$build_src_file"
  echo '",'
  echo '"version_data": "jdk8u",'
  echo "\"binary_type\": \"${bin_type}\","
  echo "\"sha256\": \"${sha256}\","
  echo "\"full_version_output\": \"${ver_txt}\","
  echo '"makejdk_any_platform_args": "",'
  echo '"configure_arguments": "",'
  echo '"make_command_args": "",'
  echo '"BUILD_CONFIGURATION_param": "",'
  echo '"openjdk_built_config": "",'
  echo '"openjdk_source": "",'
  echo '"build_env_docker_image_digest": "",'
  echo '"dependency_version_alsa": "",'
  echo '"dependency_version_freetype": "",'
  echo '"dependency_version_freemarker": ""'
  echo '}'
} >> "$metadata_file"
}

# Clear out proxy workspace to avoid archiving old artifacts if job is aborted
echo RELEASE=$RELEASE
rm -rf workspace
# This comes from a variable definition on the agent
SSH_OPTS="$SSH_PROXY_OPTS"
# "-o LogLevel=FATAL -o StrictHostKeyChecking=no -o PubkeyAcceptedKeyTypes=+ssh-rsa -o HostKeyAlgorithms=+ssh-rsa -i /home/solaris/test-azure-solaris10-x64-1/.vagrant/machines/adoptopenjdkSol10/virtualbox/private_key"

if [ "$RELEASE" = true ]; then
    PUBLISH_NAME="${SCM_REF//_adopt/}"
else
    PUBLISH_NAME="${SCM_REF//_adopt/-ea}"
fi

if [ -n "$PUBLISH_NAME" ]; then
    # Use correct published filename format
    FILENAME="OpenJDK8U-jdk_${TARGET_ARCH}_solaris_hotspot_$(echo $PUBLISH_NAME | sed 's/jdk//' | sed 's/-b/b/').tar.gz"
else
    # Use Timestamp
    FILE_DATE=$(date -u +'%Y-%m-%d-%H-%M')
    FILENAME="OpenJDK8U-jdk_${TARGET_ARCH}_solaris_hotspot_$FILE_DATE"
fi
# git clone changed from github.com/sxa/openjdk-build -b solarisfixes on April 8th
ssh -p ${SSH_PORT} ${SSH_TARGET} $SSH_OPTS \
    JDK7_BOOT_DIR="$JDK7_BOOT_DIR" VARIANT=temurin SCM_REF="$SCM_REF" \
    BUILD_ARGS="$BUILD_ARGS" CONFIGURE_ARGS="$CONFIGURE_ARGS" JDK7_BOOT_DIR=$JDK7_BOOT_DIR \
    PUBLISH_NAME="$PUBLISH_NAME" RELEASE="$RELEASE" \
	"rm -rf temurin-build && \
	 git clone https://github.com/adoptium/temurin-build && \
	 cd temurin-build/build-farm && \
     export FILENAME=\"${FILENAME}\" && \
     export BUILD_ARGS=\"${BUILD_ARGS}\" && \
     export CONFIGURE_ARGS=\"${CONFIGURE_ARGS}\" && \
     export JDK7_BOOT_DIR=\"${JDK7_BOOT_DIR}\" && \
     export SCM_REF=\"${SCM_REF}\" && \
     export VARIANT=\"${VARIANT}\" && \
     export PUBLISH_NAME=\"${PUBLISH_NAME}\" && \
     export WORKSPACE=\$HOME/temurin-build && \
     export JAVA_HOME=/usr/lib/jvm/jdk8 && \
     export RELEASE=\"${RELEASE}\" && \
     export PATH=\"/usr/local/bin:\$PATH\" && \ java -version && \
     ./make-adopt-build-farm.sh jdk8u"
# /usr/local/bin needed at start of path to avoid picking up /usr/sfw/bin/ant
# JAVA_HOME needed to avoid ant giving org/apache/tools/ant/launch/Launcher : Unsupported major.minor version 52.0

mkdir -p workspace/target
scp -prP "${SSH_PORT}" $SSH_OPTS "${SSH_TARGET}:temurin-build/build-farm/workspace/target/*" workspace/target

cd workspace/target || exit 1
for FILE in OpenJDK*; do
    echo "Creating metadata for ${FILE}"

    if [[ "${FILE}" == *-sbom_* ]]; then
        echo "SBOM detected – removing upstream checksum if present"
        rm -f "${FILE}.sha256.txt"
        sha256=""
        metadata_file="${FILE%.*}-metadata.json"
    else
        sha256sum "${FILE}" > "${FILE}.sha256.txt"
        sha256=$(cut -d' ' -f1 "${FILE}.sha256.txt")
        metadata_file="${FILE}.json"
    fi

    createMetadataFile "$metadata_file" "${TARGET_ARCH}" "$SCM_REF" \
        metadata/buildSource.txt metadata/version.txt "$sha256"
done


# Simple test job uses filenames.txt to determine the correct filenames to pull down
ls -1 > filenames.txt
cd ../../..
pwd
ls -lR
# Memo to self for tests:
#  Set PATH=/usr/local/bin:/opt/csw/bin:$PATH so that git and Perl 5.10 with Digest::SHA.pm can be located
