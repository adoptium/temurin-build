#!/bin/bash
# shellcheck disable=SC2155,SC2153,SC2038,SC1091,SC2116

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
# Build OpenJDK - can be called directly but is typically called by
# docker-build.sh or native-build.sh.
#
# See bottom of the script for the call order and each function for further
# details.
#
# Calls 'configure' then 'make' in order to build OpenJDK
#
################################################################################

set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=sbin/prepareWorkspace.sh
source "$SCRIPT_DIR/prepareWorkspace.sh"

# shellcheck source=sbin/common/config_init.sh
source "$SCRIPT_DIR/common/config_init.sh"

# shellcheck source=sbin/common/constants.sh
source "$SCRIPT_DIR/common/constants.sh"

# shellcheck source=sbin/common/common.sh
source "$SCRIPT_DIR/common/common.sh"

export LIB_DIR=$(crossPlatformRealPath "${SCRIPT_DIR}/../pipelines/")

export jreTargetPath
export CONFIGURE_ARGS=""
export ADDITIONAL_MAKE_TARGETS=""
export GIT_CLONE_ARGUMENTS=()

# Parse the CL arguments, defers to the shared function in common-functions.sh
function parseArguments() {
  parseConfigurationArguments "$@"
}

# Add an argument to the configure call
addConfigureArg() {
  # Only add an arg if it is not overridden by a user-specified arg.
  if [[ ${BUILD_CONFIG[USER_SUPPLIED_CONFIGURE_ARGS]} != *"$1"* ]]; then
    CONFIGURE_ARGS="${CONFIGURE_ARGS} ${1}${2}"
  fi
}

# Add an argument to the configure call (if it's not empty)
addConfigureArgIfValueIsNotEmpty() {
  # Only try to add an arg if the second argument is not empty.
  if [ -n "$2" ]; then
    addConfigureArg "$1" "$2"
  fi
}

# Configure the boot JDK
configureBootJDKConfigureParameter() {
  addConfigureArgIfValueIsNotEmpty "--with-boot-jdk=" "${BUILD_CONFIG[JDK_BOOT_DIR]}"
}

# Shenandaoh was backported to Java 11 as of 11.0.9 but requires this build
# parameter to ensure its inclusion. For Java 12+ this is automatically set
configureShenandoahBuildParameter() {
  if [ "${BUILD_CONFIG[OPENJDK_CORE_VERSION]}" == "${JDK11_CORE_VERSION}" ]; then
    if [ "${BUILD_CONFIG[BUILD_VARIANT]}" == "${BUILD_VARIANT_HOTSPOT}" ] || [ "${BUILD_CONFIG[BUILD_VARIANT]}" == "${BUILD_VARIANT_CORRETTO}" ]; then
      addConfigureArg "--with-jvm-features=" "shenandoahgc"
    fi
  fi
}

# Configure the boot JDK
configureMacOSCodesignParameter() {
  if [ -n "${BUILD_CONFIG[MACOSX_CODESIGN_IDENTITY]}" ]; then
    # This command needs to escape the double quotes because they are needed to preserve the spaces in the codesign cert name
    addConfigureArg "--with-macosx-codesign-identity=" "\"${BUILD_CONFIG[MACOSX_CODESIGN_IDENTITY]}\""
  fi
}

# Get the OpenJDK update version and build version
getOpenJDKUpdateAndBuildVersion() {
  cd "${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[WORKING_DIR]}"

  if [ -d "${BUILD_CONFIG[OPENJDK_SOURCE_DIR]}/.git" ]; then

    # It does exist and it's a repo other than the Temurin one
    cd "${BUILD_CONFIG[OPENJDK_SOURCE_DIR]}" || return

    if [ -f ".git/shallow.lock" ]; then
      echo "Detected lock file, assuming this is an error, removing"
      rm ".git/shallow.lock"
    fi

    # shellcheck disable=SC2154
    echo "Pulling latest tags and getting the latest update version using git fetch -q --tags ${BUILD_CONFIG[SHALLOW_CLONE_OPTION]}"
    # shellcheck disable=SC2154
    echo "NOTE: This can take quite some time!  Please be patient"
    # shellcheck disable=SC2086
    git fetch -q --tags ${BUILD_CONFIG[SHALLOW_CLONE_OPTION]}
    local openJdkVersion=$(getOpenJdkVersion)
    if [[ "${openJdkVersion}" == "" ]]; then
      # shellcheck disable=SC2154
      echo "Unable to detect git tag, exiting..."
      exit 1
    else
      echo "OpenJDK repo tag is $openJdkVersion"
    fi

    local openjdk_update_version
    openjdk_update_version=$(echo "${openJdkVersion}" | cut -d'u' -f 2 | cut -d'-' -f 1)

    # TODO dont modify config in build script
    echo "Version: ${openjdk_update_version} ${BUILD_CONFIG[OPENJDK_BUILD_NUMBER]}"
  fi

  cd "${BUILD_CONFIG[WORKSPACE_DIR]}"
}

