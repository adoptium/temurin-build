#!/bin/bash
# shellcheck disable=SC1091
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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../sbin/common/sbom.sh"

javaHome=""
classpath=""
sbomJson=""

# Arrays to store different types of strace output, to treat them different
usrLocalFiles=()
otherFiles=()

# Arrays for package and non-package dependencies
pkgs=()
npkgs=()

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
    allFiles=()

    # Configure grep command to use ignore-patterns
    grep_command="grep -Ev '(${ignores[0]}"
    for ((i = 1; i < ${#ignores[@]}; i++)); do
        grep_command+="|${ignores[i]}"
    done
    grep_command+=")'"

    # filtering out relevant parts of strace output files
    mapfile -t allFiles < <(find "$1" -type f -name 'outputFile.*' | xargs -n100 grep -v ENOENT | cut -d'"' -f2 | grep "^/" | eval "$grep_command" | sort | uniq)
    #mapfile -t allFiles < <(find "$1" -type f -name 'outputFile.*' | xargs -n100 grep -v ENOENT | cut -d'"' -f2 | grep "^/" sort | uniq)

    # loop over all filtered files and store those with /usr/local in separate array
    for file in "${allFiles[@]}"; do
        echo -e "FILE: $file \n"
        if [[ $file == "/usr/local/"* ]]; then
            usrLocalFiles+=("$file")
            echo "UsrLocalFile: $file"
        else
            otherFiles+=("$file")
            echo "No usrLocalFile: $file"
        fi
    done

    echo "Number of /usr/local files: ${#usrLocalFiles[@]}"
    echo "Number of other files: ${#otherFiles[@]}"
}

printNumberOfAllProcessedFiles() {
    # Calculate and print number of all processed strace output files
    totalLength=$((${#usrLocalFiles[@]} + ${#otherFiles[@]}))
    if [ $totalLength -ne 0 ]; then
        printf '\nNumber of all processed strace output files: %s\n' "$totalLength"
    else
        printf "\nNo strace output files available\n"
        exit 1
    fi
}

processFiles() {
    for file in "${otherFiles[@]}"; do
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
            #echo "no pkg: $filePath"
            usrLocalFiles+=("$filePath")
        else
            pkg="$(echo "$pkg" | cut -d" " -f1)"
            pkg=${pkg::-1}
            pkgString="pkg: $pkg version: $pkg"

            if ! echo "${pkgs[@]-}" | grep "temurin_${pkgString}_temurin" >/dev/null; then
                addSBOMFormulationComponentProperty "${javaHome}" "${classpath}" "${sbomJson}" "Build Dependencies" "Build tool package dependencies" "${pkg}" "${pkg}"
                pkgs+=("temurin_${pkgString}_temurin")
            fi
        fi
    done
}

processUsrLocalFiles() {
    # loop over all non-package dependencies and try to get the version. If version is not empty, add to array
    for file in "${usrLocalFiles[@]-}"; do
        npkg=$("$file" --version 2>/dev/null | head -n 1)

        echo -e "\n UsrLocalFile Package: $file ; $npkg"

        if [[ "$npkg" != "" ]]; then
            version=$(echo "$npkg" | awk '{print $NF}')

            # Make sure to only add unique packages to Sbom
            if [[ ! " ${uniqueVersions[*]-} " =~ ${npkg} ]]; then
                npkgs+=("${npkg}")
                uniqueVersions+=("${npkg}") # Marking package as processed
                addSBOMFormulationComponentProperty "${javaHome}" "${classpath}" "${sbomJson}" "Build Dependencies" "Build tool non-package dependencies" "${npkg}" "${version}"
            fi
        fi
    done
}

printPackages() {
    printf "\nNon-Package Dependencies:\n"
    printf '%s\n' "${npkgs[@]-}"

    printf "\nPackage Dependencies:\n"
    for pkg in "${pkgs[@]}"; do
        trimPkg=${pkg/#temurin_/}
        trimPkg=${trimPkg%_temurin}
        echo "$trimPkg"
    done
    printf "\n"
}

checkArguments "$@"
checkSymLinks
configureSbom
filterStraceFiles "$@"
processFiles
processUsrLocalFiles
printNumberOfAllProcessedFiles
printPackages
