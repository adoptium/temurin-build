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
    echo "WINDOWS DOWNLOAD for ${2}"
    local ARCHITECTURE="${1}"
    local VER="${2}"
    local bootDir="${3}"

    # ── normalise architecture name for the API ──────────────────────────────
    case "${ARCHITECTURE}" in
        "x86-32") downloadArch="x32" ;;
        "aarch64") downloadArch="x64" ;;
        *)         downloadArch="${ARCHITECTURE}" ;;
    esac

    # Switch Windows To Use CURL rather than wget
    _curl_get() {
        local url="$1"
        rm -f openjdk.zip                         # ← ensure no stale file
        set +e
        curl -sSfL --retry 3 -o openjdk.zip "${url}"
        local rv=$?
        if [ $rv -eq 0 ]; then
            unzip -tq openjdk.zip >/dev/null 2>&1
            rv=$?                                # 0 → looks like a zip
        fi
        set -e
        return "${rv}"
    }



    # 1) Download Boot JDK GA / Temurin (eclipse)
    releaseType="ga"
    vendor="eclipse"
    api="adoptium"
    apiURL="https://api.${api}.net/v3/binary/latest/${VER}/${releaseType}/windows/${downloadArch}/jdk/hotspot/normal/${vendor}"
    echo "Downloading GA release of boot JDK version ${VER} from ${apiURL}"

    if ! _curl_get "${apiURL}"; then
        echo "Downloading GA release failed."

        # 2) Download Boot JDK EA / Temurin (adoptium)
        releaseType="ea"
        vendor="adoptium"
        apiURL="https://api.${api}.net/v3/binary/latest/${VER}/${releaseType}/windows/${downloadArch}/jdk/hotspot/normal/${vendor}"
        echo "Attempting EA release from ${apiURL}"

        if ! _curl_get "${apiURL}"; then
            echo "Downloading EA release failed."

            # 3) Download Boot JDK GA / legacy AdoptOpenJDK
            releaseType="ga"
            vendor="adoptopenjdk"
            api="adoptopenjdk"
            apiURL="https://api.${api}.net/v3/binary/latest/${VER}/${releaseType}/windows/${downloadArch}/jdk/hotspot/normal/${vendor}"
            echo "Attempting AdoptOpenJDK GA release from ${apiURL}"

            if ! _curl_get "${apiURL}"; then
                echo "All API-based downloads failed. Attempting fallback direct URL…"

                # 4) BOOT JDK Download Fallback When None Of The Above Work
                case "${VER}" in
                    10)
                        fallbackURL="https://github.com/AdoptOpenJDK/openjdk10-releases/releases/download/jdk-10.0.2%2B13/OpenJDK10_x64_Win_jdk-10.0.2+13.zip"
                        ;;
                    11)
                        fallbackURL="https://github.com/adoptium/temurin11-binaries/releases/download/jdk-11.0.27%2B6/OpenJDK11U-jdk_x64_windows_hotspot_11.0.27_6.zip"
                        ;;
                    17)
                        fallbackURL="https://github.com/adoptium/temurin17-binaries/releases/download/jdk-17.0.9%2B9.1/OpenJDK17U-jdk_x64_windows_hotspot_17.0.9_9.zip"
                        ;;
                    20)
                        fallbackURL="https://github.com/adoptium/temurin20-binaries/releases/download/jdk-20.0.2%2B9/OpenJDK20U-jdk_x64_windows_hotspot_20.0.2_9.zip"
                        ;;
                    25)
                        fallbackURL="https://github.com/adoptium/temurin25-binaries/releases/download/jdk-25%2B20-ea-beta/OpenJDK-jdk_x64_windows_hotspot_25_20-ea.zip"
                        ;;
                    *)
                        echo "No fallback URL defined for VER=${VER}. Exiting."
                        exit 1
                        ;;
                esac

                if ! _curl_get "${fallbackURL}"; then
                    echo "Fallback download failed for ${fallbackURL}"
                    exit 1
                fi
            fi
        fi
    fi
    mkdir -p "${bootDir}"
    unzip -q openjdk.zip -d "${bootDir}"
    # If the ZIP contained a wrapper directory (e.g. jdk-25.0.0+29),
    # flatten it so $bootDir has bin/, lib/ … directly beneath it.
    inner="$(find "${bootDir}" -mindepth 1 -maxdepth 1 -type d -name "jdk*" -print -quit)"
    if [ -n "${inner}" ] && [ "${inner}" != "${bootDir}" ]; then
      shopt -s dotglob
      mv "${inner}"/* "${bootDir}"
      rmdir "${inner}"
      shopt -u dotglob
    fi
}
