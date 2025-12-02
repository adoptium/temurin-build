#!/bin/sh
# ********************************************************************************
# Copyright (c) 2023 Contributors to the Eclipse Foundation
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

[ "$VERBOSE" = "true" ] && set -x
if [ $# -lt 3 ]; then
  echo "Usage: $0 file.json majorversion scm_ref"
  echo "e.g. $0 OpenJDK17_sbom.json 17 jdk-17.0.10+1_adopt"
  exit 1
fi
SBOMFILE="$1"
MAJORVERSION="$2"
EXPECTED_SCM_REF="$3"

GLIBC=$(   jq '.metadata.tools.components[] | select(.name|test("GLIBC"))    | .version' "$SBOMFILE" | tr -d \")
GCC=$(     jq '.metadata.tools.components[] | select(.name|test("GCC"))      | .version' "$SBOMFILE" | tr -d \")
BOOTJDK=$( jq '.metadata.tools.components[] | select(.name|test("BOOTJDK"))  | .version' "$SBOMFILE" | tr -d \")
ALSA=$(    jq '.metadata.tools.components[] | select(.name|test("ALSA"))     | .version' "$SBOMFILE" | tr -d \" | sed -e 's/^.*alsa-lib-//' -e 's/\.tar.bz2//')
FREETYPE=$(jq '.metadata.tools.components[] | select(.name|test("FreeType")) | .version' "$SBOMFILE" | tr -d \")
COMPILER=$(jq '.components[0].properties[] | select(.name|test("Build Tools Summary")).value' "$SBOMFILE" | sed -e 's/^.*Toolchain: //g' -e 's/\ *\*.*//g')
SCM_REF=$( jq '.components[0].properties[]  | select(.name|test("SCM Ref"))  | .value'   "$SBOMFILE" | tr -d \")

EXPECTED_COMPILER="gcc (GNU Compiler Collection)"
EXPECTED_GLIBC=""
EXPECTED_GCC=""
# [ "${MAJORVERSION}" = "17" ] && EXPECTED_GCC=10.3.0
EXPECTED_ALSA=""
#EXPECTED_FREETYPE=N.A # https://github.com/adoptium/temurin-build/issues/3493
#EXPECTED_FREETYPE=https://github.com/freetype/freetype/commit/86bc8a95056c97a810986434a3f268cbe67f2902
if echo "$SBOMFILE" | grep _solaris_; then
  EXPECTED_FREETYPE=2.4.9
  EXPECTED_COMPILER="solstudio (Oracle Solaris Studio)"
elif echo "$SBOMFILE" | grep _aix_; then
  if [ "$MAJORVERSION" -le 21 ]; then
    EXPECTED_COMPILER="xlc (IBM XL C/C++)"
  else
    EXPECTED_COMPILER="clang (clang/LLVM)"
  fi
  if [ "$MAJORVERSION" -lt 17 ]; then
    EXPECTED_FREETYPE=2.8.0
  else
    EXPECTED_FREETYPE=2.13.3 # Bundled version
  fi
elif echo "$SBOMFILE" | grep _alpine-linux_ > /dev/null; then
  EXPECTED_FREETYPE=2.11.1
  EXPECTED_ALSA=1.1.6
  EXPECTED_GCC=10.3.1
elif echo "$SBOMFILE" | grep _linux_; then
  
  if [ "$MAJORVERSION" -lt 20 ] && echo "$SBOMFILE" | grep x64 > /dev/null; then # CentOS6
    EXPECTED_GLIBC=2.12
    EXPECTED_FREETYPE=2.3.11
  elif echo "$SBOMFILE" | grep _arm_ > /dev/null; then # Ubuntu 16.04
    EXPECTED_GLIBC=2.23
    EXPECTED_FREETYPE=2.6.1
  else # CentOS7
    EXPECTED_GLIBC=2.17
    EXPECTED_FREETYPE=2.8.0
  fi
  [ "${MAJORVERSION}" = "8" ] && EXPECTED_GCC=7.5.0
  [ "${MAJORVERSION}" = "11" ] && EXPECTED_GCC=7.5.0
  [ "${MAJORVERSION}" = "17" ] && EXPECTED_GCC=10.3.0
  [ "${MAJORVERSION}" -ge 20 ] && EXPECTED_GCC=11.3.0 && EXPECTED_FREETYPE=Unknown
  [ "${MAJORVERSION}" -ge 25 ] && EXPECTED_GCC=14.2.0
  EXPECTED_ALSA=1.1.8
  if echo "$SBOMFILE" | grep _aarch64_ > /dev/null; then
     EXPECTED_ALSA=1.1.6 # Linux/aarch64 uses CentOS7.6 devkit, not 7.9
  fi
  if echo "$SBOMFILE" | grep _riscv64_ > /dev/null; then
    EXPECTED_GCC=14.2.0
    EXPECTED_GLIBC=2.27 # Fedora 28
    EXPECTED_ALSA=1.1.1
    [ "${MAJORVERSION}" -lt 20 ] && EXPECTED_FREETYPE=2.6.5
  fi
#elif echo $SBOMFILE | grep _mac_; then
#  EXPECTED_COMPILER="clang (clang/LLVM from Xcode 10.3)"
elif echo "$SBOMFILE" | grep 64_windows_; then
  EXPECTED_FREETYPE=2.8.1
  EXPECTED_COMPILER="microsoft (Microsoft Visual Studio 2022)"
  if [ "${MAJORVERSION}" = "11" ] || [ "${MAJORVERSION}" = "17" ]; then
    EXPECTED_FREETYPE=2.13.3 # Bundled version
  fi
elif echo "$SBOMFILE" | grep _x86-32_windows_; then
  EXPECTED_FREETYPE=2.13.3 # Bundled version
  EXPECTED_COMPILER="microsoft (Microsoft Visual Studio 2022)"
  if [ "${MAJORVERSION}" = "8"  ]; then
    EXPECTED_FREETYPE=2.5.3
  fi
elif echo "$SBOMFILE" | grep _mac_; then
  # NOTE: mac/x64 native builds >=11 were using "clang (clang/LLVM from Xcode 10.3)"
  EXPECTED_FREETYPE=2.13.3 # Bundled version
  EXPECTED_COMPILER="clang (clang/LLVM from Xcode 15.2)"
  # shellcheck disable=SC2166
  if [ "${MAJORVERSION}" = "8" ] && echo "$SBOMFILE" | grep _x64_; then
    EXPECTED_COMPILER="clang (clang/LLVM)"
    EXPECTED_FREETYPE=2.9.1
  fi
fi

[ "${MAJORVERSION}" -ge 20 ] && EXPECTED_FREETYPE=2.13.3 # Bundled version

RC=0

# Skip SCM check if EXPECTED_SCM_REF parameter is empty
if [ -n "${EXPECTED_SCM_REF}" ]; then
  [ "${EXPECTED_SCM_REF}" != "${SCM_REF}" ] && echo "ERROR: SCM_REF not ${EXPECTED_SCM_REF} (SBOM has ${SCM_REF})" && RC=1 
fi
if echo "$SBOMFILE" | grep 'linux_'; then
	[ "${GLIBC}"      != "$EXPECTED_GLIBC"   ] && echo "ERROR: GLIBC version not ${EXPECTED_GLIBC} (SBOM has ${GLIBC})" && RC=1
	[ "${GCC}"        != "$EXPECTED_GCC"     ] && echo "ERROR: GCC version not ${EXPECTED_GCC} (SBOM has ${GCC})"     && RC=1
fi
echo "BOOTJDK is ${BOOTJDK}"
[ "${COMPILER}"   != "$EXPECTED_COMPILER" ] && echo "ERROR: Compiler version not ${EXPECTED_COMPILER} (SBOM has ${COMPILER})"   && RC=1
[ "${ALSA}"       != "$EXPECTED_ALSA"     ] && echo "NOTE: ALSA version not ${EXPECTED_ALSA} (SBOM has ${ALSA}) - ignoring because ALSA version is determined by devkit now"  # && RC=1
# Freetype versions are inconsistent at present - see build#3484
#[ "${FREETYPE}"   != "$EXPECTED_FREETYPE" ] && echo "ERROR: FreeType version not ${EXPECTED_FREETYPE} (SBOM has ${FREETYPE})"   && RC=1

# shellcheck disable=SC2086
[ "${FREETYPE}"   != "$EXPECTED_FREETYPE" ] && echo "ERROR: FreeType version not ${EXPECTED_FREETYPE} (SBOM has ${FREETYPE})"   && RC=1

echo "FREETYPE is ${FREETYPE}"
# shellcheck disable=SC3037
echo -n "Checking for JDK source SHA validity: "
GITURL=$(jq '.components[].properties[] | select(.name|test("OpenJDK Source Commit")) | .value' "$1" | tr -d \" | uniq)
GITREPO=$(echo "$GITURL" | cut -d/ -f1-5)
GITSHA=$( echo "$GITURL" | cut -d/ -f7)
if [ -z "${EXPECTED_SCM_REF}" ]; then
  if ! curl --silent --fail -I "$GITURL" > /dev/null; then
    echo "ERROR: git sha of source commit not found"
    echo "GITREPO: ${GITREPO}"
    echo "GITSHA: ${GITSHA}"
    RC=1
  fi
else
  if ! git ls-remote "${GITREPO}" | grep "${GITSHA}"; then
    echo "ERROR: git sha of source repo not found"
    echo "GITREPO: ${GITREPO}"
    echo "GITSHA: ${GITSHA}"
    RC=1
  fi
fi

# shellcheck disable=SC3037
if [ -n "${EXPECTED_SCM_REF}" ]; then
  echo -n "Checking for temurin-build SHA validity: "
  GITSHA=$(jq '.components[].properties[] | select(.name|test("Temurin Build Ref")) | .value' "$1" | tr -d \" | uniq)
  GITREPO=$(echo "$GITSHA" | cut -d/ -f1-5)
  GITSHA=$(echo  "$GITSHA" | cut -d/ -f7)
  echo "Checking for temurin-build SHA $GITSHA in ${GITREPO}"

  if ! git ls-remote "${GITREPO}" | grep "${GITSHA}"; then
     echo "WARNING: temurin-build SHA check failed. This can happen if it was not a tagged level."
     if echo "$1" | grep '[0-9][0-9]-[0-9][0-9]-[0-9][0-9]-[0-9][0-9]' 2>/dev/null; then
       echo "Ignoring return code as filename looks like a nightly"
     else
       echo "This can also happen with a branch being used and not a tag as we do for GAs so not failing."
       echo "Note: As this is a warning message this will not cause a non-zero return code by itself."
       # RC=1
     fi
  fi
else
  echo "The SCM_REF argument was set to an empty string; skipping SHA check."
fi

if [ "$RC" != "0" ]; then
   echo "ERROR: Overall return code from validateSBOMcontent.sh is non-zero - something failed validation."
fi
exit $RC