getOpenJdkVersion() {
  local version

  if [ "${BUILD_CONFIG[BUILD_VARIANT]}" == "${BUILD_VARIANT_CORRETTO}" ]; then
    local corrVerFile=${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[WORKING_DIR]}/${BUILD_CONFIG[OPENJDK_SOURCE_DIR]}/version.txt

    local corrVersion="$(cut -d'.' -f 1 <"${corrVerFile}")"

    if [ "${corrVersion}" == "8" ]; then
      local updateNum="$(cut -d'.' -f 2 <"${corrVerFile}")"
      local buildNum="$(cut -d'.' -f 3 <"${corrVerFile}")"
      local fixNum="$(cut -d'.' -f 4 <"${corrVerFile}")"
      version="jdk8u${updateNum}-b${buildNum}.${fixNum}"
    else
      local minorNum="$(cut -d'.' -f 2 <"${corrVerFile}")"
      local updateNum="$(cut -d'.' -f 3 <"${corrVerFile}")"
      local buildNum="$(cut -d'.' -f 4 <"${corrVerFile}")"
      local fixNum="$(cut -d'.' -f 5 <"${corrVerFile}")"
      version="jdk-${corrVersion}.${minorNum}.${updateNum}+${buildNum}.${fixNum}"
    fi
  elif [ "${BUILD_CONFIG[BUILD_VARIANT]}" == "${BUILD_VARIANT_DRAGONWELL}" ]; then
    local dragonwellVerFile=${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[WORKING_DIR]}/${BUILD_CONFIG[OPENJDK_SOURCE_DIR]}/version.txt
    if [ -r "${dragonwellVerFile}" ]; then
      if [ "${BUILD_CONFIG[OPENJDK_CORE_VERSION]}" == "${JDK8_CORE_VERSION}" ]; then
        local updateNum="$(cut -d'.' -f 2 <"${dragonwellVerFile}")"
        local buildNum="$(cut -d'.' -f 6 <"${dragonwellVerFile}")"
        version="jdk8u${updateNum}-b${buildNum}"
      else
        local minorNum="$(cut -d'.' -f 2 <"${dragonwellVerFile}")"
        local updateNum="$(cut -d'.' -f 3 <"${dragonwellVerFile}")"
        local buildNum="$(cut -d'.' -f 5 <"${dragonwellVerFile}")"
        version="jdk-11.${minorNum}.${updateNum}+${buildNum}"
      fi
    else
      version=${BUILD_CONFIG[TAG]:-$(getFirstTagFromOpenJDKGitRepo)}
      version=$(echo "$version" | cut -d'_' -f 2)
    fi
  elif [ "${BUILD_CONFIG[BUILD_VARIANT]}" == "${BUILD_VARIANT_BISHENG}" ]; then
    local bishengVerFile=${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[WORKING_DIR]}/${BUILD_CONFIG[OPENJDK_SOURCE_DIR]}/version.txt
    if [ -r "${bishengVerFile}" ]; then
      if [ "${BUILD_CONFIG[OPENJDK_CORE_VERSION]}" == "${JDK8_CORE_VERSION}" ]; then
        local updateNum="$(cut -d'.' -f 2 <"${bishengVerFile}")"
        local buildNum="$(cut -d'.' -f 5 <"${bishengVerFile}")"
        version="jdk8u${updateNum}-b${buildNum}"
      else
        local minorNum="$(cut -d'.' -f 2 <"${bishengVerFile}")"
        local updateNum="$(cut -d'.' -f 3 <"${bishengVerFile}")"
        local buildNum="$(cut -d'.' -f 5 <"${bishengVerFile}")"
        version="jdk-11.${minorNum}.${updateNum}+${buildNum}"
      fi
    else
      version=${BUILD_CONFIG[TAG]:-$(getFirstTagFromOpenJDKGitRepo)}
      version=$(echo "$version" | cut -d'-' -f 2 | cut -d'_' -f 1)
    fi
  else
    version=${BUILD_CONFIG[TAG]:-$(getFirstTagFromOpenJDKGitRepo)}
    # TODO remove pending #1016
    version=${version%_adopt}
    version=${version#aarch64-shenandoah-}
  fi

  echo "${version}"
}

# Ensure that we produce builds with versions strings something like:
#
# openjdk version "1.8.0_131"
# OpenJDK Runtime Environment (build 1.8.0-temurin-<user>_2017_04_17_17_21-b00)
# OpenJDK 64-Bit Server VM (build 25.71-b00, mixed mode)
configureVersionStringParameter() {
  stepIntoTheWorkingDirectory

  local openJdkVersion=$(getOpenJdkVersion)
  echo "OpenJDK repo tag is ${openJdkVersion}"

  # --with-milestone=fcs deprecated at jdk12+ and not used for jdk11- (we use --without-version-pre/opt)
  if [ "${BUILD_CONFIG[OPENJDK_FEATURE_NUMBER]}" == 8 ] && [ "${BUILD_CONFIG[RELEASE]}" == "true" ]; then
    addConfigureArg "--with-milestone=" "fcs"
  elif [ "${BUILD_CONFIG[OPENJDK_FEATURE_NUMBER]}" == 8 ] && [ "${BUILD_CONFIG[RELEASE]}" != "true" ]; then
    addConfigureArg "--with-milestone=" "beta"
  fi

  local dateSuffix=$(date -u +%Y%m%d%H%M)

  # Configures "vendor" jdk properties.
  # Temurin default values are set after this code block
  # TODO 1. We should probably look at having these values passed through a config
  # file as opposed to hardcoding in shell
  # TODO 2. This highlights us conflating variant with vendor. e.g. OpenJ9 is really
  # a technical variant with Eclipse as the vendor
  if [[ "${BUILD_CONFIG[BUILD_VARIANT]}" == "${BUILD_VARIANT_DRAGONWELL}" ]]; then
    BUILD_CONFIG[VENDOR]="Alibaba"
    BUILD_CONFIG[VENDOR_VERSION]="\"(Alibaba Dragonwell)\""
    BUILD_CONFIG[VENDOR_URL]="http://www.alibabagroup.com"
    BUILD_CONFIG[VENDOR_BUG_URL]="mailto:dragonwell_use@googlegroups.com"
    BUILD_CONFIG[VENDOR_VM_BUG_URL]="mailto:dragonwell_use@googlegroups.com"
  elif [[ "${BUILD_CONFIG[BUILD_VARIANT]}" == "${BUILD_VARIANT_OPENJ9}" ]]; then
    BUILD_CONFIG[VENDOR_VM_BUG_URL]="https://github.com/eclipse-openj9/openj9/issues"
  elif [[ "${BUILD_CONFIG[BUILD_VARIANT]}" == "${BUILD_VARIANT_BISHENG}" ]]; then
    BUILD_CONFIG[VENDOR]="Huawei"
    BUILD_CONFIG[VENDOR_VERSION]="Bisheng"
    BUILD_CONFIG[VENDOR_BUG_URL]="https://gitee.com/openeuler/bishengjdk-11/issues"
    BUILD_CONFIG[VENDOR_VM_BUG_URL]="https://gitee.com/openeuler/bishengjdk-11/issues"
  fi
  if [ "${BUILD_CONFIG[OPENJDK_FEATURE_NUMBER]}" != 8 ]; then
    addConfigureArg "--with-vendor-name=" "\"${BUILD_CONFIG[VENDOR]}\""
  fi
  addConfigureArg "--with-vendor-url=" "${BUILD_CONFIG[VENDOR_URL]:-"https://adoptium.net/"}"
  addConfigureArg "--with-vendor-bug-url=" "${BUILD_CONFIG[VENDOR_BUG_URL]:-"https://github.com/adoptium/adoptium-support/issues"}"
  addConfigureArg "--with-vendor-vm-bug-url=" "${BUILD_CONFIG[VENDOR_VM_BUG_URL]:-"https://github.com/adoptium/adoptium-support/issues"}"

  local buildNumber
  if [ "${BUILD_CONFIG[OPENJDK_CORE_VERSION]}" == "${JDK8_CORE_VERSION}" ]; then

    if [ "${BUILD_CONFIG[RELEASE]}" == "false" ]; then
      addConfigureArg "--with-user-release-suffix=" "${dateSuffix}"
    fi

    if [ "${BUILD_CONFIG[BUILD_VARIANT]}" == "${BUILD_VARIANT_HOTSPOT}" ]; then

      addConfigureArg "--with-company-name=" "Temurin"

      # No JFR support in AIX or zero builds (s390 or armv7l)
      if [ "${BUILD_CONFIG[OS_ARCHITECTURE]}" != "s390x" ] && [ "${BUILD_CONFIG[OS_KERNEL_NAME]}" != "aix" ] && [ "${BUILD_CONFIG[OS_ARCHITECTURE]}" != "armv7l" ]; then
        addConfigureArg "--enable-jfr" ""
      fi

    fi

    # Set the update version (e.g. 131), this gets passed in from the calling script
    local updateNumber=${BUILD_CONFIG[OPENJDK_UPDATE_VERSION]}
    if [ -z "${updateNumber}" ]; then
      updateNumber=$(echo "${openJdkVersion}" | cut -f1 -d"-" | cut -f2 -d"u")
    fi
    addConfigureArgIfValueIsNotEmpty "--with-update-version=" "${updateNumber}"

    # Set the build number (e.g. b04), this gets passed in from the calling script
    buildNumber=${BUILD_CONFIG[OPENJDK_BUILD_NUMBER]}
    if [ -z "${buildNumber}" ]; then
      buildNumber=$(echo "${openJdkVersion}" | cut -f2 -d"-")
    fi

    if [ "${buildNumber}" ] && [ "${buildNumber}" != "ga" ]; then
      addConfigureArgIfValueIsNotEmpty "--with-build-number=" "${buildNumber}"
    fi
  elif [ "${BUILD_CONFIG[OPENJDK_CORE_VERSION]}" == "${JDK9_CORE_VERSION}" ]; then
    buildNumber=${BUILD_CONFIG[OPENJDK_BUILD_NUMBER]}
    if [ -z "${buildNumber}" ]; then
      buildNumber=$(echo "${openJdkVersion}" | cut -f2 -d"+")
    fi

    if [ "${BUILD_CONFIG[RELEASE]}" == "false" ]; then
      addConfigureArg "--with-version-opt=" "${dateSuffix}"
      addConfigureArg "--with-version-pre=" "beta"
    else
      addConfigureArg "--without-version-opt" ""
      addConfigureArg "--without-version-pre" ""
    fi

    addConfigureArgIfValueIsNotEmpty "--with-version-build=" "${buildNumber}"
  else
    # > JDK 9

    # Set the build number (e.g. b04), this gets passed in from the calling script
    buildNumber=${BUILD_CONFIG[OPENJDK_BUILD_NUMBER]}
    if [ -z "${buildNumber}" ]; then
      # Get build number (eg.10) from tag of potential format "jdk-11.0.4+10_adopt"
      buildNumber=$(echo "${openJdkVersion}" | cut -d_ -f1 | cut -f2 -d"+")
    fi

    if [ "${BUILD_CONFIG[RELEASE]}" == "false" ]; then
      addConfigureArg "--with-version-opt=" "${dateSuffix}"
      addConfigureArg "--with-version-pre=" "beta"
    else
      addConfigureArg "--without-version-opt" ""
      addConfigureArg "--without-version-pre" ""
    fi

    addConfigureArgIfValueIsNotEmpty "--with-version-build=" "${buildNumber}"
  fi

  if [ "${BUILD_CONFIG[OPENJDK_FEATURE_NUMBER]}" -gt 8 ]; then
    # Derive Adoptium metadata "version" string to use as vendor.version string
    # Take openJdkVersion, remove jdk- prefix and build suffix, replace with specified buildNumber
    # eg.:
    #   openJdkVersion = jdk-11.0.7+<build>
    #   vendor.version = Adoptium-11.0.7+<buildNumber>
    #
    # Remove "jdk-" prefix from openJdkVersion tag
    local derivedOpenJdkMetadataVersion=${openJdkVersion#"jdk-"}
    # Remove "+<build>" suffix
    derivedOpenJdkMetadataVersion=$(echo "${derivedOpenJdkMetadataVersion}" | cut -f1 -d"+")
    # Add "+<buildNumber>" being used
    derivedOpenJdkMetadataVersion="${derivedOpenJdkMetadataVersion}+${buildNumber}"
    if [ "${BUILD_CONFIG[RELEASE]}" == "false" ]; then
      # Not a release build so add date suffix
      derivedOpenJdkMetadataVersion="${derivedOpenJdkMetadataVersion}-${dateSuffix}"
    fi
    addConfigureArg "--with-vendor-version-string=" "${BUILD_CONFIG[VENDOR_VERSION]:-"Temurin"}-${derivedOpenJdkMetadataVersion}"
  fi

  echo "Completed configuring the version string parameter, config args are now: ${CONFIGURE_ARGS}"
}

# Construct all of the 'configure' parameters
buildingTheRestOfTheConfigParameters() {
  if [ -n "$(which ccache)" ]; then
    addConfigureArg "--enable-ccache" ""
  fi

  # Point-in-time dependency for openj9 only
  if [[ "${BUILD_CONFIG[BUILD_VARIANT]}" == "${BUILD_VARIANT_OPENJ9}" ]]; then
    addConfigureArg "--with-freemarker-jar=" "${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[WORKING_DIR]}/freemarker-${FREEMARKER_LIB_VERSION}/freemarker.jar"
  fi

  if [ "${BUILD_CONFIG[OPENJDK_CORE_VERSION]}" == "${JDK8_CORE_VERSION}" ]; then
    addConfigureArg "--with-x=" "/usr/include/X11"
    addConfigureArg "--with-alsa=" "${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[WORKING_DIR]}/installedalsa"
  fi
}

configureDebugParameters() {
  # We don't want any extra debug symbols - ensure it's set to release;
  # other options include fastdebug and slowdebug.
  addConfigureArg "--with-debug-level=" "release"

  # If debug symbols package is requested, generate them separately
  if [ ${BUILD_CONFIG[CREATE_DEBUG_IMAGE]} == true ]; then
    addConfigureArg "--with-native-debug-symbols=" "external"
  else
    if [ "${BUILD_CONFIG[OPENJDK_CORE_VERSION]}" == "${JDK8_CORE_VERSION}" ]; then
      addConfigureArg "--disable-zip-debug-info" ""
      if [[ "${BUILD_CONFIG[BUILD_VARIANT]}" != "${BUILD_VARIANT_OPENJ9}" ]]; then
        addConfigureArg "--disable-debug-symbols" ""
      fi
    else
      if [[ "${BUILD_CONFIG[BUILD_VARIANT]}" != "${BUILD_VARIANT_OPENJ9}" ]]; then
        addConfigureArg "--with-native-debug-symbols=" "none"
      fi
    fi
  fi
}

configureFreetypeLocation() {
  if [[ ! "${CONFIGURE_ARGS}" =~ "--with-freetype" ]]; then
    if [[ "${BUILD_CONFIG[FREETYPE]}" == "true" ]]; then
      local freetypeDir="${BUILD_CONFIG[FREETYPE_DIRECTORY]}"
      if [[ "$OSTYPE" == "cygwin" ]] || [[ "$OSTYPE" == "msys" ]]; then
        case "${BUILD_CONFIG[OPENJDK_CORE_VERSION]}" in
        jdk8* | jdk9* | jdk10*) addConfigureArg "--with-freetype-src=" "${BUILD_CONFIG[WORKSPACE_DIR]}/libs/freetype" ;;
        *) freetypeDir=${BUILD_CONFIG[FREETYPE_DIRECTORY]:-bundled} ;;
        esac
      else
        case "${BUILD_CONFIG[OPENJDK_CORE_VERSION]}" in
        jdk8* | jdk9* | jdk10*) freetypeDir=${BUILD_CONFIG[FREETYPE_DIRECTORY]:-"${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[WORKING_DIR]}/installedfreetype"} ;;
        *) freetypeDir=${BUILD_CONFIG[FREETYPE_DIRECTORY]:-bundled} ;;
        esac
      fi

      if [[ -n "$freetypeDir" ]]; then 
        echo "setting freetype dir to ${freetypeDir}"
        addConfigureArg "--with-freetype=" "${freetypeDir}"
      fi
    fi
  fi
}

