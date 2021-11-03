#!/bin/bash
set -u

BOOTDIR=""
VARIANT="hotspot"
useEclipseOpenJ9DockerFiles=false
CLEAN=false
WORKSPACE=${PWD}
JDK_VERSION=
JDK_MAX=
JDK_GA=

getFile() {
  if [ $# -ne 2 ]; then
    echo "getFile takes 2 arguments, $# argument(s) given"
    echo 'Usage: getFile https://example.com file_name'
    exit 1;
  elif command -v wget &> /dev/null; then
    wget -q "$1" -O "$2"
  elif command -v curl &> /dev/null; then
    curl -s "$1" -o "$2"
  else
    echo 'Please install wget or curl to continue'
    exit 1;
  fi
}

# shellcheck disable=SC2002 # Disable UUOC error
setJDKVars() {
    getFile https://api.adoptium.net/v3/info/available_releases available_releases
    JDK_MAX=$(awk -F: '/tip_version/{gsub("[, ]","",$2); print$2}' < available_releases)
    JDK_GA=$(awk -F: '/most_recent_feature_release/{gsub("[, ]","",$2); print$2}' < available_releases)
    rm available_releases
}

# Takes in all arguments to determine script options
parseCommandLineArgs()
{
    if [ $# -lt 1 ]; then
        echo "Script takes at least one argument"
        usage;
        exit 1;
    else
        while [[ $# -gt 0 ]] && [[ ."$1" = .-* ]] ; do
            local opt="$1";
            shift;
            case "$opt" in
                "--clean" | "-c" )
                    CLEAN=true;;
                "--version" | "-v" )
                    if [ "$1" == "jdk" ]; then
                          JDK_VERSION=$JDK_MAX
                    else
                          # shellcheck disable=SC2060
                          JDK_VERSION=$(echo "$1" | tr -d [:alpha:])
                        fi
                    checkJDK
                    shift;;
                "--jdk-boot-dir" | "-J")
                    BOOTDIR="$1"; shift;;
                "--openj9" | "-j9")
                    VARIANT="openj9";;
                "--use-eclipse-docker-files" | "-e" )
                    useEclipseOpenJ9DockerFiles=true; VARIANT="eclipsei_openj9";;
                "--help" | "-h" )
                    usage; exit 0;;
                *) echo >&2 "Invalid option: ${opt}"; echo "This option was unrecognised."; usage; exit 1;;
            esac
        done
        checkArgs
    fi
}

usage()
{
    echo
    echo "Usage: ./buildDocker.sh     --version|-v                            Build the specified JDK version"
    echo "            --clean | -c                Clean old generated dockerfiles and the old workspace"
    echo "            --jdk-boot-dir|-J            Specify the boot JDK directory"
    echo "            --openj9|-j9                Builds using OpenJ9 instead of Hotspot"
    echo "            --use-eclipse-docker-files|-e        Builds the specified jdk using the Eclipse Openj9 dockerfiles"
    echo
}

checkJDK() {
  if ! ((JDK_VERSION >= 8 && JDK_VERSION <= JDK_MAX)); then
    echo "Please input a JDK between 8 & ${JDK_MAX}, or 'jdk'"
    echo "i.e. The following formats will work for jdk8: 'jdk8u', 'jdk8' , '8'"
    exit 1
  fi
}

checkArgs()
{
    # ${WORKSPACE##*/} returns the name of the current dir
    if [ "${WORKSPACE##*/}" != "docker" ]; then
        echo "Unable to run script from : $WORKSPACE"
        echo "The script must be run from openjdk-build/docker/"
        exit 1
    fi
    if [ "$CLEAN" == true ]; then
        echo "Removing all jdkXX folders"
        rm -rf "$WORKSPACE/jdk*"
        echo "Removing old workspace folder"
        rm -rf "$WORKSPACE/workspace"
        echo "Removing old EclipseDockerfiles folder"
        rm -rf "$WORKSPACE/EclipseDockerfiles"
    fi
}

useEclipseOpenJ9DockerFiles()
{
    local dockerfileDir="$WORKSPACE/EclipseDockerfiles"
    local jdk="jdk"

    mkdir -p "$dockerfileDir"
    cd "$dockerfileDir" || { echo "Dockerfile directory ($dockerfileDir) was not found"; exit 3; }
    getFile https://raw.githubusercontent.com/eclipse-openj9/openj9/master/buildenv/docker/mkdocker.sh mkdocker.sh
    chmod +x mkdocker.sh
    # Generate an Ubuntu1804 Dockerfile using mkdocker.sh
    "$dockerfileDir/mkdocker.sh" --dist=ubuntu --version=18 --print >> "$dockerfileDir/Dockerfile"

    # This Dockerfile requires an ssh key, authorized_key and known_hosts file to build
    ssh-keygen -q -f "$dockerfileDir/id_rsa" -t rsa -N ''
    cat id_rsa.pub >> "$dockerfileDir/authorized_keys"
    ssh-keyscan github.com >> "$dockerfileDir/known_hosts"

    if [ "$JDK_VERSION" != "$JDK_MAX" ]; then
            jdk="jdk${JDK_VERSION}"
    fi
    eclipseDockerCommands "${jdk}"
}

eclipseDockerCommands()
{
    local jdk=$1
    local dockerImage="${jdk}-${VARIANT}-dfc"
    local dockerContainer="${jdk}-${VARIANT}"

    docker build -t "${dockerImage}" -f Dockerfile .
    docker run -it -u root -d --name="${dockerContainer}" "${dockerImage}"
    docker exec -u root -i "${dockerContainer}" sh -c "git clone https://github.com/ibmruntimes/openj9-openjdk-${jdk}"
    docker exec -u root -i "${dockerContainer}" sh -c "cd openj9-openjdk-${jdk} && bash ./get_source.sh && bash ./configure --with-freemarker-jar=/root/freemarker.jar && make all"
    docker stop "${dockerContainer}"
    docker rm "${dockerContainer}"
    docker rmi "${dockerImage}"
}

buildDocker()
{
    local commandString="./makejdk-any-platform.sh --docker --clean-docker-build"
    local jdk="jdk"

    # Pass jdkXXu to makejdk-any-platform.sh where possible
    if ((JDK_VERSION != JDK_MAX && JDK_VERSION <= JDK_GA )); then
        jdk="jdk${JDK_VERSION}u"
    elif ((JDK_VERSION != JDK_MAX && JDK_VERSION > JDK_GA )); then
        jdk="jdk${JDK_VERSION}"
    fi
    if [ -n "$BOOTDIR" ]; then
        commandString="$commandString -J $BOOTDIR"
    fi
    if [[ "$VARIANT" == "openj9" ]]; then
        commandString="$commandString --build-variant openj9"
    fi
    echo "$commandString $jdk being executed"
    cd "$WORKSPACE/.." && $commandString "$jdk"
}

setJDKVars
parseCommandLineArgs "$@"
if [[ "$useEclipseOpenJ9DockerFiles" == "true" ]]; then
    useEclipseOpenJ9DockerFiles
else
    buildDocker
fi
