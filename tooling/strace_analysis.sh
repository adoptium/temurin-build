#!/bin/bash
# shellcheck disable=SC1091
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

################################################################################
#
# This shell script deals with analysing the output files produced by strace
# and adds them to SBOM
#
################################################################################

# Before executing this script, strace output files need to be generated
# $1 is path of strace output folder
# $2 is path of temurin-build folder, for example: /home/user/Documents/temurin-build"
# $3 is javaHome
# $4 is classpath
# $5 is sbomJson
# $6 is path of openjdk build output folder
# $7 is path of cloned openjdk folder
# $8 is Optional, path of devkit

set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../sbin/common/sbom.sh"

strace_dir=""
temurin_build_dir=""
javaHome=""
classpath=""
sbomJson=""
build_output_dir=""
cloned_openjdk_dir=""
devkit_dir=""

# Arrays to store different types of strace output, to treat them different
nonPkgFiles=()
allFiles=()

# Arrays for package and non-package dependencies
pkgs=()
nonpkgs=()
errorpkgs=()

# Array to store packages, to make sure no duplicates are added to Sbom
uniqueVersions=()

isBinSymLink=false
isLibSymLink=false
isSbinSymLink=false

# ignore-patterns for strace files
ignores=(
    "\.gitconfig$"
    "\.java$"
    "\.d$"
    "\.o$"
    "\.d\.targets$"
    "\+\+\+"
    "\-\-\-"
    "^/dev/"
    "^/proc/"
    "^/sys/"
    "^/tmp/"
)