# Configure the command parameters
configureCommandParameters() {
  configureVersionStringParameter
  configureBootJDKConfigureParameter
  configureShenandoahBuildParameter
  configureMacOSCodesignParameter
  configureDebugParameters

  if [[ "$OSTYPE" == "cygwin" ]] || [[ "$OSTYPE" == "msys" ]]; then
    echo "Windows or Windows-like environment detected, skipping configuring environment for custom Boot JDK and other 'configure' settings."

    if [[ "${BUILD_CONFIG[BUILD_VARIANT]}" == "${BUILD_VARIANT_OPENJ9}" ]] && [ "${BUILD_CONFIG[OPENJDK_CORE_VERSION]}" == "${JDK8_CORE_VERSION}" ]; then
      local addsDir="${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[WORKING_DIR]}/${BUILD_CONFIG[OPENJDK_SOURCE_DIR]}/closed/adds"

      # This is unfortunately required as if the path does not start with "/cygdrive" the make scripts are unable to find the "/closed/adds" directory.
      if ! echo "$addsDir" | grep -E -q "^/cygdrive/"; then
        # BUILD_CONFIG[WORKSPACE_DIR] does not seem to be an absolute path, prepend /cygdrive/c/cygwin64/"
        echo "Prepending /cygdrive/c/cygwin64/ to BUILD_CONFIG[WORKSPACE_DIR]"
        addsDir="/cygdrive/c/cygwin64/$addsDir"
      fi

      echo "adding source route -with-add-source-root=${addsDir}"
      addConfigureArg "--with-add-source-root=" "${addsDir}"
    fi
  else
    echo "Building up the configure command..."
    buildingTheRestOfTheConfigParameters
  fi

  echo "Configuring jvm variants if provided"
  addConfigureArgIfValueIsNotEmpty "--with-jvm-variants=" "${BUILD_CONFIG[JVM_VARIANT]}"

  if [ "${BUILD_CONFIG[CUSTOM_CACERTS]}" = "true" ] ; then
    echo "Configure custom cacerts file security/cacerts"
    addConfigureArgIfValueIsNotEmpty "--with-cacerts-file=" "$SCRIPT_DIR/../security/cacerts"
  fi

  # Finally, we add any configure arguments the user has specified on the command line.
  # This is done last, to ensure the user can override any args they need to.
  # The substitution allows the user to pass in speech marks without having to guess
  # at the number of escapes needed to ensure that they persist up to this point.
  CONFIGURE_ARGS="${CONFIGURE_ARGS} ${BUILD_CONFIG[USER_SUPPLIED_CONFIGURE_ARGS]//temporary_speech_mark_placeholder/\"}"

  configureFreetypeLocation

  echo "Completed configuring the version string parameter, config args are now: ${CONFIGURE_ARGS}"
}

# Make sure we're in the source directory for OpenJDK now
stepIntoTheWorkingDirectory() {
  cd "${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[WORKING_DIR]}/${BUILD_CONFIG[OPENJDK_SOURCE_DIR]}" || exit

  # corretto/corretto-8 (jdk-8 only) nest their source under /src in their dir
  if [ "${BUILD_CONFIG[BUILD_VARIANT]}" == "${BUILD_VARIANT_CORRETTO}" ] && [ "${BUILD_CONFIG[OPENJDK_FEATURE_NUMBER]}" == "8" ]; then
    cd "src"
  fi

  echo "Should have the source, I'm at $PWD"
}

buildTemplatedFile() {
  echo "Configuring command and using the pre-built config params..."

  stepIntoTheWorkingDirectory

  echo "Currently at '${PWD}'"

  if [[ "${BUILD_CONFIG[ASSEMBLE_EXPLODED_IMAGE]}" != "true" ]]; then
    FULL_CONFIGURE="bash ./configure --verbose ${CONFIGURE_ARGS}"
    echo "Running ./configure with arguments '${FULL_CONFIGURE}'"
  else
    FULL_CONFIGURE="echo \"Skipping configure because we're assembling an exploded image\""
    echo "Skipping configure because we're assembling an exploded image"
  fi

  # If it's Java 9+ then we also make test-image to build the native test libraries,
  # For openj9 add debug-image
  JDK_VERSION_NUMBER="${BUILD_CONFIG[OPENJDK_FEATURE_NUMBER]}"
  if [[ "${BUILD_CONFIG[BUILD_VARIANT]}" == "${BUILD_VARIANT_OPENJ9}" ]]; then
    ADDITIONAL_MAKE_TARGETS=" test-image debug-image"
  elif [ "$JDK_VERSION_NUMBER" -gt 8 ] || [ "${BUILD_CONFIG[OPENJDK_CORE_VERSION]}" == "${JDKHEAD_VERSION}" ]; then
    ADDITIONAL_MAKE_TARGETS=" test-image"
  fi

  if [[ "${BUILD_CONFIG[MAKE_EXPLODED]}" == "true" ]]; then
    # In order to make an exploded image we cannot have any additional targets
    ADDITIONAL_MAKE_TARGETS=""
  fi

  FULL_MAKE_COMMAND="${BUILD_CONFIG[MAKE_COMMAND_NAME]} ${BUILD_CONFIG[MAKE_ARGS_FOR_ANY_PLATFORM]} ${BUILD_CONFIG[USER_SUPPLIED_MAKE_ARGS]} ${ADDITIONAL_MAKE_TARGETS}"

  if [[ "${BUILD_CONFIG[ASSEMBLE_EXPLODED_IMAGE]}" == "true" ]]; then
    # This is required so that make will only touch the jmods and not re-compile them after signing
    FULL_MAKE_COMMAND="make -t \&\& ${FULL_MAKE_COMMAND}"
  fi

  # shellcheck disable=SC2002
  cat "$SCRIPT_DIR/build.template" |
    sed -e "s|{configureArg}|${FULL_CONFIGURE}|" \
      -e "s|{makeCommandArg}|${FULL_MAKE_COMMAND}|" >"${BUILD_CONFIG[WORKSPACE_DIR]}/config/configure-and-build.sh"
}

