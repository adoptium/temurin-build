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
# $2 is path of temurin-build folder, for exmaple: /home/user/Documents/temurin-build"
# $3 is javaHome
# $4 is classpath
# $5 is sbomJson

set +eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../sbin/common/sbom.sh"

javaHome=""
classpath=""
sbomJson=""

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
    "\.java$"
    "\.d$"
    "\.o$"
    "\.d\.targets$"
    "^$2"
    "\+\+\+"
    "\-\-\-"
    "^/dev/"
    "^/proc/"
    "^/sys/"
    "^/tmp/"
)

checkArguments() {
    if [ -z "$1" ]; then
        echo "strace output folder as param is missing!"
        exit 1
    fi

    if [ -z "$2" ]; then
        echo "temurin-build folder as param is missing!"
        exit 1
    fi

    if [ -z "$3" ]; then
        echo "javaHome as param is missing!"
        exit 1
    fi

    if [ -z "$4" ]; then
        echo "classpath as param is missing!"
        exit 1
    fi

    if [ -z "$5" ]; then
        echo "sbomJson as param is missing!"
        exit 1
    fi

    javaHome=$3
    classpath=$4
    sbomJson=$5

    echo "Strace output folder: $1"
    echo "Temurin build folder: $2"
    echo "javaHome: $javaHome"
    echo "classpath: $classpath"
    echo "sbomJson: $sbomJson"
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
    mapfile -t allFiles < <(find "$1" -type f -name 'outputFile.*' | xargs -n100 grep -v ENOENT | cut -d'"' -f2 | grep "^/" | eval "$grep_command" | sort | uniq)
    echo "find \"$1\" -type f -name 'outputFile.*' | xargs -n100 grep -v ENOENT | cut -d'\"' -f2 | grep \"^/\" | eval \"$grep_command\" | sort | uniq"

    for file in "${allFiles[@]}"; do
        echo "$file"
    done
}

processFiles() {
    for file in "${allFiles[@]}"; do
        echo "Processing: $file"

        filePath="$(readlink -f "$file")"
        pkg=$(rpm -qf "$filePath")
        rc=$?

        if [[ "$rc" != "0" ]]; then
            # bin, lib, sbin pkgs may be installed under the root symlink
            if [[ "$isBinSymLink" == "true" ]] && [[ $filePath == /usr/bin* ]]; then
                filePath=${filePath/#\/usr\/bin/}
                filePath="/bin${filePath}"
                pkg=$(rpm -qf "$filePath" 2>/dev/null)
                rc=$?
            fi
            if [[ "$isLibSymLink" == "true" ]] && [[ $filePath == /usr/lib* ]]; then
                filePath=${filePath/#\/usr\/lib/}
                filePath="/lib${filePath}"
                pkg=$(rpm -qf "$filePath" 2>/dev/null)
                rc=$?
            fi
            if [[ "$isSbinSymLink" == "true" ]] && [[ $filePath == /usr/sbin* ]]; then
                filePath=${filePath/#\/usr\/sbin/}
                filePath="/sbin${filePath}"
                pkg=$(rpm -qf "$filePath" 2>/dev/null)
                rc=$?
            fi
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

        if [[ "$rc" != "0" ]]; then
            nonPkgFiles+=("$filePath")
        else
            pkg="$(echo "$pkg" | cut -d" " -f1)"
            pkg=${pkg::-1}
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
    for file in "${nonPkgFiles[@]-}"; do

        # We need to try and find the program's version using possible --version or -version
        version=$("$file" --version 2>/dev/null | head -n 1)

        if [[ "$version" == "" ]]; then
            version=$("$file" -version dummy 2>/dev/null | head -n 1)
        fi
        if [[ "$version" == "" ]]; then
            version=$("$file" --version dummy 2>&1 | grep -v "[Pp]ermission denied" | head -n 1)
        fi
        if [[ "$version" == "" ]]; then
            version=$("$file" -version dummy 2>&1 | grep -v "[Pp]ermission denied" | head -n 1)
        fi
        if [[ "$version" == "" ]]; then
            version=$("$file" -version dummy 2>/dev/null | head -n 1)
        fi
        if [[ "$version" == *"Is a directory"* ]]; then
            version=""
        fi

        if [[ "$version" != "" ]]; then
            # Make sure to only add unique packages to SBOM
            if [[ ! " ${uniqueVersions[*]-} " =~ ${version} ]]; then
                addSBOMFormulationComponentProperty "${javaHome}" "${classpath}" "${sbomJson}" "Build Dependencies" "Build tool non-package dependencies" "${version}" "${version}"
                nonpkgs+=("${version}")
                uniqueVersions+=("${version}")
            fi
        else
            errorpkgs+=("${file}")
        fi
    done
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

    echo -e "\nPackages where version cannot be identified:"
    printf '%s\n' "${errorpkgs[@]-}"
}

checkArguments "$@"
checkSymLinks
configureSbom
filterStraceFiles "$@"
printNumberOfAllProcessedFiles
processFiles
processNonPkgFiles
printPackages
