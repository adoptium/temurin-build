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
      build_trim=$(echo $build | sed 's/^0*//')
    elif [[ "$ver" =~ $beta_pattern ]]; then
      update=${BASH_REMATCH[1]}
      pre='"'${BASH_REMATCH[2]}'"'
      opt='"'${BASH_REMATCH[3]}'"'
      build=${BASH_REMATCH[4]}
      adopt_build_num="0"
      ver_pre="-${BASH_REMATCH[2]}"
      ver_opt="-${BASH_REMATCH[3]}"
      semver_adopt_build_num=".$adopt_build_num"
      semver_opt=".${BASH_REMATCH[3]}"
      build_trim=$(echo $build | sed 's/^0*//')
    else
      echo "ERROR: Unable to determine metadata parameters"
      exit 1
    fi

    echo '{' > $metadata_file
    echo '"vendor": "Eclipse Adoptium",' >> $metadata_file
    echo '"os": "solaris",' >> $metadata_file
    echo '"arch": "'$arch'",' >> $metadata_file
    echo '"variant": "temurin",' >> $metadata_file
    echo '"version": {' >> $metadata_file
    echo '    "minor": 0,' >> $metadata_file
    echo '    "patch": null,' >> $metadata_file
    echo '    "msi_product_version": "8.0.'$update'.'$build_trim'",' >> $metadata_file
    echo '    "security": '$update',' >> $metadata_file
    echo '    "pre": '$pre',' >> $metadata_file
    echo '    "adopt_build_number": '$adopt_build_num',' >> $metadata_file
    echo '    "major": 8,' >> $metadata_file
    echo '    "version": "1.8.0_'$update$ver_pre$ver_opt'-b'$build'",' >> $metadata_file
    echo '    "semver": "8.0.'$update$ver_pre'+'$build_trim$semver_adopt_build_num$semver_opt'",' >> $metadata_file
    echo '    "build": '$build_trim',' >> $metadata_file
    echo '    "opt": '$opt >> $metadata_file
    echo '},' >> $metadata_file
    echo '"scmRef": "'$scm_ref'",' >> $metadata_file
    cat $build_src_file | sed 's/^/"buildRef": "/' >> $metadata_file
    echo '",'>> $metadata_file 
    echo '"version_data": "jdk8u",' >> $metadata_file
    echo '"binary_type": "'$bin_type'",' >> $metadata_file
    echo '"sha256": "'$sha256'",' >> $metadata_file
    echo '"full_version_output": "'$ver_txt'",' >> $metadata_file
    echo '"makejdk_any_platform_args": "",' >> $metadata_file 
    echo '"configure_arguments": "",' >> $metadata_file
    echo '"make_command_args": "",' >> $metadata_file
    echo '"BUILD_CONFIGURATION_param": "",' >> $metadata_file
    echo '"openjdk_built_config": "",' >> $metadata_file
    echo '"openjdk_source": "",' >> $metadata_file
    echo '"build_env_docker_image_digest": "",' >> $metadata_file
    echo '"dependency_version_alsa": "",' >> $metadata_file
    echo '"dependency_version_freetype": "",' >> $metadata_file
    echo '"dependency_version_freemarker": ""' >> $metadata_file
    echo '}' >> $metadata_file
}

# Clear out proxy workspace to avoid archiving old artifacts if job is aborted
echo RELEASE=$RELEASE
rm -rf workspace
# This comes from a variable definition on the agent
SSH_OPTS="$SSH_PROXY_OPTS"
# "-o LogLevel=FATAL -o StrictHostKeyChecking=no -o PubkeyAcceptedKeyTypes=+ssh-rsa -o HostKeyAlgorithms=+ssh-rsa -i /home/solaris/test-azure-solaris10-x64-1/.vagrant/machines/adoptopenjdkSol10/virtualbox/private_key"

if [ "$RELEASE" = true ]; then
    PUBLISH_NAME=$(echo $SCM_REF | sed 's/_adopt//')
else
    PUBLISH_NAME=$(echo $SCM_REF | sed 's/_adopt/-ea/')
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
     export FILENAME="$FILENAME" && \
     export BUILD_ARGS="$BUILD_ARGS" && \
     export CONFIGURE_ARGS="$CONFIGURE_ARGS" && \
     export JDK7_BOOT_DIR="$JDK7_BOOT_DIR" && \
     export SCM_REF="$SCM_REF" && \
     export VARIANT="$VARIANT" && \
     export PUBLISH_NAME="$PUBLISH_NAME" && \
     export WORKSPACE=$HOME/temurin-build && \
     export JAVA_HOME=/usr/lib/jvm/jdk8 && \
     export RELEASE="$RELEASE" && \
     export PATH="/usr/local/bin:$PATH" && java -version && \
     ./make-adopt-build-farm.sh jdk8u"
# /usr/local/bin needed at start of path to avoid picking up /usr/sfw/bin/ant
# JAVA_HOME needed to avoid ant giving org/apache/tools/ant/launch/Launcher : Unsupported major.minor version 52.0

mkdir -p workspace/target
scp -prP "${SSH_PORT}" $SSH_OPTS "${SSH_TARGET}:temurin-build/build-farm/workspace/target/*" workspace/target

cd workspace/target || exit 1
for FILE in OpenJDK*; do
    echo Creating metadata for ${FILE}
    # Skip checksum generation for SBOM files
    if [[ "$FILE" == *sbom.json ]]; then
        echo "Skipping checksum generation for SBOM: $FILE"
        sha256=""
    else
        sha256sum "$FILE" > "$FILE.sha256.txt"
        sha256=$(cut -d' ' -f1 "$FILE.sha256.txt")
    fi

    # Metadata filename: SBOM files get <name>-metadata.json (consistent with naming)
    if [[ "$FILE" == *sbom.json ]]; then
        metadata_file="${FILE%.*}-metadata.json"
    else
        metadata_file="$FILE.json"
    fi
    createMetadataFile "$metadata_file" "${TARGET_ARCH}" "$SCM_REF" metadata/buildSource.txt metadata/version.txt "$sha256"
done
# Simple test job uses filenames.txt to determine the correct filenames to pull down
ls -1 > filenames.txt
cd ../../..
pwd
ls -lR
# Memo to self for tests:
#  Set PATH=/usr/local/bin:/opt/csw/bin:$PATH so that git and Perl 5.10 with Digest::SHA.pm can be located