executeTemplatedFile() {
  stepIntoTheWorkingDirectory

  echo "Currently at '${PWD}'"

  # We need the exitcode from the configure-and-build.sh script
  set +eu

  # Execute the build passing the workspace dir and target dir as params for configure.txt
  bash "${BUILD_CONFIG[WORKSPACE_DIR]}/config/configure-and-build.sh" ${BUILD_CONFIG[WORKSPACE_DIR]} ${BUILD_CONFIG[TARGET_DIR]}
  exitCode=$?

  if [ "${exitCode}" -eq 3 ]; then
    createOpenJDKFailureLogsArchive
    echo "Failed to make the JDK, exiting"
    exit 1
  elif [ "${exitCode}" -eq 2 ]; then
    echo "Failed to configure the JDK, exiting"
    echo "Did you set the JDK boot directory correctly? Override by exporting JDK_BOOT_DIR"
    echo "For example, on RHEL you would do export JDK_BOOT_DIR=/usr/lib/jvm/java-1.7.0-openjdk-1.7.0.131-2.6.9.0.el7_3.x86_64"
    echo "Current JDK_BOOT_DIR value: ${BUILD_CONFIG[JDK_BOOT_DIR]}"
    exit 2
  fi

  # Restore exit behavior
  set -eu
}

createOpenJDKFailureLogsArchive() {
    echo "OpenJDK make failed, archiving make failed logs"
    cd build/*

    local adoptLogArchiveDir="TemurinLogsArchive"

    # Create new folder for failure logs
    rm -rf ${adoptLogArchiveDir}
    mkdir ${adoptLogArchiveDir}

    # Copy build and failure logs
    if [[ -f "build.log" ]]; then
      echo "Copying build.log to ${adoptLogArchiveDir}"
      cp build.log ${adoptLogArchiveDir}
    fi
    if [[ -d "make-support/failure-logs" ]]; then
      echo "Copying make-support/failure-logs to ${adoptLogArchiveDir}"
      mkdir -p "${adoptLogArchiveDir}/make-support"
      cp -r "make-support/failure-logs" "${adoptLogArchiveDir}/make-support"
    fi

    # Find any cores, dumps, ..
    find . -name 'core.*' -o -name 'core.*.dmp' -o -name 'javacore.*.txt' -o -name 'Snap.*.trc' -o -name 'jitdump.*.dmp' | sed 's#^./##' | while read -r dump ; do
      filedir=$(dirname "${dump}")
      echo "Copying ${dump} to ${adoptLogArchiveDir}/${filedir}"
      mkdir -p "${adoptLogArchiveDir}/${filedir}"
      cp "${dump}" "${adoptLogArchiveDir}/${filedir}"
    done

    # Archive logs
    local makeFailureLogsName=$(echo "${BUILD_CONFIG[TARGET_FILE_NAME]//-jdk/-makefailurelogs}")
    createArchive "${adoptLogArchiveDir}" "${makeFailureLogsName}"
}

getGradleJavaHome() {
  local gradleJavaHome=""

  if [ ${JAVA_HOME+x} ] && [ -d "${JAVA_HOME}" ]; then
    gradleJavaHome=${JAVA_HOME}
  fi

  if [ ${JDK8_BOOT_DIR+x} ] && [ -d "${JDK8_BOOT_DIR}" ]; then
    gradleJavaHome=${JDK8_BOOT_DIR}
  fi

  # Special case arm because for some unknown reason the JDK11_BOOT_DIR that arm downloads is unable to form connection
  # to services.gradle.org
  if [ ${JDK11_BOOT_DIR+x} ] && [ -d "${JDK11_BOOT_DIR}" ] && [ "${ARCHITECTURE}" != "arm" ]; then
    gradleJavaHome=${JDK11_BOOT_DIR}
  fi

  if [ ! -d "$gradleJavaHome" ]; then
    echo "[WARNING] Unable to find java to run gradle with, this build may fail with /bin/java: No such file or directory. Set JAVA_HOME, JDK8_BOOT_DIR or JDK11_BOOT_DIR to squash this warning: $gradleJavaHome" >&2
  fi

  echo "$gradleJavaHome"
}

getGradleUserHome() {
  local gradleUserHome=""

  if [ -n "${BUILD_CONFIG[GRADLE_USER_HOME_DIR]}" ]; then
    gradleUserHome="${BUILD_CONFIG[GRADLE_USER_HOME_DIR]}"
  else
    gradleUserHome="${BUILD_CONFIG[WORKSPACE_DIR]}/.gradle"
  fi

  echo $gradleUserHome
}

parseJavaVersionString() {
  ADOPT_BUILD_NUMBER="${ADOPT_BUILD_NUMBER:-1}"

  local javaVersion=$(JAVA_HOME="$PRODUCT_HOME" "$PRODUCT_HOME"/bin/java -version 2>&1)

  cd "${LIB_DIR}"
  local gradleJavaHome=$(getGradleJavaHome)
  local version=$(echo "$javaVersion" | JAVA_HOME="$gradleJavaHome" "$gradleJavaHome"/bin/java -cp "target/libs/adopt-shared-lib.jar" ParseVersion -s -f openjdk-semver "$ADOPT_BUILD_NUMBER" | tr -d '\n')

  echo "$version"
}

# Print the version string so we know what we've produced
printJavaVersionString() {
  stepIntoTheWorkingDirectory

  case "${BUILD_CONFIG[OS_KERNEL_NAME]}" in
  "darwin")
    # shellcheck disable=SC2086
    PRODUCT_HOME=$(ls -d ${PWD}/build/*/images/${BUILD_CONFIG[JDK_PATH]}/Contents/Home)
    ;;
  *)
    # shellcheck disable=SC2086
    PRODUCT_HOME=$(ls -d ${PWD}/build/*/images/${BUILD_CONFIG[JDK_PATH]})
    ;;
  esac
  if [[ -d "$PRODUCT_HOME" ]]; then
     echo "'$PRODUCT_HOME' found"
     if [ ! -r "$PRODUCT_HOME/bin/java" ]; then
       echo "===$PRODUCT_HOME===="
       ls -alh "$PRODUCT_HOME"

       echo "===$PRODUCT_HOME/bin/===="
       ls -alh "$PRODUCT_HOME/bin/"

       echo "Error 'java' does not exist in '$PRODUCT_HOME'."
       exit 3
     elif [ "${BUILD_CONFIG[CROSSCOMPILE]}" == "true" ]; then
       # job is cross compiled, so we cannot run it on the build system
       # So we leave it for now and retrive the version from a downstream job after the build
       echo "Warning: java version can't be run on cross compiled build system. Faking version for now..."
     else
       # print version string around easy to find output
       # do not modify these strings as jenkins looks for them
       echo "=JAVA VERSION OUTPUT="
       "$PRODUCT_HOME"/bin/java -version 2>&1
       echo "=/JAVA VERSION OUTPUT="

       "$PRODUCT_HOME"/bin/java -version > "${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[TARGET_DIR]}/metadata/version.txt" 2>&1
     fi
  else
    echo "'$PRODUCT_HOME' does not exist, build might have not been successful or not produced the expected JDK image at this location."
    exit 3
  fi
}

getJdkArchivePath() {
  # Todo: Set this to the outcome of https://github.com/adoptium/temurin-build/issues/1016
  # local version="$(parseJavaVersionString)
  # echo "jdk-${version}"

  local version=$(getOpenJdkVersion)
  echo "$version"
}

getJreArchivePath() {
  local jdkArchivePath=$(getJdkArchivePath)
  echo "${jdkArchivePath}-jre"
}

getTestImageArchivePath() {
  local jdkArchivePath=$(getJdkArchivePath)
  echo "${jdkArchivePath}-test-image"
}

getDebugImageArchivePath() {
  local jdkArchivePath=$(getJdkArchivePath)
  echo "${jdkArchivePath}-debug-image"
}

# Clean up
removingUnnecessaryFiles() {
  local jdkTargetPath=$(getJdkArchivePath)
  local jreTargetPath=$(getJreArchivePath)
  local testImageTargetPath=$(getTestImageArchivePath)
  local debugImageTargetPath=$(getDebugImageArchivePath)

  echo "Removing unnecessary files now..."

  stepIntoTheWorkingDirectory

  cd build/*/images || return

  echo "Currently at '${PWD}'"

  local jdkPath=$(ls -d ${BUILD_CONFIG[JDK_PATH]})
  echo "moving ${jdkPath} to ${jdkTargetPath}"
  rm -rf "${jdkTargetPath}" || true
  mv "${jdkPath}" "${jdkTargetPath}"

  if [ -d "$(ls -d ${BUILD_CONFIG[JRE_PATH]})" ]; then
    echo "moving $(ls -d ${BUILD_CONFIG[JRE_PATH]}) to ${jreTargetPath}"
    rm -rf "${jreTargetPath}" || true
    mv "$(ls -d ${BUILD_CONFIG[JRE_PATH]})" "${jreTargetPath}"

    case "${BUILD_CONFIG[OS_KERNEL_NAME]}" in
    "darwin") dirToRemove="${jreTargetPath}/Contents/Home" ;;
    *) dirToRemove="${jreTargetPath}" ;;
    esac
    rm -rf "${dirToRemove}"/demo || true
  fi

  # Test image - check if the config is set and directory exists
  local testImagePath="${BUILD_CONFIG[TEST_IMAGE_PATH]}"
  if [ -n "${testImagePath}" ] && [ -d "${testImagePath}" ]; then
    echo "moving ${testImagePath} to ${testImageTargetPath}"
    rm -rf "${testImageTargetPath}" || true
    mv "${testImagePath}" "${testImageTargetPath}"
  fi

  # Debug image - check if the config is set and directory exists
  local debugImagePath="${BUILD_CONFIG[DEBUG_IMAGE_PATH]}"
  if [ -n "${debugImagePath}" ] && [ -d "${debugImagePath}" ]; then
    echo "moving ${debugImagePath} to ${debugImageTargetPath}"
    rm -rf "${debugImageTargetPath}" || true
    mv "${debugImagePath}" "${debugImageTargetPath}"
  fi

  # Remove files we don't need
  case "${BUILD_CONFIG[OS_KERNEL_NAME]}" in
  "darwin") dirToRemove="${jdkTargetPath}/Contents/Home" ;;
  *) dirToRemove="${jdkTargetPath}" ;;
  esac
  rm -rf "${dirToRemove}"/demo || true

  # In OpenJ9 builds, debug symbols are captured in the debug image:
  # we don't want another copy of them in the main JDK or JRE archives.
  # Builds for other variants don't normally include debug symbols,
  # but if they were explicitly requested via the configure option
  # '--with-native-debug-symbols=(external|zipped)' leave them alone.
  if [[ "${BUILD_CONFIG[BUILD_VARIANT]}" == "${BUILD_VARIANT_OPENJ9}" ]]; then
    deleteDebugSymbols
  fi

  if [ ${BUILD_CONFIG[CREATE_DEBUG_IMAGE]} == true ] && [ "${BUILD_CONFIG[BUILD_VARIANT]}" != "${BUILD_VARIANT_OPENJ9}" ]; then
    case "${BUILD_CONFIG[OS_KERNEL_NAME]}" in
    *cygwin*)
      # on Windows, we want to take .pdb and .map files
      debugSymbols=$(find "${jdkTargetPath}" -type f -name "*.pdb" -o -name "*.map")
      ;;
    darwin)
      # on MacOSX, we want to take the files within the .dSYM folders
      debugSymbols=$(find "${jdkTargetPath}" -type d -name "*.dSYM" | xargs -I {} find "{}" -type f)
      ;;
    *)
      # on other platforms, we want to take .debuginfo files
      debugSymbols=$(find "${jdkTargetPath}" -type f -name "*.debuginfo")
      ;;
    esac

    # if debug symbols were found, copy them to a different folder
    if [ -n "${debugSymbols}" ]; then
      echo "Copying found debug symbols to ${debugImageTargetPath}"
      mkdir -p "${debugImageTargetPath}"
      echo "${debugSymbols}" | cpio -pdm "${debugImageTargetPath}"
    fi

    deleteDebugSymbols
  fi

  echo "Finished removing unnecessary files from ${jdkTargetPath}"
}

