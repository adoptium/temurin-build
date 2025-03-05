#!/bin/bash
# shellcheck disable=SC2155,SC1091,SC2196,SC2235
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

################################################################################
#
# This script prepares the workspace to build (Adoptium) OpenJDK.
# See the configureWorkspace function for details
# It is sourced by build.sh
#
################################################################################

set -eu
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=sbin/common/constants.sh
source "$SCRIPT_DIR/common/constants.sh"

# shellcheck source=sbin/common/common.sh
source "$SCRIPT_DIR/common/common.sh"

# Set default versions for 3 libraries that OpenJDK relies on to build

ALSA_LIB_VERSION=${ALSA_LIB_VERSION:-1.1.6}
ALSA_LIB_CHECKSUM=${ALSA_LIB_CHECKSUM:-5f2cd274b272cae0d0d111e8a9e363f08783329157e8dd68b3de0c096de6d724}
ALSA_LIB_GPGKEYID=${ALSA_LIB_GPGKEYID:-A6E59C91}
FREETYPE_FONT_SHARED_OBJECT_FILENAME="libfreetype.so*"

# sha256 of https://github.com/adoptium/devkit-binaries/releases/tag/vs2022_redist_14.40.33807_10.0.26100.1742
WINDOWS_REDIST_CHECKSUM="ac6060f5f8a952f59faef20e53d124c2c267264109f3f6fabeb2b7aefb3e3c62"

copyFromDir() {
  echo "Copying OpenJDK source from  ${BUILD_CONFIG[OPENJDK_LOCAL_SOURCE_ARCHIVE_ABSPATH]} to $(pwd)/${BUILD_CONFIG[OPENJDK_SOURCE_DIR]} to be built"
  # We really do not want to use .git for dirs, as we expect user have them set up, ignoring them
  local files=$(find "${BUILD_CONFIG[OPENJDK_LOCAL_SOURCE_ARCHIVE_ABSPATH]}" -maxdepth 1 -mindepth 1 | grep -v -e "/workspace$" -e "/build$" -e "/.git" -e -"/build/")
  # SC2086 (info): Double quote to prevent globbing and word splitting.
  # globbing is intentional here
  # shellcheck disable=SC2086
  cp -rf $files "./${BUILD_CONFIG[OPENJDK_SOURCE_DIR]}/"
}

# this is workarounding --strip-components 1 missing on gnu tar
# it requires  absolute tar-filepath as it changes dir and is hardcoded to one
# similar approach can be used also for zip in future
# warning! this method do not merge if (parts of!) destination exists.
unpackGnuAbsPathWithStrip1Component() {
  local tmp=$(mktemp -d)
  pushd "$tmp" > /dev/null
    "$@"
  popd  > /dev/null
  mv "$tmp"/*/* .
  mv "$tmp"/*/.* . || echo "no hidden files in tarball"
  rmdir "$tmp"/*
  rmdir "$tmp"
}

untarGnuAbsPathWithStrip1Component() {
  unpackGnuAbsPathWithStrip1Component tar -xf "$@"
}

unzipGnuAbsPathWithStrip1Component() {
  unpackGnuAbsPathWithStrip1Component unzip "$@"
}

unpackFromArchive() {
  echo "Extracting OpenJDK source tarball ${BUILD_CONFIG[OPENJDK_LOCAL_SOURCE_ARCHIVE_ABSPATH]} to $(pwd)/${BUILD_CONFIG[OPENJDK_SOURCE_DIR]} to build the binary"
  # If the tarball contains .git files, they should be ignored later
  pushd "./${BUILD_CONFIG[OPENJDK_SOURCE_DIR]}"
    if [ "${BUILD_CONFIG[OPENJDK_LOCAL_SOURCE_ARCHIVE_ABSPATH]: -4}" == ".zip" ] ; then
        echo "Source zip unpacked as if it contains exactly one directory"
        unzipGnuAbsPathWithStrip1Component "${BUILD_CONFIG[OPENJDK_LOCAL_SOURCE_ARCHIVE_ABSPATH]}"
    else
      local topLevelItems=$(tar --exclude='*/*' -tf  "${BUILD_CONFIG[OPENJDK_LOCAL_SOURCE_ARCHIVE_ABSPATH]}" | grep "/$" -c) || local topLevelItems=1
      if [ "$topLevelItems" -eq "1" ] ; then
        echo "Source tarball contains exactly one directory"
        untarGnuAbsPathWithStrip1Component "${BUILD_CONFIG[OPENJDK_LOCAL_SOURCE_ARCHIVE_ABSPATH]}"
      else
        echo "Source tarball does not contain a top level directory"
        tar -xf "${BUILD_CONFIG[OPENJDK_LOCAL_SOURCE_ARCHIVE_ABSPATH]}"
      fi
    fi
    rm -rf "build"
  popd
}

copyFromDirOrUnpackFromArchive() {
  echo "Cleaning the copy of OpenJDK source repository from $(pwd)/${BUILD_CONFIG[OPENJDK_SOURCE_DIR]} and replacing with a fresh copy in 10 seconds..."
  verboseSleep	 10
  rm -rf "./${BUILD_CONFIG[OPENJDK_SOURCE_DIR]}"
  mkdir  "./${BUILD_CONFIG[OPENJDK_SOURCE_DIR]}"
  # Note that we are not persisting the build directory
  if [ -d "${BUILD_CONFIG[OPENJDK_LOCAL_SOURCE_ARCHIVE_ABSPATH]}" ] ; then
    copyFromDir
  elif [ -f "${BUILD_CONFIG[OPENJDK_LOCAL_SOURCE_ARCHIVE_ABSPATH]}" ] ; then
    unpackFromArchive
  else
    echo "${BUILD_CONFIG[OPENJDK_LOCAL_SOURCE_ARCHIVE_ABSPATH]} is not a directory or a file "
    exit 1
  fi
}

