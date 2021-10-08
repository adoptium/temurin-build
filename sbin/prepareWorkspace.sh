#!/bin/bash
# shellcheck disable=SC2155,SC1091

################################################################################
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

################################################################################
#
# This script prepares the workspace to build (Adopt) OpenJDK.
# See the configureWorkspace function for details
# It is sourced by build.sh
#
################################################################################

set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=sbin/common/constants.sh
source "$SCRIPT_DIR/common/constants.sh"

# Set default versions for 3 libraries that OpenJDK relies on to build

ALSA_LIB_VERSION=${ALSA_LIB_VERSION:-1.1.6}
ALSA_LIB_CHECKSUM=${ALSA_LIB_CHECKSUM:-5f2cd274b272cae0d0d111e8a9e363f08783329157e8dd68b3de0c096de6d724}
FREEMARKER_LIB_CHECKSUM=${FREEMARKER_LIB_CHECKSUM:-8723ec9ffe006e8d376b6c7dbe7950db34ad1fa163aef4026e6477151a1a0deb}
FREETYPE_LIB_CHECKSUM=${FREETYPE_LIB_CHECKSUM:-ec391504e55498adceb30baceebd147a6e963f636eb617424bcfc47a169898ce}

FREETYPE_FONT_SHARED_OBJECT_FILENAME="libfreetype.so*"
FREEMARKER_LIB_VERSION=${FREEMARKER_LIB_VERSION:-2.3.31}

# Create a new clone or update the existing clone of the OpenJDK source repo
# TODO refactor this for Single Responsibility Principle (SRP)
checkoutAndCloneOpenJDKGitRepo() {

  cd "${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[WORKING_DIR]}"

  # Check that we have a git repo, we assume that it is a repo that contains openjdk source
  if [ -d "${BUILD_CONFIG[OPENJDK_SOURCE_DIR]}/.git" ]; then
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
      git --git-dir "${BUILD_CONFIG[OPENJDK_SOURCE_DIR]}/.git" remote -v | grep "origin.*fetch" | grep -E "${BUILD_CONFIG[REPOSITORY]}.git|${BUILD_CONFIG[REPOSITORY]}\s"
    else
      git --git-dir "${BUILD_CONFIG[OPENJDK_SOURCE_DIR]}/.git" remote -v | grep "origin.*fetch" | grep "${BUILD_CONFIG[OPENJDK_CORE_VERSION]}" | grep -E "${BUILD_CONFIG[REPOSITORY]}.git|${BUILD_CONFIG[REPOSITORY]}\s"
    fi
    local isValidGitRepo=$?
    set -e

    # If the local copy of the git source repo is valid then we reset appropriately
    if [ "${isValidGitRepo}" == "0" ]; then
      cd "${BUILD_CONFIG[OPENJDK_SOURCE_DIR]}" || return
      echo "Resetting the git openjdk source repository at $PWD in 10 seconds..."
      sleep 10
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

  if [[ "${BUILD_CONFIG[BUILD_VARIANT]}" == "${BUILD_VARIANT_HOTSPOT}" ]] && [[ "${BUILD_CONFIG[OPENJDK_FEATURE_NUMBER]}" -ge 11 ]]; then
    # Verify Adopt patches tag is being built, otherwise we may be accidently just building "raw" OpenJDK
    if [ ! -f "${TEMURIN_MARKER_FILE}" ] && [ "${BUILD_CONFIG[DISABLE_ADOPT_BRANCH_SAFETY]}" == "false" ]; then
      echo "${TEMURIN_MARKER_FILE} marker file not found in fetched source to be built, this may mean the wrong SCMReference build parameter has been specified. Ensure the correct Temurin patch release tag is specified, eg.for build jdk-11.0.4+10, it would be jdk-11.0.4+10_adopt"
      exit 1
    fi
  fi

  git clean -ffdx

  updateOpenj9Sources
  updateDragonwellSources

  createSourceTagFile

  cd "${BUILD_CONFIG[WORKSPACE_DIR]}"
}