deleteDebugSymbols() {
  # .diz files may be present on any platform
  # Note that on AIX, find does not support the '-delete' option.
  find "${jdkTargetPath}" "${jreTargetPath}" -type f -name "*.diz" | xargs rm -f || true

  case "${BUILD_CONFIG[OS_KERNEL_NAME]}" in
  *cygwin*)
    # on Windows, we want to remove .map and .pdb files
    find "${jdkTargetPath}" "${jreTargetPath}" -type f -name "*.map" -delete || true
    find "${jdkTargetPath}" "${jreTargetPath}" -type f -name "*.pdb" -delete || true
    ;;
  darwin)
    # on MacOSX, we want to remove .dSYM folders
    find "${jdkTargetPath}" "${jreTargetPath}" -type d -name "*.dSYM" | xargs -I "{}" rm -rf "{}"
    ;;
  *)
    # on other platforms, we want to remove .debuginfo files
    find "${jdkTargetPath}" "${jreTargetPath}" -name "*.debuginfo" | xargs rm -f || true
    ;;
  esac
}

moveFreetypeLib() {
  local LIB_DIRECTORY="${1}"

  if [ ! -d "${LIB_DIRECTORY}" ]; then
    echo "Could not find dir: ${LIB_DIRECTORY}"
    return
  fi

  echo " Performing copying of the free font library to ${LIB_DIRECTORY}, applicable for this version of the JDK. "

  local SOURCE_LIB_NAME="${LIB_DIRECTORY}/libfreetype.dylib.6"

  if [ ! -f "${SOURCE_LIB_NAME}" ]; then
    SOURCE_LIB_NAME="${LIB_DIRECTORY}/libfreetype.dylib"
  fi

  if [ ! -f "${SOURCE_LIB_NAME}" ]; then
    echo "[Error] ${SOURCE_LIB_NAME} does not exist in the ${LIB_DIRECTORY} folder, please check if this is the right folder to refer to, aborting copy process..."
    return
  fi

  local TARGET_LIB_NAME="${LIB_DIRECTORY}/libfreetype.6.dylib"

  local INVOKED_BY_FONT_MANAGER="${LIB_DIRECTORY}/libfontmanager.dylib"

  echo "Currently at '${PWD}'"
  echo "Copying ${SOURCE_LIB_NAME} to ${TARGET_LIB_NAME}"
  echo " *** Workaround to fix the MacOSX issue where invocation to ${INVOKED_BY_FONT_MANAGER} fails to find ${TARGET_LIB_NAME} ***"

  # codesign freetype before it is bundled
  if [ -n "${BUILD_CONFIG[MACOSX_CODESIGN_IDENTITY]}" ]; then
    # test if codesign certificate is usable
    if touch test && codesign --sign "Developer ID Application: London Jamocha Community CIC" test && rm -rf test; then
      ENTITLEMENTS="$WORKSPACE/entitlements.plist"
      codesign --entitlements "$ENTITLEMENTS" --options runtime --timestamp --sign "${BUILD_CONFIG[MACOSX_CODESIGN_IDENTITY]}" "${SOURCE_LIB_NAME}"
    else
      echo "skipping codesign as certificate cannot be found"
    fi
  fi

  cp "${SOURCE_LIB_NAME}" "${TARGET_LIB_NAME}"
  if [ -f "${INVOKED_BY_FONT_MANAGER}" ]; then
    otool -L "${INVOKED_BY_FONT_MANAGER}"
  else
    # shellcheck disable=SC2154
    echo "[Warning] ${INVOKED_BY_FONT_MANAGER} does not exist in the ${LIB_DIRECTORY} folder, please check if this is the right folder to refer to, this may cause runtime issues, please beware..."
  fi

  otool -L "${TARGET_LIB_NAME}"

  echo "Finished copying ${SOURCE_LIB_NAME} to ${TARGET_LIB_NAME}"
}

# If on a Mac, make a copy of the font lib as required
makeACopyOfLibFreeFontForMacOSX() {
  local DIRECTORY="${1}"
  local PERFORM_COPYING=$2

  echo "PERFORM_COPYING=${PERFORM_COPYING}"
  if [ "${PERFORM_COPYING}" == "false" ]; then
    echo " Skipping copying of the free font library to ${DIRECTORY}, does not apply for this version of the JDK. "
    return
  fi

  if [[ "${BUILD_CONFIG[OS_KERNEL_NAME]}" == "darwin" ]]; then
    moveFreetypeLib "${DIRECTORY}/Contents/Home/lib"
    moveFreetypeLib "${DIRECTORY}/Contents/Home/jre/lib"
  fi
}

# Creates the notice file to be shipped with all binary distributions. See https://github.com/adoptium/adoptium/issues/20
createNoticeFile() {
  local DIRECTORY="${1}"
  local TYPE="${2}"

  # Only perform these steps for EF builds
  if [[ "${BUILD_CONFIG[VENDOR]}" == "Eclipse Foundation" ]]; then
    if [[ "${BUILD_CONFIG[OS_KERNEL_NAME]}" == "darwin" ]]; then
      HOME_DIR="${DIRECTORY}/Contents/home/"
    else
      HOME_DIR="${DIRECTORY}"
    fi
    cp "${SCRIPT_DIR}/NOTICE.template" "${HOME_DIR}/NOTICE"
  fi
}