# Create a new clone or update the existing clone of the OpenJDK source repo
# TODO refactor this for Single Responsibility Principle (SRP)
checkoutAndCloneOpenJDKGitRepo() {

  cd "${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[WORKING_DIR]}"

  # Check that we have a git repo, we assume that it is a repo that contains openjdk source
  if [ -d "${BUILD_CONFIG[OPENJDK_SOURCE_DIR]}/.git" ] && [ "${BUILD_CONFIG[OPENJDK_LOCAL_SOURCE_ARCHIVE]}" == "false" ]; then
    set +e
    git --git-dir "${BUILD_CONFIG[OPENJDK_SOURCE_DIR]}/.git" remote -v
    echo "${BUILD_CONFIG[OPENJDK_CORE_VERSION]}"

    # Ensure cached origin fetch remote repo is correct version and repo (eg.jdk11u, or jdk), remember "jdk" sub-string of jdk11u hence grep with "\s"
    # eg. origin https://github.com/adoptium/openjdk-jdk11u (fetch)
    # eg. origin https://github.com/adoptium/openjdk-jdk (fetch)
    # eg. origin git@github.com:adoptium/openjdk-jdk.git (fetch)
    # eg. origin https://github.com/alibaba/dragonwell8.git (fetch)
    # eg. origin https://github.com/feilongjiang/bishengjdk-11-mirror.git (fetch)
    if [ "${BUILD_CONFIG[BUILD_VARIANT]}" == "${BUILD_VARIANT_DRAGONWELL}" ] || [ "${BUILD_CONFIG[BUILD_VARIANT]}" == "${BUILD_VARIANT_BISHENG}" ]; then
      git --git-dir "${BUILD_CONFIG[OPENJDK_SOURCE_DIR]}/.git" remote -v | grep "origin.*fetch" | egrep "${BUILD_CONFIG[REPOSITORY]}.git|${BUILD_CONFIG[REPOSITORY]}\s"
    else
      git --git-dir "${BUILD_CONFIG[OPENJDK_SOURCE_DIR]}/.git" remote -v | grep "origin.*fetch" | grep "${BUILD_CONFIG[OPENJDK_CORE_VERSION]}" | egrep "${BUILD_CONFIG[REPOSITORY]}.git|${BUILD_CONFIG[REPOSITORY]}\s"
    fi
    local isValidGitRepo=$?
    set -e

    # If the local copy of the git source repo is valid then we reset appropriately
    if [ "${isValidGitRepo}" == "0" ]; then
      cd "${BUILD_CONFIG[OPENJDK_SOURCE_DIR]}" || return
      echo "Resetting the git openjdk source repository at $PWD in 10 seconds..."
      verboseSleep 10
      echo "Pulling latest changes from git openjdk source repository"
    elif [ "${BUILD_CONFIG[CLEAN_GIT_REPO]}" == "true" ]; then
      echo "Removing current git repo as it is the wrong type"
      rm -rf "${BUILD_CONFIG[WORKSPACE_DIR]:?}/${BUILD_CONFIG[WORKING_DIR]}/${BUILD_CONFIG[OPENJDK_SOURCE_DIR]}"
      cloneOpenJDKGitRepo
    else
      echo "Incorrect Source Code for ${BUILD_CONFIG[OPENJDK_FOREST_NAME]}.  This is an error, please check what is in $PWD and manually remove, exiting..."
      echo "If this is inside a docker you can purge the existing source by passing --clean-docker-build"
      exit 1
    fi
  elif [ "${BUILD_CONFIG[OPENJDK_LOCAL_SOURCE_ARCHIVE]}" == "true" ]; then
    copyFromDirOrUnpackFromArchive
  elif [ ! -d "${BUILD_CONFIG[OPENJDK_SOURCE_DIR]}/.git" ]; then
    echo "Could not find a valid openjdk git repository at $(pwd)/${BUILD_CONFIG[OPENJDK_SOURCE_DIR]} so re-cloning the source to openjdk"
    rm -rf "${BUILD_CONFIG[WORKSPACE_DIR]:?}/${BUILD_CONFIG[WORKING_DIR]}/${BUILD_CONFIG[OPENJDK_SOURCE_DIR]}"
    cloneOpenJDKGitRepo
  fi

  checkoutRequiredCodeToBuild
  # shellcheck disable=SC2086
  if [ $checkoutRc -ne 0 ]; then
    echo "RETRYWARNING: Checkout required source failed, cleaning workspace and retrying..."
    cd "${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[WORKING_DIR]}"
    rm -rf "${BUILD_CONFIG[WORKSPACE_DIR]:?}/${BUILD_CONFIG[WORKING_DIR]}/${BUILD_CONFIG[OPENJDK_SOURCE_DIR]}"
    cloneOpenJDKGitRepo
    checkoutRequiredCodeToBuild
    if [ $checkoutRc -ne 0 ]; then
      echo "RETRYWARNING: Checkout failed on clean workspace retry, failing job..."
      exit 1
    fi
  fi

  if [[ "${BUILD_CONFIG[BUILD_VARIANT]}" == "${BUILD_VARIANT_TEMURIN}" ]]; then
    # Verify Adoptium patches tag is being built, otherwise we may be accidently just building "raw" OpenJDK
    if [ ! -f "${TEMURIN_MARKER_FILE}" ] && [ "${BUILD_CONFIG[DISABLE_ADOPT_BRANCH_SAFETY]}" == "false" ]; then
      echo "${TEMURIN_MARKER_FILE} marker file not found in fetched source to be built, this may mean the wrong SCMReference build parameter has been specified. Ensure the correct Temurin patch release tag is specified, eg.for build jdk-11.0.4+10, it would be jdk-11.0.4+10_adopt"
      exit 1
    fi
  fi

  if [ "${BUILD_CONFIG[OPENJDK_LOCAL_SOURCE_ARCHIVE]}" == "false" ]; then
    git clean -ffdx
  fi
  updateOpenj9Sources

  createSourceTagFile

  cd "${BUILD_CONFIG[WORKSPACE_DIR]}"
}