# Checkout the required code to build from the given cached git repo
# Set checkoutRc to result so we can retry
checkoutRequiredCodeToBuild() {
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
  if [ "${BUILD_CONFIG[BUILD_VARIANT]}" != "${BUILD_VARIANT_OPENJ9}" ]; then
    git fetch --tags || rc=$?
    if [ $rc -eq 0 ]; then
      if git show-ref -q --verify "refs/tags/${BUILD_CONFIG[BRANCH]}"; then
        echo "looks like the scm ref given is a valid tag, so treat it as a tag"
        tag="${BUILD_CONFIG[BRANCH]}"
        BUILD_CONFIG[TAG]="${tag}"
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
        # g824f8474f5 = THE SHORT HASH OF THE MOST RECENT COMMIT
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
    bash get_source.sh --openssl-version=1.1.1l
    cd "${BUILD_CONFIG[WORKSPACE_DIR]}"
  fi
}

updateDragonwellSources() {
  if [[ "${BUILD_CONFIG[BUILD_VARIANT]}" == "${BUILD_VARIANT_DRAGONWELL}" ]] && [[ "${BUILD_CONFIG[OPENJDK_CORE_VERSION]}" == "${JDK8_CORE_VERSION}" ]]; then
    cd "${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[WORKING_DIR]}/${BUILD_CONFIG[OPENJDK_SOURCE_DIR]}" || return
    local target_scm
    if [ -n "${BUILD_CONFIG[TAG]}" ]; then
      target_scm="${BUILD_CONFIG[TAG]}"
    else
      target_scm="${BUILD_CONFIG[BRANCH]}"
    fi
    if [ "${BUILD_CONFIG[RELEASE]}" == "false" ]; then
      bash get_source_dragonwell.sh --site github --branch "${target_scm}"
    else
      bash get_source_dragonwell.sh --site github --branch "${target_scm}" -r
    fi
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
}