# If on a Mac, we need to modify the plist values
setPlistValueForMacOS() {
  local DIRECTORY="${1}"
  local TYPE="${2}"

  # Only perform these steps for EF builds
  if [[ "${BUILD_CONFIG[VENDOR]}" == "Eclipse Foundation" ]]; then
    VENDOR_NAME="temurin"
    PACKAGE_NAME="Eclipse Temurin"
    MAJOR_VERSION="${BUILD_CONFIG[OPENJDK_FEATURE_NUMBER]}"

    if [[ "${BUILD_CONFIG[OS_KERNEL_NAME]}" == "darwin" ]]; then

      local JAVA_LOC="${DIRECTORY}/Contents/home/bin/java"
      local FULL_VERSION=$($JAVA_LOC -XshowSettings:properties -version 2>&1 | grep 'java.runtime.version' | sed 's/^.*= //' | tr -d '\r')

      case "${BUILD_CONFIG[BUILD_VARIANT]}" in
        openj9)
          IDENTIFIER="net.${VENDOR_NAME}.${MAJOR_VERSION}-openj9.${TYPE}"
          BUNDLE="${PACKAGE_NAME} (OpenJ9)"
          case $TYPE in
            jre) BUNDLE="${PACKAGE_NAME} (OpenJ9, JRE)" ;;
            jdk) BUNDLE="${PACKAGE_NAME} (OpenJ9)" ;;
          esac
          ;;
        *)
          IDENTIFIER="net.${VENDOR_NAME}.${MAJOR_VERSION}.${TYPE}"
          case $TYPE in
            jre) BUNDLE="${PACKAGE_NAME} (JRE)" ;;
            jdk) BUNDLE="${PACKAGE_NAME}" ;;
          esac
          ;;
      esac

      mkdir -p "${DIRECTORY}/Contents/Home/bundle/Libraries"
      if [ -f "${DIRECTORY}/Contents/Home/lib/server/libjvm.dylib" ]; then
        cp "${DIRECTORY}/Contents/Home/lib/server/libjvm.dylib" "${DIRECTORY}/Contents/Home/bundle/Libraries/libserver.dylib"
      else
        cp "${DIRECTORY}/Contents/Home/jre/lib/server/libjvm.dylib" "${DIRECTORY}/Contents/Home/bundle/Libraries/libserver.dylib"
      fi

      if [ "$TYPE" == "jre" ]; then
        /usr/libexec/PlistBuddy -c "Add :JavaVM:JVMCapabilities array" "${DIRECTORY}/Contents/Info.plist"
        /usr/libexec/PlistBuddy -c "Add :JavaVM:JVMCapabilities:0 string CommandLine" "${DIRECTORY}/Contents/Info.plist"
      fi

      /usr/libexec/PlistBuddy -c "Set :CFBundleGetInfoString ${BUNDLE} ${FULL_VERSION}" "${DIRECTORY}/Contents/Info.plist"
      /usr/libexec/PlistBuddy -c "Set :CFBundleName ${BUNDLE} ${MAJOR_VERSION}" "${DIRECTORY}/Contents/Info.plist"
      /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier ${IDENTIFIER}" "${DIRECTORY}/Contents/Info.plist"
      /usr/libexec/PlistBuddy -c "Set :JavaVM:JVMPlatformVersion ${FULL_VERSION}" "${DIRECTORY}/Contents/Info.plist"
      /usr/libexec/PlistBuddy -c "Set :JavaVM:JVMVendor ${PACKAGE_NAME}" "${DIRECTORY}/Contents/Info.plist"

      # Fix comes from https://apple.stackexchange.com/a/211033 to associate JAR files
      /usr/libexec/PlistBuddy -c "Add :JavaVM:JVMCapabilities:1 string JNI" "${DIRECTORY}/Contents/Info.plist"
      /usr/libexec/PlistBuddy -c "Add :JavaVM:JVMCapabilities:2 string BundledApp" "${DIRECTORY}/Contents/Info.plist"
    fi
  fi
}

# JDK8 tag selection
# Version tags are expected to follow this pattern:
#   jdk8uV-bB
# where V and B are numeric.
# - answer the largest matching tag based on the version ordering of V.B
#
getLatestTagJDK8() {
  local max_tag=
  local max_v=
  local max_b=

  while read -r tag ; do
    if [[ "$tag" =~ ^jdk8u([0-9]+)-b([0-9]+)$ ]] ; then
      local better=0
      local cur_v=${BASH_REMATCH[1]}
      local cur_b=${BASH_REMATCH[2]}

      if [ -z "$max_tag" ] ; then
        better=1
      elif [ "$cur_v" -gt "$max_v" ] ; then
        better=1
      elif [ "$cur_v" -eq "$max_v" ] && [ "$cur_b" -gt "$max_b" ] ; then
        better=1
      fi

      if [ "$better" -ne 0 ] ; then
        max_tag="$tag"
        max_v="$cur_v"
        max_b="$cur_b"
      fi
    fi
  done

  if [ -n "$max_tag" ] ; then
    echo "$max_tag"
  fi
}

# JDK11+ tag selection
# Version tags are expected to follow this pattern:
#   jdk-V[.W[.X[.P]]]+B
# where V, W, X, P and B are numeric (missing components are considered to be 0).
# - answer the largest matching tag based on the version ordering of V.W.X.P+B
#
getLatestTagJDK11plus() {
  local max_tag=
  local max_v=
  local max_w=
  local max_x=
  local max_p=
  local max_b=

  while read -r tag ; do
    if [[ "$tag" =~ ^jdk-([0-9]+)(\.([0-9]+))?(\.([0-9]+))?(\.([0-9]+))?\+([0-9]+)$ ]] ; then
      local better=0
      local cur_v=${BASH_REMATCH[1]}
      local cur_w=${BASH_REMATCH[3]:-0}
      local cur_x=${BASH_REMATCH[5]:-0}
      local cur_p=${BASH_REMATCH[7]:-0}
      local cur_b=${BASH_REMATCH[8]:-0}

      if [ -z "$max_tag" ] ; then
        better=1
      elif [ "$cur_v" -gt "$max_v" ] ; then
        better=1
      elif [ "$cur_v" -eq "$max_v" ] ; then
        if [ "$cur_w" -gt "$max_w" ] ; then
          better=1
        elif [ "$cur_w" -eq "$max_w" ] ; then
          if [ "$cur_x" -gt "$max_x" ] ; then
            better=1
          elif [ "$cur_x" -eq "$max_x" ] ; then
            if [ "$cur_p" -gt "$max_p" ] ; then
              better=1
            elif [ "$cur_p" -eq "$max_p" ] && [ "$cur_b" -gt "$max_b" ] ; then
              better=1
            fi
          fi
        fi
      fi

      if [ "$better" -ne 0 ] ; then
        max_tag="$tag"
        max_v="$cur_v"
        max_w="$cur_w"
        max_x="$cur_x"
        max_p="$cur_p"
        max_b="$cur_b"
      fi
    fi
  done

  if [ -n "$max_tag" ] ; then
    echo "$max_tag"
  fi
}

# Get the tags from the git repo and choose the latest numerically ordered tag for the given JDK version.
#
getFirstTagFromOpenJDKGitRepo() {

  # Save current directory of caller so we can return to that directory at the end of this function.
  # Some callers are not in the git repo root, but instead build/*/images directory like the archive functions
  # and any function called after removingUnnecessaryFiles().
  local savePwd="${PWD}"

  # Change to openjdk git repo root to find build tag.
  cd "${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[WORKING_DIR]}/${BUILD_CONFIG[OPENJDK_SOURCE_DIR]}"

  # Choose tag search keyword and get cmd based on version.
  local TAG_SEARCH="jdk-${BUILD_CONFIG[OPENJDK_FEATURE_NUMBER]}*+*"
  local get_tag_cmd=getLatestTagJDK11plus
  if [ "${BUILD_CONFIG[OPENJDK_FEATURE_NUMBER]}" == "8" ]; then
    TAG_SEARCH="jdk8u*-b*"
    get_tag_cmd=getLatestTagJDK8
  fi

  if [ "${BUILD_CONFIG[BUILD_VARIANT]}" == "${BUILD_VARIANT_DRAGONWELL}" ]; then
    TAG_SEARCH="dragonwell-*_jdk*"
  fi

  if [ "${BUILD_CONFIG[BUILD_VARIANT]}" == "${BUILD_VARIANT_BISHENG}" ] && [ "${BUILD_CONFIG[OS_ARCHITECTURE]}" == "riscv64" ]; then
    TAG_SEARCH="jdk-*+*bisheng_riscv"
  elif [ "${BUILD_CONFIG[BUILD_VARIANT]}" == "${BUILD_VARIANT_BISHENG}" ] && [ "${BUILD_CONFIG[OPENJDK_FEATURE_NUMBER]}" == "8" ]; then
    # Bisheng's JDK8 tags follow the aarch64 convention
    TAG_SEARCH="aarch64-shenandoah-jdk8u*-b*"
  fi

  # If openj9 and the closed/openjdk-tag.gmk file exists which specifies what level the openj9 jdk code is based upon,
  # read OPENJDK_TAG value from that file.
  local openj9_openjdk_tag_file="${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[WORKING_DIR]}/${BUILD_CONFIG[OPENJDK_SOURCE_DIR]}/closed/openjdk-tag.gmk"
  if [[ "${BUILD_CONFIG[BUILD_VARIANT]}" == "${BUILD_VARIANT_OPENJ9}" ]] && [[ -f "${openj9_openjdk_tag_file}" ]]; then
    firstMatchingNameFromRepo=$(grep OPENJDK_TAG ${openj9_openjdk_tag_file} | awk 'BEGIN {FS = "[ :=]+"} {print $2}')
  else
    git fetch --tags "${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[WORKING_DIR]}/${BUILD_CONFIG[OPENJDK_SOURCE_DIR]}"
    firstMatchingNameFromRepo=$(git tag --list "$TAG_SEARCH" | "$get_tag_cmd")
  fi

  if [ -z "$firstMatchingNameFromRepo" ]; then
    echo "WARNING: Failed to identify latest tag in the repository" 1>&2
    # If the ADOPT_BRANCH_SAFETY flag is set, we may be building from an alternate
    # repository that doesn't have the same tags, so allow defaults. For a better 
    # options see https://github.com/adoptium/temurin-build/issues/2671
    if [ "${BUILD_CONFIG[DISABLE_ADOPT_BRANCH_SAFETY]}" == "true" ]; then
      if [ "${BUILD_CONFIG[OPENJDK_FEATURE_NUMBER]}" == "8" ]; then
         echo "WARNING: Could not identify latest tag but the ADOPT_BRANCH_SAFETY flag is off so defaulting to 8u000-b00" 1>&2
         echo "8u000-b00"
      else
         echo "WARNING: Could not identify latest tag but the ADOPT_BRANCH_SAFETY flag is off so defaulting to jdk-${BUILD_CONFIG[OPENJDK_FEATURE_NUMBER]}.0.0+0" 1>&2
         echo "jdk-${BUILD_CONFIG[OPENJDK_FEATURE_NUMBER]}.0.0+0"
      fi
    else
      echo "WARNING: Failed to identify latest tag in the repository" 1>&2
    fi
  else
    echo "$firstMatchingNameFromRepo"
  fi

  # Restore current directory.
  cd "$savePwd"
}