# Checkout the required code to build from the given cached git repo
# Set checkoutRc to result so we can retry
checkoutRequiredCodeToBuild() {

  if [ "${BUILD_CONFIG[OPENJDK_LOCAL_SOURCE_ARCHIVE]}" == "true" ]; then
    echo "Skipping checkoutRequiredCodeToBuild - local directory under processing:"
    echo "  workspace = ${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[WORKING_DIR]}/${BUILD_CONFIG[OPENJDK_SOURCE_DIR]}"
    echo "  BUILD_VARIANT = ${BUILD_CONFIG[BUILD_VARIANT]}"
    echo "  TAG = ${BUILD_CONFIG[TAG]} - Used only in name, if at all"
    echo "  BRANCH = ${BUILD_CONFIG[BRANCH]} - UNUSED!"
    checkoutRc=0
    return
  fi

  checkoutRc=1

  cd "${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[WORKING_DIR]}/${BUILD_CONFIG[OPENJDK_SOURCE_DIR]}"

  echo "checkoutRequiredCodeToBuild:"
  echo "  workspace = ${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[WORKING_DIR]}/${BUILD_CONFIG[OPENJDK_SOURCE_DIR]}"
  echo "  BUILD_VARIANT = ${BUILD_CONFIG[BUILD_VARIANT]}"
  echo "  TAG = ${BUILD_CONFIG[TAG]}"
  echo "  BRANCH = ${BUILD_CONFIG[BRANCH]}"

  # Ensure commands don't abort shell
  set +e
  local rc=0

  local tag="${BUILD_CONFIG[TAG]}"
  local sha=""
  if [ "${BUILD_CONFIG[BUILD_VARIANT]}" != "${BUILD_VARIANT_OPENJ9}" ]; then
    git fetch --tags || rc=$?
    if [ $rc -eq 0 ]; then
      if git show-ref -q --verify "refs/tags/${BUILD_CONFIG[BRANCH]}"; then
        echo "looks like the scm ref given is a valid tag, so treat it as a tag"
        tag="${BUILD_CONFIG[BRANCH]}"
        BUILD_CONFIG[TAG]="${tag}"
        BUILD_CONFIG[SHALLOW_CLONE_OPTION]=""
      elif git cat-file commit "${BUILD_CONFIG[BRANCH]}"; then
        echo "look like the scm ref given is a valid sha, so treat it as a sha"
        sha="${BUILD_CONFIG[BRANCH]}"
        BUILD_CONFIG[SHALLOW_CLONE_OPTION]=""
      fi
    else
      echo "Failed cmd: git fetch --tags"
    fi
  fi

  if [ $rc -eq 0 ]; then
    if [ "${tag}" ]; then
      echo "Checking out tag ${tag}"
      git fetch origin "refs/tags/${tag}:refs/tags/${tag}" || rc=$?
      if [ $rc -eq 0 ]; then
        git checkout "${tag}" || rc=$?
        if [ $rc -eq 0 ]; then
          git reset --hard || rc=$?
          if [ $rc -eq 0 ]; then
            echo "Checked out tag ${tag}"
          else
            echo "Failed cmd: git reset --hard"
          fi
        else
          echo "Failed cmd: git checkout \"${tag}\""
        fi
      else
        echo "Failed cmd: git fetch origin \"refs/tags/${tag}:refs/tags/${tag}\""
      fi
    elif [ "$sha" ]; then
      echo "Checking out sha ${sha}"
      git checkout "${sha}" || rc=$?
      if [ $rc -eq 0 ]; then
        git reset --hard || rc=$?
        if [ $rc -eq 0 ]; then
          echo "Checked out sha ${sha}"
        else
          echo "Failed cmd reset sha: git reset --hard"
        fi
      else
        echo "Failed cmd: git checkout \"${sha}\""
      fi
    else
      git remote set-branches --add origin "${BUILD_CONFIG[BRANCH]}" || rc=$?
      if [ $rc -eq 0 ]; then
        # shellcheck disable=SC2086
        git fetch --all ${BUILD_CONFIG[SHALLOW_CLONE_OPTION]} || rc=$?
        if [ $rc -eq 0 ]; then
          git reset --hard "origin/${BUILD_CONFIG[BRANCH]}" || rc=$?
          if [ $rc -eq 0 ]; then
            echo "Checked out origin/${BUILD_CONFIG[BRANCH]}"
          else
            echo "Failed cmd: git reset --hard \"origin/${BUILD_CONFIG[BRANCH]}\""
          fi
        else
          echo "Failed cmd: git fetch --all ${BUILD_CONFIG[SHALLOW_CLONE_OPTION]}"
        fi
      else
        echo "Failed cmd: git remote set-branches --add origin \"${BUILD_CONFIG[BRANCH]}\""
      fi
    fi
  fi

  # Get the latest tag to stick in the scmref metadata, using the build config tag if it exists
  local scmrefPath="${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[TARGET_DIR]}/metadata/scmref.txt"

  if [ $rc -eq 0 ]; then

    if [ -z "${BUILD_CONFIG[TAG]}" ]; then
      # If SCM_REF is not set
      echo "INFO: Extracting latest tag for the scmref using git describe since no tag is set in the build config..."

      local describeReturn=0
      git describe || describeReturn=$?

      if [ $describeReturn -eq 0 ]; then
        # Tag will be something similar to jdk-11.0.8+8_adopt-160-g824f8474f5
        # jdk-11.0.8+8_adopt = TAGNAME
        # 160 = NUMBER OF COMMITS ON TOP OF THE ORIGINAL TAGGED OBJECT
        # g824f8474f5 = "g" + THE SHORT HASH OF THE MOST RECENT COMMIT
        echo "SUCCESS: TAG FOUND! Exporting to $scmrefPath..."
        git describe > "$scmrefPath"

      else
        # No annotated tags can describe the latest commit
        echo "WARNING: git describe FAILED. There is likely additional error output above (exit code was $describeReturn). Trying again using git describe --tags to match a lightweight (non-annotated) tag"
        local describeReturn=0
        git describe --tags || describeReturn=$?

        if [ $describeReturn -eq 0 ]; then
          # Will match commits that are not named
          echo "SUCCESS: TAG FOUND USING --tags! Exporting to $scmrefPath..."
          git describe --tags > "$scmrefPath"
        else
          # Use the shortend commit hash as a scmref if all else fails
          echo "FINAL WARNING: git describe --tags FAILED. There is likely additional error output above (exit code was $describeReturn). Exporting the abbreviated commit hash using git describe --always as a failsafe to $scmrefPath"
          git describe --always | tee "$scmrefPath"
        fi

      fi

    else
      # SCM_REF is set. Use it over the git describe output
      echo "SUCCESS: BUILD_CONFIG[TAG] is set. Exporting to $scmrefPath..."
      echo -n "${BUILD_CONFIG[TAG]}" | tee "$scmrefPath"
    fi

  else
    # Previous steps failed so don't bother trying to get the tags
    echo "WARNING: Cannot get tag due to previous failures. $scmrefPath will NOT be created!"
  fi

  # Restore command failure shell abort
  set -e

  if [ $rc -eq 0 ]; then
    echo "checkoutRequiredCodeToBuild succeeded"
  else
    echo "checkoutRequiredCodeToBuild failed rc=$rc"
  fi

  checkoutRc=$rc
}

# Set the git clone arguments
setGitCloneArguments() {
  cd "${BUILD_CONFIG[WORKSPACE_DIR]}"
  local git_remote_repo_address="${BUILD_CONFIG[REPOSITORY]}.git"
  # shellcheck disable=SC2206
  GIT_CLONE_ARGUMENTS=(${BUILD_CONFIG[SHALLOW_CLONE_OPTION]} "$git_remote_repo_address" "${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[WORKING_DIR]}/${BUILD_CONFIG[OPENJDK_SOURCE_DIR]}")
}

