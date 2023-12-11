#!/bin/bash
# Before executing this script, strace output files need to be generated
set -x
# $1 is path of strace output folder
# $2 is path of temurin-build folder, for exmaple: /home/user/Documents/temurin-build"
git rem

if [ -z "$1" ]; then
    echo "temurin-build folder as param is missing!"
    exit 1
fi

# File patterns to ignore
ignores=("^/dev/")
ignores+=("^/proc/")
ignores+=("^/etc/ld.so.cache$")
ignores+=("^/etc/nsswitch.conf$")
ignores+=("^/etc/passwd$")
ignores+=("^/etc/timezone$")
ignores+=("^/sys/devices/system/cpu")
ignores+=("^/sys/fs/cgroup/")
ignores+=("^/lib/locale/locale-archive$")
ignores+=("^/etc/mailcap$")

isBinSymLink=false
isLibSymLink=false
isSbinSymLink=false

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

# grep strace files,
# ignoring:
#   ENOENT           : strace no entry
#   +++              : strace +++ lines
#   ---              : strace --- lines
#   /dev/            : devices
#   /proc/           : /proc processor paths
#   /tmp/            : /tmp files
#   .java            : .java files
#   .d               : .d compiler output
#   .o               : .o compiler output
#   .d.targets       : .d.targets make compiler output
#   <build_dir>      : begins with build directory
#   <relative paths> : relative file paths

#set -f
# filtering out relevant parts of strace output files
# grep -E "/usr/*|/bin/*|/sys/*"
echo "Param 1: $1"
echo "Param 2: $2"
#allFiles="$(find "$2" -type f -name 'outputFile.*' | xargs -n100 grep -v ENOENT | cut -d'"' -f2 | grep -v "$1" | grep -v "\.java$" | grep -v "\+\+\+" | grep -v "\-\-\-" | grep -v "test/*" | grep -v "^src/" | grep -v "^modules/" | grep -v "^make/" | grep -v "^jdk." | grep -v "^java." | grep -v "^.github" | sort | uniq)"
allFiles="$(find "$1" -type f -name 'outputFile.*'| xargs -n100 grep -v ENOENT | cut -d'"' -f2 | grep "^/" | grep -v "\.java$" | grep -v "\.d$" | grep -v "\.o$" | grep -v "\.d\.targets$" | grep -v "^$2" | grep -v "\+\+\+" | grep -v "\-\-\-" | grep -v "^/dev/" | grep -v "^/proc/" | grep -v "^/sys/" | grep -v "^/tmp/" | sort | uniq)"
#set +f

totalFileCounter=0
pkgs=()
no_pkg_files=()
for file in $allFiles; do
    echo "Processing: $file"
    ((totalFileCounter = totalFileCounter + 1))

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
        no_pkg_files+=("$filePath")
    else
        pkg="$(echo "$pkg" | cut -d" " -f1)"
        pkg=${pkg::-1}
        #echo "file: $filePath pkg: $pkg version: $pkg"
        pkgString="pkg: $pkg version: $pkg"
        if ! echo "${pkgs[@]}" | grep "temurin_${pkgString}_temurin" >/dev/null; then
            pkgs+=("temurin_${pkgString}_temurin")
        fi
    fi
done
echo "Number of all processed strace output files: $totalFileCounter"
if [ $totalFileCounter == 0 ]; then
    echo "No strace output files available"
    exit 1
fi

npkgs=()
# loop over all non-package dependencies and try to get the version. If version is not empty, add to array
for file in "${no_pkg_files[@]}"; do
    npkg=$("$file" --version 2>/dev/null | head -n 1)
    if [[ "$npkg" != "" ]]; then
        npkgs+=("${npkg}")
    fi
done

echo -e "\nNon-Package Dependencies:"
printf '%s\n' "${npkgs[@]}" | sort -u

echo -e "\nPackage Dependencies:"
for pkg in "${pkgs[@]}"; do
    trimPkg=${pkg/#temurin_/}
    trimPkg=${trimPkg%_temurin}
    echo $trimPkg
done