createArchive() {
  repoLocation=$1
  targetName=$2

  archiveExtension=$(getArchiveExtension)

  createOpenJDKArchive "${repoLocation}" "OpenJDK"
  archive="${PWD}/OpenJDK${archiveExtension}"

  echo "Your final archive was created at ${archive}"

  echo "Moving the artifact to ${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[TARGET_DIR]}"
  mv "${archive}" "${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[TARGET_DIR]}/${targetName}"
}

# Create a Tar ball
createOpenJDKTarArchive() {
  local jdkTargetPath=$(getJdkArchivePath)
  local jreTargetPath=$(getJreArchivePath)
  local testImageTargetPath=$(getTestImageArchivePath)
  local debugImageTargetPath=$(getDebugImageArchivePath)

  echo "OpenJDK JDK path will be ${jdkTargetPath}. JRE path will be ${jreTargetPath}"

  if [ -d "${jreTargetPath}" ]; then
    # shellcheck disable=SC2001
    local jreName=$(echo "${BUILD_CONFIG[TARGET_FILE_NAME]}" | sed 's/-jdk/-jre/')
    createArchive "${jreTargetPath}" "${jreName}"
  fi
  if [ -d "${testImageTargetPath}" ]; then
    echo "OpenJDK test image path will be ${testImageTargetPath}."
    local testImageName=$(echo "${BUILD_CONFIG[TARGET_FILE_NAME]//-jdk/-testimage}")
    createArchive "${testImageTargetPath}" "${testImageName}"
  fi
  if [ -d "${debugImageTargetPath}" ]; then
    echo "OpenJDK debug image path will be ${debugImageTargetPath}."
    local debugImageName=$(echo "${BUILD_CONFIG[TARGET_FILE_NAME]//-jdk/-debugimage}")
    createArchive "${debugImageTargetPath}" "${debugImageName}"
  fi
  createArchive "${jdkTargetPath}" "${BUILD_CONFIG[TARGET_FILE_NAME]}"
}

copyFreeFontForMacOS() {
  local jdkTargetPath=$(getJdkArchivePath)
  local jreTargetPath=$(getJreArchivePath)

  makeACopyOfLibFreeFontForMacOSX "${jdkTargetPath}" "${BUILD_CONFIG[COPY_MACOSX_FREE_FONT_LIB_FOR_JDK_FLAG]}"
  makeACopyOfLibFreeFontForMacOSX "${jreTargetPath}" "${BUILD_CONFIG[COPY_MACOSX_FREE_FONT_LIB_FOR_JRE_FLAG]}"
}

setPlistForMacOS() {
  local jdkTargetPath=$(getJdkArchivePath)
  local jreTargetPath=$(getJreArchivePath)

  setPlistValueForMacOS "${jdkTargetPath}" "jdk"
  setPlistValueForMacOS "${jreTargetPath}" "jre"
}

addNoticeFile() {
  local jdkTargetPath=$(getJdkArchivePath)
  local jreTargetPath=$(getJreArchivePath)

  createNoticeFile "${jdkTargetPath}" "jdk"
  createNoticeFile "${jreTargetPath}" "jre"
}

wipeOutOldTargetDir() {
  rm -r "${BUILD_CONFIG[WORKSPACE_DIR]:?}/${BUILD_CONFIG[TARGET_DIR]}" || true
}

createTargetDir() {
  # clean out old builds
  mkdir -p "${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[TARGET_DIR]}" || exit
  mkdir "${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[TARGET_DIR]}/metadata" || exit
  if [ "${BUILD_CONFIG[BUILD_VARIANT]}" == "${BUILD_VARIANT_OPENJ9}" ]; then
    mkdir "${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[TARGET_DIR]}/metadata/variant_version" || exit
  fi
}

fixJavaHomeUnderDocker() {
  # If we are inside docker we cannot trust the JDK_BOOT_DIR that was detected on the host system
  if [[ "${BUILD_CONFIG[USE_DOCKER]}" == "true" ]]; then
    # clear BUILD_CONFIG[JDK_BOOT_DIR] and re set it
    BUILD_CONFIG[JDK_BOOT_DIR]=""
    setBootJdk
  fi
}

addInfoToReleaseFile() {
  # Extra information is added to the release file here
  echo "===GENERATING RELEASE FILE==="
  cd "$PRODUCT_HOME"
  JAVA_LOC="$PRODUCT_HOME/bin/java"
  echo "ADDING IMPLEMENTOR"
  addImplementor
  echo "ADDING BUILD SHA"
  addBuildSHA
  echo "ADDING BUILD SOURCE REPO"
  addBuildSourceRepo
  echo "ADDING OPENJDK SOURCE REPO"
  addOpenJDKSourceRepo
  echo "ADDING FULL VER"
  addFullVersion
  echo "ADDING SEM VER"
  addSemVer
  echo "ADDING BUILD OS"
  addBuildOS
  echo "ADDING VARIANT"
  addJVMVariant
  echo "ADDING JVM VERSION"
  addJVMVersion
  # OpenJ9 specific options
  if [ "${BUILD_CONFIG[BUILD_VARIANT]}" == "${BUILD_VARIANT_OPENJ9}" ]; then
    echo "ADDING J9 TAG"
    addJ9Tag
  fi
  echo "MIRRORING TO JRE"
  mirrorToJRE
  echo "ADDING IMAGE TYPE"
  addImageType
  echo "===RELEASE FILE GENERATED==="
}

addImplementor() {
  if [ "${BUILD_CONFIG[OPENJDK_CORE_VERSION]}" == "${JDK8_CORE_VERSION}" ]; then
    # shellcheck disable=SC2086
    echo -e IMPLEMENTOR=\"${BUILD_CONFIG[VENDOR]}\" >>release
  fi
}

addJVMVersion() { # Adds the JVM version i.e. openj9-0.21.0
  local jvmVersion=$($JAVA_LOC -XshowSettings:properties -version 2>&1 | grep 'java.vm.version' | sed 's/^.*= //' | tr -d '\r')
  # shellcheck disable=SC2086
  echo -e JVM_VERSION=\"$jvmVersion\" >>release
}

addFullVersion() { # Adds the full version including build number i.e. 11.0.9+5-202009040847
  local fullVer=$($JAVA_LOC -XshowSettings:properties -version 2>&1 | grep 'java.runtime.version' | sed 's/^.*= //' | tr -d '\r')
  # shellcheck disable=SC2086
  echo -e FULL_VERSION=\"$fullVer\" >>release
}

addJVMVariant() {
  # shellcheck disable=SC2086
  echo -e JVM_VARIANT=\"${BUILD_CONFIG[BUILD_VARIANT]^}\" >>release
}

addBuildSHA() { # git SHA of the build repository i.e. openjdk-build
  local buildSHA=$(git -C "${BUILD_CONFIG[WORKSPACE_DIR]}" rev-parse --short HEAD 2>/dev/null)
  if [[ $buildSHA ]]; then
    # shellcheck disable=SC2086
    echo -e BUILD_SOURCE=\"git:$buildSHA\" >>release
  else
    echo "Unable to fetch build SHA, does a work tree exist?..."
  fi
}

addBuildSourceRepo() { # name of git repo for which BUILD_SOURCE sha is from
  local buildSourceRepo=$(git -C "${BUILD_CONFIG[WORKSPACE_DIR]}" config --get remote.origin.url 2>/dev/null)
  if [[ $buildSourceRepo ]]; then
    # shellcheck disable=SC2086
    echo -e BUILD_SOURCE_REPO=\"$buildSourceRepo\" >>release
  else
    echo "Unable to fetch Build Source Repo, does a work tree exist?..."
  fi
}

addOpenJDKSourceRepo() { # name of git repo for which SOURCE sha is from
  local openjdkSourceRepo=$(git -C "${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[WORKING_DIR]}/${BUILD_CONFIG[OPENJDK_SOURCE_DIR]}" config --get remote.origin.url 2>/dev/null)
  if [[ $openjdkSourceRepo ]]; then
    # shellcheck disable=SC2086
    echo -e SOURCE_REPO=\"$openjdkSourceRepo\" >>release
  else
    echo "Unable to fetch OpenJDK Source Repo, does a work tree exist?..."
  fi
}