updateOpenj9Sources() {
  # Building OpenJDK with OpenJ9 must run get_source.sh to clone openj9 and openj9-omr repositories
  if [ "${BUILD_CONFIG[BUILD_VARIANT]}" == "${BUILD_VARIANT_OPENJ9}" ]; then
    cd "${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[WORKING_DIR]}/${BUILD_CONFIG[OPENJDK_SOURCE_DIR]}" || return
    # NOTE: fetched openssl will NOT be used in the RISC-V cross-compile situation
    bash get_source.sh -openssl-branch=openssl-3.0.16
    cd "${BUILD_CONFIG[WORKSPACE_DIR]}"
  fi
}

# Clone the git repo
cloneOpenJDKGitRepo() {
  setGitCloneArguments

  echo "git clone ${GIT_CLONE_ARGUMENTS[*]}"
  git clone "${GIT_CLONE_ARGUMENTS[@]}"
}

# Create the workspace
createWorkspace() {
  # Setting this to ensure none of the files we ship are group writable
  umask 022
  mkdir -p "${BUILD_CONFIG[WORKSPACE_DIR]}" || exit
  mkdir -p "${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[WORKING_DIR]}" || exit

  # If a user supplied OpenJDK build root directory has been specified and it is not empty
  # then fail with an error, we don't want to delete it in case user has specified a wrong directory
  # Ensure the directory is created if it doesn't exist
  if [[ -n "${BUILD_CONFIG[USER_OPENJDK_BUILD_ROOT_DIRECTORY]}" ]]; then
    if [[ -d "${BUILD_CONFIG[USER_OPENJDK_BUILD_ROOT_DIRECTORY]}" ]] && [[ "$(ls -A "${BUILD_CONFIG[USER_OPENJDK_BUILD_ROOT_DIRECTORY]}")" ]]; then
      echo "ERROR: Existing user supplied OpenJDK build root directory ${BUILD_CONFIG[USER_OPENJDK_BUILD_ROOT_DIRECTORY]} is not empty"
      exit 1
    fi
    mkdir -p "${BUILD_CONFIG[USER_OPENJDK_BUILD_ROOT_DIRECTORY]}" || exit
  fi
}

# ALSA first for sound
checkingAndDownloadingAlsa() {

  cd "${BUILD_CONFIG[WORKSPACE_DIR]}/libs/" || exit

  echo "Checking for ALSA"

  FOUND_ALSA=$(find "${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[WORKING_DIR]}/" -name "installedalsa")

  mkdir -p "${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[WORKING_DIR]}/installedalsa/" || exit

  ALSA_BUILD_URL="Unknown"
  if [[ -n "$FOUND_ALSA" ]]; then
    echo "Skipping ALSA download"
  else

    ALSA_BUILD_URL="https://ftp2.osuosl.org/pub/blfs/conglomeration/alsa-lib/alsa-lib-${ALSA_LIB_VERSION}.tar.bz2"
    curl -o "alsa-lib.tar.bz2" "$ALSA_BUILD_URL"
    curl -o "alsa-lib.tar.bz2.sig" "https://www.alsa-project.org/files/pub/lib/alsa-lib-${ALSA_LIB_VERSION}.tar.bz2.sig"

    setupGpg

    # Should we clear this directory up after checking?
    # Would this risk removing anyone's existing dir with that name?
    # Erring on the side of caution for now
    # Note: the uptime command below is to aid diagnostics for this issue:
    # https://github.com/adoptium/temurin-build/issues/3518#issuecomment-1792606345
    uptime
    # Will retry command below until it passes or we've failed 10 times.
    for i in {1..10}; do
      if gpg --keyserver keyserver.ubuntu.com --keyserver-options timeout=300 --recv-keys "${ALSA_LIB_GPGKEYID}"; then
        echo "gpg command has passed."
        break
      elif [[ ${i} -lt 10 ]]; then
        echo "gpg recv-keys attempt has failed. Retrying after 10 second pause..."
        verboseSleep 10
      else
        echo "ERROR: gpg recv-keys final attempt has failed. Will not try again."
      fi
    done
    echo -e "5\ny\n" |  gpg --batch --command-fd 0 --expert --edit-key "${ALSA_LIB_GPGKEYID}" trust;
    gpg --verify alsa-lib.tar.bz2.sig alsa-lib.tar.bz2 || exit 1

    if [[ "${BUILD_CONFIG[OS_KERNEL_NAME]}" == "aix" ]] || [[ "${BUILD_CONFIG[OS_KERNEL_NAME]}" == "sunos" ]]; then
      bzip2 -d alsa-lib.tar.bz2
      tar -xf alsa-lib.tar --strip-components=1 -C "${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[WORKING_DIR]}/installedalsa/"
      rm alsa-lib.tar
    else
      tar -xf alsa-lib.tar.bz2 --strip-components=1 -C "${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[WORKING_DIR]}/installedalsa/"
      rm alsa-lib.tar.bz2
    fi
  fi

  # Record buildinfo version
  echo "${ALSA_BUILD_URL}" > "${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[TARGET_DIR]}/metadata/dependency_version_alsa.txt"
}

sha256File() {
  if [ -x "$(command -v shasum)" ]; then
    (shasum -a 256 "$1" | cut -f1 -d' ')
  else
    sha256sum "$1" | cut -f1 -d' '
  fi
}

checkFingerprint() {
  local sigFile="$1"
  local fileName="$2"
  local publicKey="$3"
  local expectedFingerprint="$4"
  local expectedChecksum="$5"

  if ! [ -x "$(command -v gpg)" ] || [ "${BUILD_CONFIG[OS_ARCHITECTURE]}" == "armv7l" ]; then
    echo "WARNING: GPG not present, resorting to checksum"
    local actualChecksum=$(sha256File "${fileName}")

    if [ "${actualChecksum}" != "${expectedChecksum}" ]; then
      echo "Failed to verify checksum on ${fileName}"

      echo "Expected ${expectedChecksum} got ${actualChecksum}"
      exit 1
    fi

    return
  fi

  rm "${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[WORKING_DIR]}/public_key.gpg" || true

  gpg --no-options --output "${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[WORKING_DIR]}/public_key.gpg" --dearmor "${SCRIPT_DIR}/sig_check/${publicKey}.asc"

  # If this dir does not exist, gpg 1.4.20 supplied on Ubuntu16.04 aborts
  mkdir -p "$HOME/.gnupg"
  local verify=$(gpg --no-options -v --no-default-keyring --keyring "${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[WORKING_DIR]}/public_key.gpg" --verify "$sigFile" "$fileName" 2>&1)

  echo "$verify"

  # grep out and trim fingerprint from line of the form "Primary key fingerprint: 58E0 C111 E39F 5408 C5D3  EC76 C1A6 0EAC E707 FDA5"
  local fingerprint=$(echo "$verify" | grep "Primary key fingerprint" | egrep -o "([0-9A-F]{4} ? ?){10}" | head -n 1)

  # Remove whitespace from finger print as different versions of gpg may or may not add spaces to the fingerprint
  # specifically gpg on Ubuntu 16.04 produces:
  # `13AC 2213 964A BE1D 1C14 7C0E 1939 A252 0BAB 1D90`
  # where as 18.04 produces:
  # `13AC2213964ABE1D1C147C0E1939A2520BAB1D90`
  fingerprint="${fingerprint// /}"

  # remove spaces from expected fingerprint to match the format from the output of gpg
  expectedFingerprint="${expectedFingerprint// /}"

  if [ "$fingerprint" != "$expectedFingerprint" ]; then
    echo "Failed to verify signature of $fileName"
    echo "expected \"$expectedFingerprint\" got \"$fingerprint\""
    exit 1
  fi
}

