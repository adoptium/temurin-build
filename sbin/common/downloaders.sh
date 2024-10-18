#!/bin/bash
# shellcheck disable=SC1091

# ********************************************************************************
# Copyright (c) 2018 Contributors to the Eclipse Foundation
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

####################################################################################
# This file is gathering all download boot jdk functions, so they can b reused later
# On long run, the methods - due theirs similarity - should converge to one
####################################################################################

# This function switches logic based on the (supported) os
function downloadBootJDK() {
  if uname -o | grep -i -e Linux ; then
    downloadLinuxBootJDK "$@"
  elif uname -o | grep -i -e Cygwin -e Windows ; then
    downloadWindowsBootJDK "$@"
  else
    echo "Unsupported platform for direct download of boot jdk: $(uname -m) $(uname -o)"
    exit 1
  fi
}

function downloadLinuxBootJDK() {
  local ARCH="${1}"
  local VER="${2}"
  local bootDir="${3}"
  export downloadArch
  case "$ARCH" in
     "riscv64") downloadArch="$NATIVE_API_ARCH";;
             *) downloadArch="$ARCH";;
  esac
  releaseType="ga"
  vendor="eclipse"
  apiUrlTemplate="https://api.adoptium.net/v3/binary/latest/\${VER}/\${releaseType}/linux/\${downloadArch}/jdk/hotspot/normal/\${vendor}"
  apiURL=$(eval echo "${apiUrlTemplate}")
  echo "Downloading GA release of boot JDK version ${VER} from ${apiURL}"
  # make-adopt-build-farm.sh has 'set -e'. We need to disable that for
  # the fallback mechanism, as downloading of the GA binary might fail.
  set +e
  curl -L -o bootjdk.tar.gz "${apiURL}"
  apiSigURL=$(curl -v "${apiURL}" 2>&1 | tr -d \\r | awk '/^< [Ll]ocation:/{print $3 ".sig"}')
  if ! grep "No releases match the request" bootjdk.tar.gz; then
    curl -L -o bootjdk.tar.gz.sig "${apiSigURL}"
    gpg --keyserver keyserver.ubuntu.com --recv-keys 3B04D753C9050D9A5D343F39843C48A565F8F04B
    echo -e "5\ny\n" |  gpg --batch --command-fd 0 --expert --edit-key 3B04D753C9050D9A5D343F39843C48A565F8F04B trust;
    gpg --verify bootjdk.tar.gz.sig bootjdk.tar.gz || exit 1
    mkdir "$bootDir"
    tar xpzf bootjdk.tar.gz --strip-components=1 -C "$bootDir"
    set -e
  else
    # We must be a JDK HEAD build for which no boot JDK exists other than
    # nightlies?
    echo "Downloading GA release of boot JDK version ${VER} failed."
    # shellcheck disable=SC2034
    releaseType="ea"
    # shellcheck disable=SC2034
    vendor="adoptium"
    apiURL=$(eval echo ${apiUrlTemplate})
    echo "Attempting to download EA release of boot JDK version ${VER} from ${apiURL}"
    set +e
    curl -L -o bootjdk.tar.gz "${apiURL}"
    if ! grep "No releases match the request" bootjdk.tar.gz; then
      apiSigURL=$(curl -v "${apiURL}" 2>&1 | tr -d \\r | awk '/^< [Ll]ocation:/{print $3 ".sig"}')
      curl -L -o bootjdk.tar.gz.sig "${apiSigURL}"
      gpg --keyserver keyserver.ubuntu.com --recv-keys 3B04D753C9050D9A5D343F39843C48A565F8F04B
      echo -e "5\ny\n" |  gpg --batch --command-fd 0 --expert --edit-key 3B04D753C9050D9A5D343F39843C48A565F8F04B trust;
      gpg --verify bootjdk.tar.gz.sig bootjdk.tar.gz || exit 1
      mkdir "$bootDir"
      tar xpzf bootjdk.tar.gz --strip-components=1 -C "$bootDir"
    else
      # If no binaries are available then try from adoptopenjdk
      echo "Downloading Temurin release of boot JDK version ${VER} failed."
      # shellcheck disable=SC2034
      releaseType="ga"
      # shellcheck disable=SC2034
      vendor="adoptium"
      apiURL=$(eval echo ${apiUrlTemplate})
      echo "Attempting to download GA release of boot JDK version ${VER} from ${apiURL}"
      curl -L "${apiURL}" | tar xpzf - --strip-components=1 -C "$bootDir"
    fi
  fi
}

function downloadWindowsBootJDK() {
      local ARCHITECTURE="${1}"
      local VER="${2}"
      local bootDir="${3}"
      # This is needed to convert x86-32 to x32 which is what the API uses
      export downloadArch
      case "$ARCHITECTURE" in
         "x86-32") downloadArch="x32";;
        "aarch64") downloadArch="x64";;
                *) downloadArch="$ARCHITECTURE";;
      esac
      releaseType="ga"
      vendor="eclipse"
      api="adoptium"
      apiUrlTemplate="https://api.\${api}.net/v3/binary/latest/\${VER}/\${releaseType}/windows/\${downloadArch}/jdk/hotspot/normal/\${vendor}"
      apiURL=$(eval echo ${apiUrlTemplate})
      echo "Downloading GA release of boot JDK version ${VER} from ${apiURL}"
      # make-adopt-build-farm.sh has 'set -e'. We need to disable that for
      # the fallback mechanism, as downloading of the GA binary might fail
      set +e
      wget -q "${apiURL}" -O openjdk.zip
      retVal=$?
      set -e
      if [ $retVal -ne 0 ]; then
        # We must be a JDK HEAD build for which no boot JDK exists other than
        # nightlies?
        echo "Downloading GA release of boot JDK version ${VER} failed."
        # shellcheck disable=SC2034
        releaseType="ea"
        # shellcheck disable=SC2034
        vendor="adoptium"
        apiURL=$(eval echo ${apiUrlTemplate})
        echo "Attempting to download EA release of boot JDK version ${VER} from ${apiURL}"
        set +e
        wget -q "${apiURL}" -O openjdk.zip
        retVal=$?
        set -e
        if [ $retVal -ne 0 ]; then
          # If no binaries are available then try from adoptopenjdk
          echo "Downloading Temurin release of boot JDK version ${VER} failed."
          # shellcheck disable=SC2034
          releaseType="ga"
          # shellcheck disable=SC2034
          vendor="adoptopenjdk"
          # shellcheck disable=SC2034
          api="adoptopenjdk"
          apiURL=$(eval echo ${apiUrlTemplate})
          echo "Attempting to download GA release of boot JDK version ${VER} from ${apiURL}"
          wget -q "${apiURL}" -O openjdk.zip
        fi
      fi
      unzip -q openjdk.zip
      mv "$(ls -d jdk*"${VER}"*)" "$bootDir"
}
