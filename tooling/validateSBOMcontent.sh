#!/bin/sh
[ "$VERBOSE" = "true" ] && set -x
if [ $# -lt 3 ]; then
  echo "Usage: $0 file.json majorversion fullversion"
  echo "e.g. $0 OpenJDK17_sbom.json 17 17.0.8"
  exit 1
fi
SBOMFILE="$1"
MAJORVERSION="$2"
#FULLVERSION="$3"

GLIBC=$(jq '.metadata.tools[] | select(.name|test("GLIBC")) | .version'           "$1" | tr -d \")
GCC=$(jq '.metadata.tools[] | select(.name|test("GCC")) | .version'               "$1" | tr -d \")
BOOTJDK=$(jq '.metadata.tools[] | select(.name|test("BOOTJDK")) | .version'       "$1"  | tr -d \")
ALSA=$(jq '.metadata.tools[] | select(.name|test("ALSA")) | .version'             "$1" | tr -d \" | sed -e 's/^.*alsa-lib-//' -e 's/\.tar.bz2//')
FREETYPE=$(jq '.metadata.tools[] | select(.name|test("FreeType")) | .version'     "$1"  | tr -d \")
FREEMARKER=$(jq '.metadata.tools[] | select(.name|test("FreeMarker")) | .version' "$1"  | tr -d \")
COMPILER=$(jq '.components[0].properties[] | select(.name|test("Build Tools Summary")).value' "$SBOMFILE" | sed -e 's/^.*Toolchain: //g' -e 's/\ *\*.*//g')

EXPECTED_COMPILER="gcc (GNU Compiler Collection)"
EXPECTED_GLIBC=""
EXPECTED_GCC=""
# [ "${MAJORVERSION}" = "17" ] && EXPECTED_GCC=10.3.0
EXPECTED_ALSA=N.A
#EXPECTED_FREETYPE=N.A # https://github.com/adoptium/temurin-build/issues/3493
#EXPECTED_FREETYPE=https://github.com/freetype/freetype/commit/86bc8a95056c97a810986434a3f268cbe67f2902
if echo "$SBOMFILE" | grep _solaris_; then
  #EXPECTED_FREETYPE=N.A
  EXPECTED_COMPILER="solstudio (Oracle Solaris Studio)"
elif echo "$SBOMFILE" | grep _aix_; then
  EXPECTED_COMPILER="xlc (IBM XL C/C++)"
elif echo "$SBOMFILE" | grep _alpine-linux_ > /dev/null; then
  #EXPECTED_FREETYPE=N.A
  EXPECTED_ALSA=1.1.6
  EXPECTED_GCC=10.3.1
elif echo "$SBOMFILE" | grep _linux_; then
  if [ "$MAJORVERSION" -lt 20 ] && echo "$SBOMFILE" | grep x64 > /dev/null; then
    EXPECTED_GLIBC=2.12
  elif echo "$SBOMFILE" | grep _arm_ > /dev/null; then
    EXPECTED_GLIBC=2.23
  else
    EXPECTED_GLIBC=2.17
  fi
  [ "${MAJORVERSION}" = "8" ] && EXPECTED_GCC=7.5.0
  [ "${MAJORVERSION}" = "11" ] && EXPECTED_GCC=7.5.0
  [ "${MAJORVERSION}" = "17" ] && EXPECTED_GCC=10.3.0
  [ "${MAJORVERSION}" -ge 20 ] && EXPECTED_GCC=11.2.0
  EXPECTED_ALSA=1.1.6
  #EXPECTED_FREETYPE=N.A
#elif echo $SBOMFILE | grep _mac_; then
#  EXPECTED_COMPILER="clang (clang/LLVM from Xcode 10.3)"
elif echo "$SBOMFILE" | grep _x64_windows_; then
  if [ "${MAJORVERSION}" = "8" ]; then
    EXPECTED_COMPILER="microsoft (Microsoft Visual Studio 2017 - CURRENTLY NOT WORKING)"
    #EXPECTED_FREETYPE="https://github.com/freetype/freetype/commit/ec8853cd18e1a0c275372769bdad37a79550ed66"
  elif [ "${MAJORVERSION}" -ge 20 ]; then
    EXPECTED_COMPILER="microsoft (Microsoft Visual Studio 2022)"
  else
    EXPECTED_COMPILER="microsoft (Microsoft Visual Studio 2019)"
  fi
elif echo "$SBOMFILE" | grep _x86-32_windows_; then
  if [ "${MAJORVERSION}" = "8"  ]; then
    EXPECTED_COMPILER="microsoft (Microsoft Visual Studio 2013)"
    #EXPECTED_FREETYPE="https://github.com/freetype/freetype/commit/ec8853cd18e1a0c275372769bdad37a79550ed66"
  elif [ "${MAJORVERSION}" = "11" ]; then
    EXPECTED_COMPILER="microsoft (Microsoft Visual Studio 2017)"
  else
    EXPECTED_COMPILER="microsoft (Microsoft Visual Studio 2019)"
  fi
elif echo "$SBOMFILE" | grep _mac_; then
  # NOTE: mac/x64 native builds >=11 were using "clang (clang/LLVM from Xcode 10.3)"
  EXPECTED_COMPILER="clang (clang/LLVM from Xcode 12.4)"
  # shellcheck disable=SC2166
  if [ "${MAJORVERSION}" = "8" -o "${MAJORVERSION}" = "11" ] && echo "$SBOMFILE" | grep _x64_; then
    EXPECTED_COMPILER="clang (clang/LLVM)"
#    EXPECTED_FREETYPE="https://github.com/freetype/freetype/commit/ec8853cd18e1a0c275372769bdad37a79550ed66"
  fi
fi

EXPECTED_FREEMARKER=N.A
RC=0
if echo "$SBOMFILE" | grep 'linux_'; then
	[ "${GLIBC}"      != "$EXPECTED_GLIBC"   ] && echo "ERROR: GLIBC version not ${EXPECTED_GLIBC} (SBOM has ${GLIBC})" && RC=1
	[ "${GCC}"        != "$EXPECTED_GCC"     ] && echo "ERROR: GCC version not ${EXPECTED_GCC} (SBOM has ${GCC})"     && RC=1
fi
echo "BOOTJDK is ${BOOTJDK}"
[ "${COMPILER}"   != "$EXPECTED_COMPILER" ] && echo "ERROR: Compiler version not ${EXPECTED_COMPILER} (SBOM has ${COMPILER})"   && RC=1
[ "${ALSA}"       != "$EXPECTED_ALSA"     ] && echo "ERROR: ALSA version not ${EXPECTED_ALSA} (SBOM has ${ALSA})"   && RC=1
# Freetype versions are inconsistent at present - see build#3484
#[ "${FREETYPE}"   != "$EXPECTED_FREETYPE" ] && echo "ERROR: FreeType version not ${EXPECTED_FREETYPE} (SBOM has ${FREETYPE})"   && RC=1

# shellcheck disable=SC2086
[ -n "$(echo $FREETYPE | tr -d '[0-9]\.')" ] && echo "ERROR: FreeType version not a valid number (SBOM has ${FREETYPE})"   && RC=1
echo "FREETYPE is ${FREETYPE}"
[ "${FREEMARKER}" != "$EXPECTED_FREEMARKER"  ] && echo "ERROR: Freemarker version not ${EXPECTED_FREEMARKER} (SBOM has ${FREEMARKER})"   && RC=1
# shellcheck disable=SC3037
echo -n "Checking for JDK source SHA validity: "
GITSHA=$(jq '.components[].properties[] | select(.name|test("OpenJDK Source Commit")) | .value' "$1" | tr -d \")
GITREPO=$(echo "$GITSHA" | cut -d/ -f1-5)
GITSHA=$( echo "$GITSHA" | cut -d/ -f7)
if ! git ls-remote "${GITREPO}" | grep "${GITSHA}"; then
  echo "ERROR: git sha of source repo not found"
  RC=1
fi

# shellcheck disable=SC3037
echo -n "Checking for temurin-build SHA validity: "
GITSHA=$(jq '.components[].properties[] | select(.name|test("Temurin Build Ref")) | .value' "$1" | tr -d \")
GITREPO=$(echo "$GITSHA" | cut -d/ -f1-5)
GITSHA=$(echo  "$GITSHA" | cut -d/ -f7)
echo "Checking for temurin-build SHA $GITSHA"
if ! git ls-remote "${GITREPO}" | grep "${GITSHA}"; then
   echo "WARNING: temurin-build SHA check failed. This can happen if it was not a tagged level"
   if echo "$1" | grep '[0-9][0-9]-[0-9][0-9]-[0-9][0-9]-[0-9][0-9]' 2>/dev/null; then
     echo "Ignoring return code as filename looks like a nightly"
   else
     echo "This can also happen with a branch being used and not a tag as we do for GAs so not failing"
     echo "Note: As this is a warning message this will not cause a non-zero return code by itself"
     # RC=1
   fi
fi

if [ "$RC" != "0" ]; then
   echo "ERROR: Overall return code from validateSBOMcontent.sh is non-zero - something failed validation"
fi
exit $RC