# Utility function
downloadFile() {
  local targetFileName="$1"
  local url="$2"

  echo downloadFile: Saving "url" to "$targetFileName"

  # Temporary fudge as curl on my windows boxes is exiting with RC=127
  if [[ "$OSTYPE" == "cygwin" ]] || [[ "$OSTYPE" == "msys" ]]; then
    if ! wget -O "${targetFileName}" "${url}"; then
       echo ERROR: Failed to download "${url}" - exiting
       exit 2
    fi
  elif ! curl --fail -L -o "${targetFileName}" "${url}"; then
    echo ERROR: Failed to download "${url}" - exiting
    exit 2
  fi

  if [ $# -ge 3 ]; then

    local expectedChecksum="$3"
    local actualChecksum=$(sha256File "${targetFileName}")

    if [ "${actualChecksum}" != "${expectedChecksum}" ]; then
      echo "ERROR: Failed to verify checksum on ${targetFileName} ${url}"

      echo "Expected ${expectedChecksum} got ${actualChecksum}"
      exit 1
    fi
  fi
}

# Clone Freetype from GitHub
checkingAndDownloadingFreeType() {
  cd "${BUILD_CONFIG[WORKSPACE_DIR]}/libs/" || exit
  echo "Checking for freetype at ${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[WORKING_DIR]}"

  FOUND_FREETYPE=$(find "${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[WORKING_DIR]}/installedfreetype/lib/" -name "${FREETYPE_FONT_SHARED_OBJECT_FILENAME}" || true)

  if [[ -n "$FOUND_FREETYPE" ]]; then
    echo "Skipping FreeType download"
  else
    # Delete existing freetype folder if it exists
    rm -rf "./freetype" || true

    case ${BUILD_CONFIG[FREETYPE_FONT_VERSION]} in
    *.*)
      # Replace . with - in version number e.g 2.8.1 -> 2-8-1
      FREETYPE_BRANCH="VER-${BUILD_CONFIG[FREETYPE_FONT_VERSION]//./-}"
      git clone https://github.com/freetype/freetype.git -b "${FREETYPE_BRANCH}" freetype || exit
      ;;
    *)
      # Use specific git hash
      git clone https://github.com/freetype/freetype.git freetype || exit
      cd freetype || exit
      git checkout "${BUILD_CONFIG[FREETYPE_FONT_VERSION]}" || exit
      cd .. || exit
      ;;
    esac

    cd freetype || exit

    if [[ "$OSTYPE" == "cygwin" ]] || [[ "$OSTYPE" == "msys" ]]; then
      return
    fi

    local freetypeEnv=""
    if [[ "${BUILD_CONFIG[OS_ARCHITECTURE]}" == "i686" ]] || [[ "${BUILD_CONFIG[OS_ARCHITECTURE]}" == "i386" ]]; then
      freetypeEnv="export CC=\"gcc -m32\""
    fi

    eval "${freetypeEnv}" && bash ./autogen.sh || exit 1

    local pngArg=""
    if ./configure --help | grep "with-png"; then
      pngArg="--with-png=no"
    fi

    # We get the files we need at $WORKING_DIR/installedfreetype
    # shellcheck disable=SC2046
    if ! (bash ./configure --prefix="${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[WORKING_DIR]}"/installedfreetype "${pngArg}" "${BUILD_CONFIG[FREETYPE_FONT_BUILD_TYPE_PARAM]}" && ${BUILD_CONFIG[MAKE_COMMAND_NAME]} all && ${BUILD_CONFIG[MAKE_COMMAND_NAME]} install); then
      # shellcheck disable=SC2154
      echo "Failed to configure and build libfreetype, exiting"
      exit
    else
      # shellcheck disable=SC2154
      echo "Successfully configured OpenJDK with the FreeType library (libfreetype)!"

      if [ -d "${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[WORKING_DIR]}/installedfreetype/include/freetype2/freetype" ]; then
        echo "Relocating freetype headers"
        # Later freetype nests its header files
        cp -r "${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[WORKING_DIR]}/installedfreetype/include/freetype2/ft2build.h" "${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[WORKING_DIR]}/installedfreetype/include/"
        cp -r "${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[WORKING_DIR]}/installedfreetype/include/freetype2/freetype/"* "${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[WORKING_DIR]}/installedfreetype/include/"
      fi

      # For unclear reasons on OpenSUSE it puts the lib into a different dir
      if [ -d "${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[WORKING_DIR]}/installedfreetype/lib64" ] && [ ! -d "${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[WORKING_DIR]}/installedfreetype/lib" ]; then
        ln -s lib64 "${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[WORKING_DIR]}/installedfreetype/lib"
      fi

      if [[ ${BUILD_CONFIG[OS_KERNEL_NAME]} == "darwin" ]]; then
        TARGET_DYNAMIC_LIB_DIR="${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[WORKING_DIR]}"/installedfreetype/lib/
        TARGET_DYNAMIC_LIB="${TARGET_DYNAMIC_LIB_DIR}"/libfreetype.6.dylib

        echo "Listing the contents of ${TARGET_DYNAMIC_LIB_DIR} to see if the dynamic library 'libfreetype.6.dylib' has been created..."
        ls "${TARGET_DYNAMIC_LIB_DIR}"

        echo "Releasing the runpath dependency of the dynamic library ${TARGET_DYNAMIC_LIB}"
        install_name_tool -id @rpath/libfreetype.6.dylib "${TARGET_DYNAMIC_LIB}"

        # shellcheck disable=SC2181
        if [[ $? == 0 ]]; then
          echo "Successfully released the runpath dependency of the dynamic library ${TARGET_DYNAMIC_LIB}"
        else
          echo "Failed to release the runpath dependency of the dynamic library ${TARGET_DYNAMIC_LIB}"
        fi
      fi
    fi
  fi
}