checkArguments() {
    
    if [ $# -lt 6 ]; then
        echo "Missing argument(s)"
        echo "Syntax:"
        echo "  $0 <Strace output folder> <temurin-build folder> <javaHome> <classpath> <sbomJson> <build output folder> <cloned openjdk folder> [<DevKit folder>]"
        exit 1
    fi

    strace_dir="$1"
    temurin_build_dir="$2"
    javaHome="$3"
    classpath="$4"
    sbomJson="$5"
    build_output_dir="$6"
    cloned_openjdk_dir="$7"
    if [ $# -gt 7 ]; then
        devkit_dir="$8"
    fi

    echo "Strace output folder: $strace_dir"
    echo "temurin-build folder: $temurin_build_dir"
    echo "javaHome: $javaHome"
    echo "classpath: $classpath"
    echo "sbomJson: $sbomJson"
    echo "build output folder: $build_output_dir"
    echo "cloned openjdk folder: $cloned_openjdk_dir"
    if [ -n "$devkit_dir" ]; then
        echo "DevKit folder: $devkit_dir"
    fi

    # Add build output folder to the ignore list as it is just build output
    ignores+=("^${build_output_dir}")

    # Add cloned openjdk folder to the ignore list as it is just openjdk source
    ignores+=("^${cloned_openjdk_dir}")
}

checkSymLinks() {
    # Check if /bin, /lib, /sbin are symlinks, as sometimes pkgs are installed
    # under the symlink folder, eg.in Ubuntu 20.04
    binDir=$(readlink -f "/bin")
    if [[ "$binDir" != "/bin" ]]; then
        isBinSymLink=true
    fi
    libDir=$(readlink -f "/lib")
    if [[ "$libDir" != "/lib" ]]; then
        isLibSymLink=true
    fi
    sbinDir=$(readlink -f "/sbin")
    if [[ "$sbinDir" != "/sbin" ]]; then
        isSbinSymLink=true
    fi

    # Check if javaHome is a sym link, if so resolve it to the real path
    # which will be used in strace output
    javaHomeLink=$(readlink -f "${javaHome}")
    if [[ "x${javaHomeLink}" != "x${javaHome}" ]]; then
        echo "Resolving javaHome '${javaHome}' sym link to '${javaHomeLink}'"
        javaHome="${javaHomeLink}"
    fi

    echo "/bin is symlink: $isBinSymLink"
    echo "/lib is symlink: $isLibSymLink"
    echo "/sbin is symlink: $isSbinSymLink"
    echo ""
}

configureSbom() {
    addSBOMFormulation "${javaHome}" "${classpath}" "${sbomJson}" "Build Dependencies"
    addSBOMFormulationComp "${javaHome}" "${classpath}" "${sbomJson}" "Build Dependencies" "Build tool package dependencies"
    addSBOMFormulationComp "${javaHome}" "${classpath}" "${sbomJson}" "Build Dependencies" "Build tool non-package dependencies"
}

filterStraceFiles() {
    # Configure grep command to use ignore-patterns
    grep_command="grep -Ev '(${ignores[0]}"
    for ((i = 1; i < ${#ignores[@]}; i++)); do
        grep_command+="|${ignores[i]}"
    done
    grep_command+=")'"

    # filtering out relevant parts of strace output files
    mapfile -t allFiles < <(find "${strace_dir}" -type f -name 'outputFile.*' | xargs -n100 grep -v ENOENT | cut -d'"' -f2 | grep "^/" | eval "$grep_command" | sort | uniq)
    echo "find \"${strace_dir}\" -type f -name 'outputFile.*' | xargs -n100 grep -v ENOENT | cut -d'\"' -f2 | grep \"^/\" | eval \"$grep_command\" | sort | uniq"

    for file in "${allFiles[@]}"; do
        echo "$file"
    done
}

processFiles() {
    echo "Processing found files to determine 'Package' versions... (this will take a few minutes)"

    for file in "${allFiles[@]}"; do
        filePath="$(readlink -f "$file")"
        non_pkg=false

        # Attempt to determine rpm pkg
        # shellcheck disable=SC2069
        if ! rpm -qf "$filePath" 2>&1>/dev/null; then
            # bin, lib, sbin pkgs may be installed under the root symlink
            if [[ "$isBinSymLink" == "true" ]] && [[ $filePath == /usr/bin* ]]; then
                filePath=${filePath/#\/usr\/bin/}
                filePath="/bin${filePath}"
            fi
            if [[ "$isLibSymLink" == "true" ]] && [[ $filePath == /usr/lib* ]]; then
                filePath=${filePath/#\/usr\/lib/}
                filePath="/lib${filePath}"
            fi
            if [[ "$isSbinSymLink" == "true" ]] && [[ $filePath == /usr/sbin* ]]; then
                filePath=${filePath/#\/usr\/sbin/}
                filePath="/sbin${filePath}"
            fi

            # shellcheck disable=SC2069 
            if ! rpm -qf "$filePath" 2>&1>/dev/null; then
                non_pkg=true
            else
                pkg=$(rpm -qf "$filePath")
            fi
        else
            pkg=$(rpm -qf "$filePath")
        fi

        ignoreFile=false
        for ignoreFile in "${ignores[@]}"; do
            if [[ "$filePath" =~ $ignoreFile ]]; then
                ignoreFile=true
                break
            fi
        done
        if [[ $ignoreFile == true ]]; then
            continue
        fi

        if [[ "$non_pkg" = true ]]; then
            nonPkgFiles+=("$filePath")
        else
            pkg="$(echo "$pkg" | cut -d" " -f1 | tr -d '\\n\\r')"
            pkgString="pkg: $pkg version: $pkg"

            # Make sure to only add unique packages to SBOM
            if ! echo "${pkgs[@]-}" | grep "temurin_${pkgString}_temurin" >/dev/null; then
                addSBOMFormulationComponentProperty "${javaHome}" "${classpath}" "${sbomJson}" "Build Dependencies" "Build tool package dependencies" "${pkg}" "${pkg}"
                pkgs+=("temurin_${pkgString}_temurin")
            fi
        fi
    done
}

processNonPkgFiles() {
    for np_file in "${nonPkgFiles[@]-}"; do
        # Ensure we have the full real path name
        file=$(readlink -f "${np_file}")

        if [[ "$file" =~ ^"$temurin_build_dir".* ]]; then
            if [[ ( -z "$devkit_dir" || ! "$file" =~ ^"$devkit_dir".* ) && (! "$file" =~ ^"$javaHome".*) ]]; then
                # not DevKit or javaHome path within, so ignore as part of temurin-build
                continue
            fi
        fi

        local version
        # If file is part of javaHome, then obtain version of the JDK
        if [[ "$file" =~ ^"$javaHome".* ]]; then
          # Get javaHome version
          version=$("${javaHome}/bin/java" -version 2>&1 | head -2 | tail -1)
        else
          # We need to try and find the program's version using possible --version or -version
          version=$("$file" --version 2>/dev/null | head -n 1)

          if [[ "$version" == "" ]]; then
              version=$("$file" -version dummy 2>/dev/null | head -n 1)
          fi
          if [[ "$version" == "" ]]; then
              version=$("$file" --version dummy 2>&1 | grep -v "[Pp]ermission denied" | grep -v "not found" | grep -v "error while loading" | head -n 1)
          fi
          if [[ "$version" == "" ]]; then
              version=$("$file" -version dummy 2>&1 | grep -v "[Pp]ermission denied" | grep -v "not found" | grep -v "error while loading" | head -n 1)
          fi
          if [[ "$version" == "" ]]; then
              version=$("$file" -version dummy 2>/dev/null | head -n 1)
          fi
          if [[ "$version" == *"Is a directory"* ]]; then
              version=""
          fi
        fi

        if [[ "$version" != "" ]]; then
            # Make sure to only add unique packages to SBOM
            if [[ ! "${uniqueVersions[*]-}" =~ .*"END_${version}_END".* ]]; then
                addSBOMFormulationComponentProperty "${javaHome}" "${classpath}" "${sbomJson}" "Build Dependencies" "Build tool non-package dependencies" "${version}" "${version}"
                nonpkgs+=("${version}")
                uniqueVersions+=("END_${version}_END")
            fi
        else
            if [[ -n "$devkit_dir" ]] && [[ "$file" =~ ^"$devkit_dir".* ]]; then
                # DevKit file, then ignore, as we recognise it and manually add DevKit info
                continue
            else
                errorpkgs+=("${file}")
            fi
        fi
    done
}

addDevKitInfo() {
    if [[ -n "$devkit_dir" ]]; then
        local devkitInfo="${devkit_dir}/devkit.info"

        local adoptium_devkit_version=""
        if grep "ADOPTIUM_DEVKIT_RELEASE" "${devkitInfo}"; then
            adoptium_devkit_version="$(grep "ADOPTIUM_DEVKIT_RELEASE" "${devkitInfo}" | cut -d"=" -f2)"
        fi
        if grep "ADOPTIUM_DEVKIT_TARGET" "${devkitInfo}"; then
            adoptium_devkit_version="${adoptium_devkit_version}-$(grep "ADOPTIUM_DEVKIT_TARGET" "${devkitInfo}" | cut -d"=" -f2)"
        fi

        local devkit_name="Unknown"
        if grep "DEVKIT_NAME" "${devkitInfo}"; then
            devkit_name="$(grep "DEVKIT_NAME" "${devkitInfo}" | cut -d"=" -f2)"
        fi

        addSBOMFormulationComponentProperty "${javaHome}" "${classpath}" "${sbomJson}" "Build Dependencies" "Build tool non-package dependencies" "DEVKIT_NAME" "${devkit_name}"
        nonpkgs+=("DevKit: ${devkit_name}")
        uniqueVersions+=("END_DevKit: ${devkit_name}_END")

        if [[ -n "${adoptium_devkit_version}" ]]; then
            addSBOMFormulationComponentProperty "${javaHome}" "${classpath}" "${sbomJson}" "Build Dependencies" "Build tool non-package dependencies" "ADOPTIUM_DEVKIT" "${adoptium_devkit_version}"
            nonpkgs+=("DevKit Adoptium Version: ${adoptium_devkit_version}")
            uniqueVersions+=("END_DevKit Adoptium Version: ${adoptium_devkit_version}_END")
        fi
    fi
}

printPackages() {
    echo -e "\nNon-Package Dependencies:"
    printf '%s\n' "${nonpkgs[@]-}"

    echo -e "\nPackage Dependencies:"
    for pkg in "${pkgs[@]}"; do
        trimPkg=${pkg/#temurin_/}
        trimPkg=${trimPkg%_temurin}
        echo "$trimPkg"
    done

    # If some packages cannot be identified then list them
    if [[ -n "${errorpkgs[*]-}" ]]; then
        echo -e "\nERROR: Some package versions cannot be identified:"
        printf '%s\n' "${errorpkgs[@]-}"
    fi
}

checkArguments "$@"
checkSymLinks
configureSbom
filterStraceFiles "$@"
processFiles
processNonPkgFiles
addDevKitInfo
printPackages