addBuildOS() {
  local buildOS="Unknown"
  local buildVer="Unknown"
  if [ "${BUILD_CONFIG[OS_KERNEL_NAME]}" == "darwin" ]; then
    buildOS=$(sw_vers | sed -n 's/^ProductName:[[:blank:]]*//p')
    buildVer=$(sw_vers | tail -n 2 | awk '{print $2}')
  elif [ "${BUILD_CONFIG[OS_KERNEL_NAME]}" == "linux" ]; then
    buildOS=$(uname -s)
    buildVer=$(uname -r)
  else # Fall back to java properties OS/Version info
    buildOS=$($JAVA_LOC -XshowSettings:properties -version 2>&1 | grep 'os.name' | sed 's/^.*= //' | tr -d '\r')
    buildVer=$($JAVA_LOC -XshowSettings:properties -version 2>&1 | grep 'os.version' | sed 's/^.*= //' | tr -d '\r')
  fi
  echo -e BUILD_INFO=\"OS: "$buildOS" Version: "$buildVer"\" >>release
}

addJ9Tag() {
  # java.vm.version varies for OpenJ9 depending on if it is a release build i.e. master-*gitSha* or 0.21.0
  # This code makes sure that a version number is always present in the release file i.e. openj9-0.21.0
  local j9Location="${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[WORKING_DIR]}/${BUILD_CONFIG[OPENJDK_SOURCE_DIR]}/openj9"
  # Pull the tag associated with the J9 commit being used
  J9_TAG=$(git -C $j9Location describe --abbrev=0)
  # shellcheck disable=SC2086
  if [ ${BUILD_CONFIG[RELEASE]} = false ]; then
    echo -e OPENJ9_TAG=\"$J9_TAG\" >> release
  fi
}

addSemVer() { # Pulls the semantic version from the tag associated with the openjdk repo
  local fullVer=$(getOpenJdkVersion)
  SEM_VER="$fullVer"
  if [ "${BUILD_CONFIG[OPENJDK_CORE_VERSION]}" == "${JDK8_CORE_VERSION}" ]; then
    # Translate jdk8uNNN-bBB to 8.0.NNN.BB, where NNN is any number and BB is 2 digits removing leading 0 if present
    # eg. jdk8u302-b00 => 8.0.302.0
    # eg. jdk8u292-b10 => 8.0.292.10
    SEM_VER=$(echo "$SEM_VER" | cut -c4- | awk -F'[-b]+' '{print $1"+"$2}' | sed 's/u/.0./' | sed 's/\+0/\+/')
  else
    SEM_VER=$(echo "$SEM_VER" | cut -c5-) # i.e. 11.0.2+12
  fi
  # shellcheck disable=SC2086
  echo -e SEMANTIC_VERSION=\"$SEM_VER\" >> release
}

# Disable shellcheck in here as it causes issues with ls on mac
mirrorToJRE() {
  stepIntoTheWorkingDirectory

  # shellcheck disable=SC2086
  case "${BUILD_CONFIG[OS_KERNEL_NAME]}" in
  "darwin")
    JRE_HOME=$(ls -d ${PWD}/build/*/images/${BUILD_CONFIG[JRE_PATH]}/Contents/Home)
    ;;
  *)
    JRE_HOME=$(ls -d ${PWD}/build/*/images/${BUILD_CONFIG[JRE_PATH]})
    ;;
  esac

  # shellcheck disable=SC2086
  cp -f $PRODUCT_HOME/release $JRE_HOME/release
}

addImageType() {
  echo -e IMAGE_TYPE=\"JDK\" >>"$PRODUCT_HOME/release"
  echo -e IMAGE_TYPE=\"JRE\" >>"$JRE_HOME/release"
}

addInfoToJson(){
  mv "${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[TARGET_DIR]}/configure.txt" "${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[TARGET_DIR]}/metadata/"
  mv "${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[TARGET_DIR]}/makeCommandArg.txt" "${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[TARGET_DIR]}/metadata/"
  addVariantVersionToJson
  addVendorToJson
  addSourceToJson # Build repository and commit SHA
  addOpenJDKSourceToJson # OpenJDK repository and commit SHA
}

addVariantVersionToJson(){
  if [ "${BUILD_CONFIG[BUILD_VARIANT]}" == "${BUILD_VARIANT_OPENJ9}" ]; then
    local variantJson=$(echo "$J9_TAG" | cut -c8- | tr "-" ".") # i.e. 0.22.0.m2
    local major=$(echo "$variantJson" | awk -F[.] '{print $1}')
    local minor=$(echo "$variantJson" | awk -F[.] '{print $2}')
    local security=$(echo "$variantJson" | awk -F[.] '{print $3}')
    local tags=$(echo "$variantJson" | awk -F[.] '{print $4}')
    if [[ $(echo "$variantJson" | tr -cd '.' | wc -c) -lt 3 ]]; then # Precaution for when OpenJ9 releases a 1.0.0 version
      tags="$minor"
      minor=""
    fi
    echo -n "${major:-"0"}" > "${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[TARGET_DIR]}/metadata/variant_version/major.txt"
    echo -n "${minor:-"0"}" > "${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[TARGET_DIR]}/metadata/variant_version/minor.txt"
    echo -n "${security:-"0"}" > "${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[TARGET_DIR]}/metadata/variant_version/security.txt"
    echo -n "${tags:-""}" > "${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[TARGET_DIR]}/metadata/variant_version/tags.txt"
  fi
}

addVendorToJson(){
  echo -n "${BUILD_CONFIG[VENDOR]}" > "${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[TARGET_DIR]}/metadata/vendor.txt"
}

addSourceToJson(){ # Pulls the origin repo, or uses 'openjdk-build' in rare cases of failure
  local repoName=$(git -C "${BUILD_CONFIG[WORKSPACE_DIR]}" config --get remote.origin.url 2>/dev/null)
  local repoNameStr="${repoName:-"ErrorUnknown"}"
  local buildSHA=$(git -C "${BUILD_CONFIG[WORKSPACE_DIR]}" rev-parse --short HEAD 2>/dev/null)
  if [[ $buildSHA ]]; then
    echo -n "${repoNameStr%%.git}/commit/$buildSHA" > "${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[TARGET_DIR]}/metadata/buildSource.txt"
  else
    echo "Unable to fetch build SHA, does a work tree exist?..."
  fi
}

addOpenJDKSourceToJson() { # name of git repo for which SOURCE sha is from
  local openjdkSourceRepo=$(git -C "${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[WORKING_DIR]}/${BUILD_CONFIG[OPENJDK_SOURCE_DIR]}" config --get remote.origin.url 2>/dev/null)
  local openjdkSHA=$(git -C "${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[WORKING_DIR]}/${BUILD_CONFIG[OPENJDK_SOURCE_DIR]}" rev-parse --short HEAD 2>/dev/null)
  if [[ $openjdkSHA ]]; then
    echo -n "${openjdkSourceRepo%%.git}/commit/${openjdkSHA}" > "${BUILD_CONFIG[WORKSPACE_DIR]}/${BUILD_CONFIG[TARGET_DIR]}/metadata/openjdkSource.txt"
  else
    echo "Unable to fetch OpenJDK Source SHA, does a work tree exist?..."
  fi
}

################################################################################

loadConfigFromFile
fixJavaHomeUnderDocker
cd "${BUILD_CONFIG[WORKSPACE_DIR]}"

parseArguments "$@"

if [[ "${BUILD_CONFIG[ASSEMBLE_EXPLODED_IMAGE]}" == "true" ]]; then
  buildTemplatedFile
  executeTemplatedFile
  printJavaVersionString
  addInfoToReleaseFile
  addInfoToJson
  removingUnnecessaryFiles
  copyFreeFontForMacOS
  setPlistForMacOS
  addNoticeFile
  createOpenJDKTarArchive
  exit 0
fi

echo "build.sh : $(date +%T) : Clearing out target dir ..."
wipeOutOldTargetDir
createTargetDir

echo "build.sh : $(date +%T) : Configuring workspace inc. clone and cacerts generation ..."
configureWorkspace

echo "build.sh : $(date +%T) : Initiating build ..."
getOpenJDKUpdateAndBuildVersion
configureCommandParameters
buildTemplatedFile
executeTemplatedFile

echo "build.sh : $(date +%T) : Build complete ..."

if [[ "${BUILD_CONFIG[MAKE_EXPLODED]}" != "true" ]]; then
  printJavaVersionString
  addInfoToReleaseFile
  addInfoToJson
  removingUnnecessaryFiles
  copyFreeFontForMacOS
  setPlistForMacOS
  addNoticeFile
  createOpenJDKTarArchive
fi

echo "build.sh : $(date +%T) : All done!"

# ccache is not detected properly TODO
# change grep to something like $GREP -e '^1.*' -e '^2.*' -e '^3\.0.*' -e '^3\.1\.[0123]$'`]
# See https://github.com/adoptium/openjdk-jdk8u/blob/dev/common/autoconf/build-performance.m4