# Recording Build image SHA into docker.txt
writeDockerImageSHA(){
  echo "${BUILDIMAGESHA-N.A}" > "${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[TARGET_DIR]}/metadata/docker.txt"
}

# Generates cacerts file
prepareMozillaCacerts() {
    echo "Generating cacerts from Mozilla's bundle"
    cd "$SCRIPT_DIR/../security"
    if [[ "${BUILD_CONFIG[OPENJDK_FEATURE_NUMBER]}" -ge "17" ]]; then
      # jdk-17+ build uses JDK make tool GenerateCacerts to load keystore for reproducible builds
      time ./mk-cacerts.sh --nokeystore
    else
      time ./mk-cacerts.sh --keytool "${BUILD_CONFIG[JDK_BOOT_DIR]}/bin/keytool"
    fi
}

# Create and setup GNUPGHOME
setupGpg() {
    ## This affects riscv64 & Alpine docker images and also evaluation pipelines
    if ( [ -r /etc/alpine-release ] && [ "$(pwd | wc -c)" -gt 83 ] ) || \
       ( [ "${BUILD_CONFIG[OS_KERNEL_NAME]}" == "linux" ] && [ "${BUILD_CONFIG[OS_ARCHITECTURE]}" == "riscv64" ] && [ "$(pwd | wc -c)" -gt 83 ] ); then
        # Use /tmp in preference to $HOME as fails gpg operation if PWD > 83 characters
        # Also cannot create ~/.gpg-temp within a docker context
        GNUPGHOME="$(mktemp -d /tmp/.gpg-temp.XXXXXX)"
    else
        GNUPGHOME="${BUILD_CONFIG[WORKSPACE_DIR]:-$PWD}/.gpg-temp"
    fi
    if [ ! -d "$GNUPGHOME" ]; then
        mkdir -m 700 "$GNUPGHOME"
    fi
    export GNUPGHOME

    echo "GNUPGHOME=$GNUPGHOME"
}

# Download the required Linux DevKit if necessary and not available in /usr/local/devkit
downloadLinuxDevkit() {
    local devkit_target="${BUILD_CONFIG[OS_ARCHITECTURE]}-linux-gnu"

    local USR_LOCAL_DEVKIT="/usr/local/devkit/${BUILD_CONFIG[USE_ADOPTIUM_DEVKIT]}"
    if [[ -d "${USR_LOCAL_DEVKIT}" ]]; then
      local usrLocalDevkitInfo="${USR_LOCAL_DEVKIT}/devkit.info"
       if ! grep "ADOPTIUM_DEVKIT_RELEASE=${BUILD_CONFIG[USE_ADOPTIUM_DEVKIT]}" "${usrLocalDevkitInfo}" || ! grep "ADOPTIUM_DEVKIT_TARGET=${devkit_target}" "${usrLocalDevkitInfo}"; then
        echo "WARNING: Devkit ${usrLocalDevkitInfo} does not match required release and architecture:"
        echo "       Required:   ADOPTIUM_DEVKIT_RELEASE=${BUILD_CONFIG[USE_ADOPTIUM_DEVKIT]}"
        echo "       ${USR_LOCAL_DEVKIT}: $(grep ADOPTIUM_DEVKIT_RELEASE= "${usrLocalDevkitInfo}")"
        echo "       Required:   ADOPTIUM_DEVKIT_TARGET=${devkit_target}"
        echo "       ${USR_LOCAL_DEVKIT}: $(grep ADOPTIUM_DEVKIT_TARGET= "${usrLocalDevkitInfo}")"
        echo "Attempting to download the required DevKit instead"
      else
        # Found a matching DevKit
        echo "Using matching DevKit from location ${USR_LOCAL_DEVKIT}"
        BUILD_CONFIG[ADOPTIUM_DEVKIT_LOCATION]="${USR_LOCAL_DEVKIT}"
      fi
    fi

    # Download from adoptium/devkit-runtimes if we have not found a matching one locally
    if [[ -z "${BUILD_CONFIG[ADOPTIUM_DEVKIT_LOCATION]}" ]]; then
      local devkit_tar="${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[WORKING_DIR]}/devkit/devkit.tar.xz"

      setupGpg

      # Determine DevKit tarball to download for this arch and release
      local devkitUrl="https://github.com/adoptium/devkit-binaries/releases/download/${BUILD_CONFIG[USE_ADOPTIUM_DEVKIT]}"
      local devkit="devkit-${BUILD_CONFIG[USE_ADOPTIUM_DEVKIT]}-${devkit_target}"

      # Download tarball and GPG sig
      echo "Downloading DevKit : ${devkitUrl}/${devkit}.tar.xz"
      curl -L --fail --silent --show-error -o "${devkit_tar}" "${devkitUrl}/${devkit}.tar.xz"
      curl -L --fail --silent --show-error -o "${devkit_tar}.sig" "${devkitUrl}/${devkit}.tar.xz.sig"

      # GPG verify
      gpg --keyserver keyserver.ubuntu.com --recv-keys 3B04D753C9050D9A5D343F39843C48A565F8F04B
      echo -e "5\ny\n" |  gpg --batch --command-fd 0 --expert --edit-key 3B04D753C9050D9A5D343F39843C48A565F8F04B trust;
      gpg --verify "${devkit_tar}.sig" "${devkit_tar}" || exit 1

      tar xpJf "${devkit_tar}" -C "${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[WORKING_DIR]}/devkit"
      rm "${devkit_tar}"
      rm "${devkit_tar}.sig"

      # Validate devkit.info matches value passed in and current architecture
      local devkitInfo="${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[WORKING_DIR]}/devkit/devkit.info"
      if ! grep "ADOPTIUM_DEVKIT_RELEASE=${BUILD_CONFIG[USE_ADOPTIUM_DEVKIT]}" "${devkitInfo}" || ! grep "ADOPTIUM_DEVKIT_TARGET=${devkit_target}" "${devkitInfo}"; then
        echo "ERROR: Devkit does not match required release and architecture:"
        echo "       Required:   ADOPTIUM_DEVKIT_RELEASE=${BUILD_CONFIG[USE_ADOPTIUM_DEVKIT]}"
        echo "       Downloaded: $(grep ADOPTIUM_DEVKIT_RELEASE= "${devkitInfo}")"
        echo "       Required:   ADOPTIUM_DEVKIT_TARGET=${devkit_target}"
        echo "       Downloaded: $(grep ADOPTIUM_DEVKIT_TARGET= "${devkitInfo}")"
        exit 1
      fi

      BUILD_CONFIG[ADOPTIUM_DEVKIT_LOCATION]="${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[WORKING_DIR]}/devkit"
    fi
}