# ALSA first for sound
checkingAndDownloadingAlsa() {
  cd "${BUILD_CONFIG[WORKSPACE_DIR]}/libs/" || exit

  echo "Checking for ALSA"

  FOUND_ALSA=$(find "${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[WORKING_DIR]}/" -name "installedalsa")

  mkdir -p "${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[WORKING_DIR]}/installedalsa/" || exit

  ALSA_BUILD_INFO="Unknown"
  if [[ -n "$FOUND_ALSA" ]]; then
    echo "Skipping ALSA download"
  else
    downloadFile "alsa-lib.tar.bz2" "https://ftp.osuosl.org/pub/blfs/conglomeration/alsa-lib/alsa-lib-${ALSA_LIB_VERSION}.tar.bz2" "${ALSA_LIB_CHECKSUM}"
    ALSA_BUILD_INFO="https://ftp.osuosl.org/pub/blfs/conglomeration/alsa-lib/alsa-lib-${ALSA_LIB_VERSION}.tar.bz2"

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
  echo "${ALSA_BUILD_INFO}" > "${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[TARGET_DIR]}/metadata/dependency_version_alsa.txt"
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
  local fingerprint=$(echo "$verify" | grep "Primary key fingerprint" | grep -E -o "([0-9A-F]{4} ? ?){10}" | head -n 1)

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

# Freemarker for OpenJ9
checkingAndDownloadingFreemarker() {
  echo "Checking for FREEMARKER"

  cd "${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[WORKING_DIR]}/" || exit
  FOUND_FREEMARKER=$(find "." -type d -name "freemarker-${FREEMARKER_LIB_VERSION}")

  FREEMARKER_BUILD_INFO="Unknown"
  if [[ -n "$FOUND_FREEMARKER" ]]; then
    echo "Skipping FREEMARKER download"
  else

    # www.mirrorservice.org unavailable - issue #1867
    #wget -nc --no-check-certificate "https://www.mirrorservice.org/sites/ftp.apache.org/freemarker/engine/${FREEMARKER_LIB_VERSION}/binaries/apache-freemarker-${FREEMARKER_LIB_VERSION}-bin.tar.gz"

    wget "https://www.apache.org/dist/freemarker/engine/${FREEMARKER_LIB_VERSION}/binaries/apache-freemarker-${FREEMARKER_LIB_VERSION}-bin.tar.gz" ||
      curl -L -o "apache-freemarker-${FREEMARKER_LIB_VERSION}-bin.tar.gz" "https://www.apache.org/dist/freemarker/engine/${FREEMARKER_LIB_VERSION}/binaries/apache-freemarker-${FREEMARKER_LIB_VERSION}-bin.tar.gz"

    # Allow fallback to curl since wget fails cert check on macos - issue #1194
    wget "https://www.apache.org/dist/freemarker/engine/${FREEMARKER_LIB_VERSION}/binaries/apache-freemarker-${FREEMARKER_LIB_VERSION}-bin.tar.gz.asc" ||
      curl -L -o "apache-freemarker-${FREEMARKER_LIB_VERSION}-bin.tar.gz.asc" "https://www.apache.org/dist/freemarker/engine/${FREEMARKER_LIB_VERSION}/binaries/apache-freemarker-${FREEMARKER_LIB_VERSION}-bin.tar.gz.asc"

    FREEMARKER_BUILD_INFO="https://www.apache.org/dist/freemarker/engine/${FREEMARKER_LIB_VERSION}/binaries/apache-freemarker-${FREEMARKER_LIB_VERSION}-bin.tar.gz"

    checkFingerprint "apache-freemarker-${FREEMARKER_LIB_VERSION}-bin.tar.gz.asc" "apache-freemarker-${FREEMARKER_LIB_VERSION}-bin.tar.gz" "freemarker" "13AC 2213 964A BE1D 1C14 7C0E 1939 A252 0BAB 1D90" "${FREEMARKER_LIB_CHECKSUM}"

    mkdir -p "${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[WORKING_DIR]}/freemarker-${FREEMARKER_LIB_VERSION}/" || exit
    tar -xzf "apache-freemarker-${FREEMARKER_LIB_VERSION}-bin.tar.gz" --strip-components=1 -C "${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[WORKING_DIR]}/freemarker-${FREEMARKER_LIB_VERSION}/"
    rm "apache-freemarker-${FREEMARKER_LIB_VERSION}-bin.tar.gz"
  fi

  # Record buildinfo version
  echo "${FREEMARKER_BUILD_INFO}" > "${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[TARGET_DIR]}/metadata/dependency_version_freemarker.txt"
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

# Get Freetype
checkingAndDownloadingFreeType() {
  cd "${BUILD_CONFIG[WORKSPACE_DIR]}/libs/" || exit
  echo "Checking for freetype at ${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[WORKING_DIR]}"

  FOUND_FREETYPE=$(find "${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[WORKING_DIR]}/installedfreetype/lib/" -name "${FREETYPE_FONT_SHARED_OBJECT_FILENAME}" || true)

  FREETYPE_BUILD_INFO="Unknown"
  if [[ -n "$FOUND_FREETYPE" ]]; then
    echo "Skipping FreeType download"
  else
    downloadFile "freetype.tar.gz" "https://ci.adoptopenjdk.net/userContent/freetype/freetype-${BUILD_CONFIG[FREETYPE_FONT_VERSION]}.tar.gz"
    downloadFile "freetype.tar.gz.sig" "https://ci.adoptopenjdk.net/userContent/freetype/freetype-${BUILD_CONFIG[FREETYPE_FONT_VERSION]}.tar.gz.sig"
    checkFingerprint "freetype.tar.gz.sig" "freetype.tar.gz" "freetype" "58E0 C111 E39F 5408 C5D3 EC76 C1A6 0EAC E707 FDA5" "${FREETYPE_LIB_CHECKSUM}"

    FREETYPE_BUILD_INFO="https://ci.adoptopenjdk.net/userContent/freetype/freetype-${BUILD_CONFIG[FREETYPE_FONT_VERSION]}.tar.gz"

    rm -rf "./freetype" || true
    mkdir -p "freetype" || true
    tar xpzf freetype.tar.gz --strip-components=1 -C "freetype"
    rm freetype.tar.gz

    if [[ "$OSTYPE" == "cygwin" ]] || [[ "$OSTYPE" == "msys" ]]; then
      # Record buildinfo version
      echo "${FREETYPE_BUILD_INFO}" > "${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[TARGET_DIR]}/metadata/dependency_version_freetype.txt"
      return
    fi

    cd freetype || exit

    local pngArg=""
    if ./configure --help | grep "with-png"; then
      pngArg="--with-png=no"
    fi

    local freetypeEnv=""
    if [[ "${BUILD_CONFIG[OS_ARCHITECTURE]}" == "i686" ]] || [[ "${BUILD_CONFIG[OS_ARCHITECTURE]}" == "i386" ]]; then
      freetypeEnv="export CC=\"gcc -m32\""
    fi

    # We get the files we need at $WORKING_DIR/installedfreetype
    # shellcheck disable=SC2046
    if ! (eval "${freetypeEnv}" && bash ./configure --prefix="${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[WORKING_DIR]}"/installedfreetype "${pngArg}" "${BUILD_CONFIG[FREETYPE_FONT_BUILD_TYPE_PARAM]}" && ${BUILD_CONFIG[MAKE_COMMAND_NAME]} all && ${BUILD_CONFIG[MAKE_COMMAND_NAME]} install); then
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

  # Record buildinfo version
  echo "${FREETYPE_BUILD_INFO}" > "${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[TARGET_DIR]}/metadata/dependency_version_freetype.txt"
}

# Generates cacerts file
prepareMozillaCacerts() {
    echo "Generating cacerts from Mozilla's bundle"
    cd "$SCRIPT_DIR/../security"
    time ./mk-cacerts.sh --keytool "${BUILD_CONFIG[JDK_BOOT_DIR]}/bin/keytool"
}

# Download all of the dependencies for OpenJDK (Alsa, FreeType, etc.)
downloadingRequiredDependencies() {
  if [[ "${BUILD_CONFIG[CLEAN_LIBS]}" == "true" ]]; then
    rm -rf "${BUILD_CONFIG[WORKSPACE_DIR]}/libs/freetype" || true

    rm -rf "${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[WORKING_DIR]}/installedalsa" || true
    rm -rf "${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[WORKING_DIR]}/installedfreetype" || true
  fi

  mkdir -p "${BUILD_CONFIG[WORKSPACE_DIR]}/libs/" || exit
  cd "${BUILD_CONFIG[WORKSPACE_DIR]}/libs/" || exit

  if [[ "$OSTYPE" == "cygwin" ]] || [[ "$OSTYPE" == "msys" ]] || [[ "${BUILD_CONFIG[OS_KERNEL_NAME]}" == "darwin" ]]; then
    echo "macOS, Windows or Windows-like environment detected, skipping download of dependency Alsa."
  else
    echo "Checking and downloading Alsa dependency"
    checkingAndDownloadingAlsa
  fi

  if [[ "${BUILD_CONFIG[BUILD_VARIANT]}" == "${BUILD_VARIANT_OPENJ9}" ]]; then
    if [[ "$OSTYPE" == "cygwin" ]] || [[ "$OSTYPE" == "msys" ]]; then
      echo "Windows or Windows-like environment detected, skipping download of dependency Freemarker."
    else
      echo "Checking and downloading Freemarker dependency"
      checkingAndDownloadingFreemarker
    fi
  fi

  if [[ "${BUILD_CONFIG[FREETYPE]}" == "true" ]]; then
    if [ -z "${BUILD_CONFIG[FREETYPE_DIRECTORY]}" ]; then
      echo "Checking and download FreeType Font dependency"
      checkingAndDownloadingFreeType
    else
      echo ""
      echo "---> Skipping the process of checking and downloading the FreeType Font dependency, a pre-built version provided at ${BUILD_CONFIG[FREETYPE_DIRECTORY]} <---"
      echo ""
    fi
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
    jobName=$(echo "${JOB_NAME:-build-dir}" | grep -E -o "[^/]+$")
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
    local OpenJDK_SHA=$(git -C "$OpenJDK_TopDir" rev-parse --short HEAD)
    if [ "${BUILD_CONFIG[BUILD_VARIANT]}" == "${BUILD_VARIANT_OPENJ9}" ]; then
      # OpenJ9 list 3 SHA's in their release file: OpenJDK, OpenJ9, and OMR.
      local OpenJ9_TopDir="$OpenJDK_TopDir/openj9"
      local OMR_TopDir="$OpenJDK_TopDir/omr"
      local OpenJ9_SHA=$(git -C "$OpenJ9_TopDir" rev-parse --short HEAD)
      local OMR_SHA=$(git -C "$OMR_TopDir" rev-parse --short HEAD)
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
    relocateToTmpIfNeeded
    checkoutAndCloneOpenJDKGitRepo
    applyPatches
    if [ "${BUILD_CONFIG[CUSTOM_CACERTS]}" = "true" ] ; then
      prepareMozillaCacerts
    fi
  fi
}