# Download the required Windows DevKit if necessary and not available in c:/openjdk/devkit
#   For the moment this is just support for Windows Redist DLLs
downloadWindowsDevkit() {
    local WIN_LOCAL_DEVKIT="/cygdrive/C/openjdk/devkit/${BUILD_CONFIG[USE_ADOPTIUM_DEVKIT]}"
    if [[ -d "${WIN_LOCAL_DEVKIT}" ]]; then
      local winLocalDevkitInfo="${WIN_LOCAL_DEVKIT}/devkit.info"
       if ! grep "ADOPTIUM_DEVKIT_RELEASE=${BUILD_CONFIG[USE_ADOPTIUM_DEVKIT]}" "${winLocalDevkitInfo}"; then
        echo "WARNING: Devkit ${winLocalDevkitInfo} does not match required release:"
        echo "       Required:   ADOPTIUM_DEVKIT_RELEASE=${BUILD_CONFIG[USE_ADOPTIUM_DEVKIT]}"
        echo "       ${WIN_LOCAL_DEVKIT}: $(grep ADOPTIUM_DEVKIT_RELEASE= "${winLocalDevkitInfo}")"
        echo "Attempting to download the required DevKit instead"
      else
        # Found a matching DevKit
        echo "Using matching DevKit from location ${WIN_LOCAL_DEVKIT}"
        BUILD_CONFIG[ADOPTIUM_DEVKIT_LOCATION]="${WIN_LOCAL_DEVKIT}"
      fi
    fi

    # Download from adoptium/devkit-runtimes if we have not found a matching one locally
    if [[ -z "${BUILD_CONFIG[ADOPTIUM_DEVKIT_LOCATION]}" ]]; then
      local devkit_zip="${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[WORKING_DIR]}/devkit/devkit.zip"

      # Determine DevKit zip to download for this release
      local devkitUrl="https://github.com/adoptium/devkit-binaries/releases/download/${BUILD_CONFIG[USE_ADOPTIUM_DEVKIT]}"
      local devkit="${BUILD_CONFIG[USE_ADOPTIUM_DEVKIT]}.zip"

      # Download zip
      echo "Downloading DevKit : ${devkitUrl}/${devkit}"
      curl -L --fail --silent --show-error -o "${devkit_zip}" "${devkitUrl}/${devkit}"

      # Verify checksum
      local expectedChecksum="${WINDOWS_REDIST_CHECKSUM}"
      local actualChecksum=$(sha256File "${devkit_zip}")
      if [ "${actualChecksum}" != "${expectedChecksum}" ]; then
        echo "Failed to verify checksum on ${devkit_zip}"

        echo "Expected ${expectedChecksum} got ${actualChecksum}"
        exit 1
      fi

      unzip "${devkit_zip}" -d "${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[WORKING_DIR]}/devkit"
      rm "${devkit_zip}"

      # Validate devkit.info matches value passed in
      local devkitInfo="${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[WORKING_DIR]}/devkit/devkit.info"
      if ! grep "ADOPTIUM_DEVKIT_RELEASE=${BUILD_CONFIG[USE_ADOPTIUM_DEVKIT]}" "${devkitInfo}"; then
        echo "ERROR: Devkit does not match required release:"
        echo "       Required:   ADOPTIUM_DEVKIT_RELEASE=${BUILD_CONFIG[USE_ADOPTIUM_DEVKIT]}"
        echo "       Downloaded: $(grep ADOPTIUM_DEVKIT_RELEASE= "${devkitInfo}")"
        exit 1
      fi

      BUILD_CONFIG[ADOPTIUM_DEVKIT_LOCATION]="${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[WORKING_DIR]}/devkit"
    fi
}

# Download the required DevKit if necessary and not available in /usr/local/devkit
downloadDevkit() {
  if [[ -n "${BUILD_CONFIG[USE_ADOPTIUM_DEVKIT]}" ]]; then
    rm -rf "${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[WORKING_DIR]}/devkit"
    mkdir -p "${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[WORKING_DIR]}/devkit"

    BUILD_CONFIG[ADOPTIUM_DEVKIT_LOCATION]=""

    if [ "${BUILD_CONFIG[OS_KERNEL_NAME]}" == "linux" ]; then
      downloadLinuxDevkit
    elif [[ "$OSTYPE" == "cygwin" ]] || [[ "$OSTYPE" == "msys" ]]; then
      downloadWindowsDevkit
    fi
  fi
}

downloadBootJdkIfNeeded () {
  if [[ "${BUILD_CONFIG[JDK_BOOT_DIR]}" == "download" ]]; then
    local futureBootDir="${BUILD_CONFIG[WORKSPACE_DIR]}/downloaded-boot-jdk-${BUILD_CONFIG[OPENJDK_FEATURE_NUMBER]}"
    if  [ -e "$futureBootDir" ] ; then
      echo "Reusing $futureBootDir"
    else
      source "$SCRIPT_DIR/common/downloaders.sh"
      echo "Downloading to $futureBootDir"
      downloadBootJDK "$(uname -m)" "${BUILD_CONFIG[OPENJDK_FEATURE_NUMBER]}" "${futureBootDir}"
    fi
    BUILD_CONFIG[JDK_BOOT_DIR]="${futureBootDir}"
  fi
}

# Download all of the dependencies for OpenJDK (Alsa, FreeType, boot-jdk etc.)
downloadingRequiredDependencies() {
  if [[ "${BUILD_CONFIG[CLEAN_LIBS]}" == "true" ]]; then
    rm -rf "${BUILD_CONFIG[WORKSPACE_DIR]}/libs/freetype" || true
    rm -rf "${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[WORKING_DIR]}/installedalsa" || true
    rm -rf "${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[WORKING_DIR]}/installedfreetype" || true
    rm -rf "${BUILD_CONFIG[WORKSPACE_DIR]}/downloaded-boot-jdk-${BUILD_CONFIG[OPENJDK_FEATURE_NUMBER]}" || true
  fi

  downloadBootJdkIfNeeded

  mkdir -p "${BUILD_CONFIG[WORKSPACE_DIR]}/libs/" || exit
  cd "${BUILD_CONFIG[WORKSPACE_DIR]}/libs/" || exit

  if [[ "$OSTYPE" == "cygwin" ]] || [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "" ]] || [[ "${BUILD_CONFIG[OS_KERNEL_NAME]}" == "darwin" ]] ||  [[ "${BUILD_CONFIG[OS_KERNEL_NAME]}" == "aix" ]] ||  [[ "${BUILD_CONFIG[OS_KERNEL_NAME]}" == "sunos" ]] ; then
    echo "Non-Linux-based environment detected, skipping download of dependency Alsa."
  else
    echo "Checking and downloading Alsa dependency because OSTYPE=\"${OSTYPE}\""
    if [[ "${BUILD_CONFIG[ALSA]}" == "true" ]]; then
      checkingAndDownloadingAlsa
    else
      echo ""
      echo "---> Skipping the process of checking and downloading the Alsa dependency, a pre-built version should be provided via -C/--configure-args <---"
      echo ""
    fi
  fi

  if [[ "${BUILD_CONFIG[FREETYPE]}" == "true" ]]; then
    case "${BUILD_CONFIG[OPENJDK_CORE_VERSION]}" in
      jdk8* | jdk9* | jdk10*)
        if [ -z "${BUILD_CONFIG[FREETYPE_DIRECTORY]}" ]; then
          echo "Checking and download FreeType Font dependency"
          checkingAndDownloadingFreeType
        else
          echo ""
          echo "---> Skipping the process of checking and downloading the FreeType Font dependency, a pre-built version provided at ${BUILD_CONFIG[FREETYPE_DIRECTORY]} <---"
          echo ""
        fi
      ;;
      *) echo "Using bundled Freetype" ;;
    esac
  else
    echo "Skipping Freetype"
  fi
}

function moveTmpToWorkspaceLocation() {
  if [ -n "${TMP_WORKSPACE}" ]; then

    echo "Relocating workspace from ${TMP_WORKSPACE} to ${ORIGINAL_WORKSPACE}"

    rsync -a --delete "${TMP_WORKSPACE}/workspace/" "${ORIGINAL_WORKSPACE}/"
    echo "===${ORIGINAL_WORKSPACE}/======"
    ls -alh "${ORIGINAL_WORKSPACE}/" || true

    echo "===${ORIGINAL_WORKSPACE}/build======"
    ls -alh "${ORIGINAL_WORKSPACE}/build" || true
  fi
}

relocateToTmpIfNeeded() {
  if [ "${BUILD_CONFIG[TMP_SPACE_BUILD]}" == "true" ]; then
    jobName=$(echo "${JOB_NAME:-build-dir}" | egrep -o "[^/]+$")
    local tmpdir="/tmp/openjdk-${jobName}"
    mkdir -p "$tmpdir"

    export TMP_WORKSPACE="${tmpdir}"
    export ORIGINAL_WORKSPACE="${BUILD_CONFIG[WORKSPACE_DIR]}"

    trap moveTmpToWorkspaceLocation EXIT SIGINT SIGTERM

    if [ -d "${ORIGINAL_WORKSPACE}" ]; then
      echo "${BUILD_CONFIG[WORKSPACE_DIR]}"
      rsync -a --delete "${BUILD_CONFIG[WORKSPACE_DIR]}" "${TMP_WORKSPACE}/"

      echo "===${TMP_WORKSPACE}/======"
      ls -alh "${TMP_WORKSPACE}/" || true

      echo "===${TMP_WORKSPACE}/workspace======"
      ls -alh "${TMP_WORKSPACE}/workspace" || true

      echo "===${TMP_WORKSPACE}/workspace/build======"
      ls -alh "${TMP_WORKSPACE}/workspace/build" || true
    fi
    BUILD_CONFIG[WORKSPACE_DIR]="${TMP_WORKSPACE}/workspace"

  fi
}

applyPatches() {
  if [ -n "${BUILD_CONFIG[PATCHES]}" ]; then
    echo "applying patches from ${BUILD_CONFIG[PATCHES]}"
    git clone "${BUILD_CONFIG[PATCHES]}" "${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[WORKING_DIR]}/patches"
    cd "${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[WORKING_DIR]}/${BUILD_CONFIG[OPENJDK_SOURCE_DIR]}"
    for patch in "${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[WORKING_DIR]}/patches/"*.patch; do
      echo "applying $patch"
      patch -p1 <"$patch"
    done
  fi
}

# jdk8u requires a .hgtip file to populate the "SOURCE" tag in the release file.
# Creates .hgtip and populates it with the git sha of the last commit(s).
createSourceTagFile(){
  if [ "${BUILD_CONFIG[OPENJDK_CORE_VERSION]}" == "${JDK8_CORE_VERSION}" ]; then
    local OpenJDK_TopDir="${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[WORKING_DIR]}/${BUILD_CONFIG[OPENJDK_SOURCE_DIR]}"
    local OpenJDK_SHA=$(cd "$OpenJDK_TopDir" && git rev-parse --short HEAD)
    if [ "${BUILD_CONFIG[BUILD_VARIANT]}" == "${BUILD_VARIANT_OPENJ9}" ]; then
      # OpenJ9 list 3 SHA's in their release file: OpenJDK, OpenJ9, and OMR.
      local OpenJ9_TopDir="$OpenJDK_TopDir/openj9"
      local OMR_TopDir="$OpenJDK_TopDir/omr"
      local OpenJ9_SHA=$(cd "$OpenJ9_TopDir" && git rev-parse --short HEAD)
      local OMR_SHA=$(cd "$OMR_TopDir" && git rev-parse --short HEAD)
      (printf "OpenJDK: %s OpenJ9: %s OMR: %s" "$OpenJDK_SHA" "$OpenJ9_SHA" "$OMR_SHA") > "$OpenJDK_TopDir/.hgtip"
    else # Other variants only list the main repo SHA.
      (printf "OpenJDK: %s" "$OpenJDK_SHA") > "$OpenJDK_TopDir/.hgtip"
    fi
  fi
}

##################################################################

function configureWorkspace() {
  if [[ "${BUILD_CONFIG[ASSEMBLE_EXPLODED_IMAGE]}" != "true" ]]; then
    createWorkspace
    downloadingRequiredDependencies
    downloadDevkit
    relocateToTmpIfNeeded
    checkoutAndCloneOpenJDKGitRepo
    applyPatches
    if [ "${BUILD_CONFIG[CUSTOM_CACERTS]}" = "true" ] ; then
      prepareMozillaCacerts
    fi
  fi
  writeDockerImageSHA
}
