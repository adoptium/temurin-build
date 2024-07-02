#!/bin/bash
# shellcheck disable=SC2129
# ********************************************************************************
# Copyright (c) 2020 Contributors to the Eclipse Foundation
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

set -eu

OPENJ9=false
BUILD=false
COMMENTS=false
DIRS=
PRINT=false
DOCKERFILE_DIR=
DOCKERFILE_PATH=
# Default to JDK8
JDK_VERSION=8
IMAGE="ubuntu:18.04"
JDK_MAX=
JDK_GA=
DNF_INSTALL=dnf

UBUNTU_PREAMBLE="apt-get update \\
  && apt-get install -qq -u --no-install-recommends \\
    software-properties-common \\
    dirmngr \\
    gpg-agent \\
    coreutils \\
  && apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys 0x219BD9C9 \\
  && add-apt-repository 'deb http://repos.azulsystems.com/ubuntu stable main' \\
  && apt-get update \\	
  && apt-get -y upgrade \\"

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
  JDK_MAX=$(cat available_releases \
      | grep 'tip_version' \
      | cut -d':' -f 2 \
      | sed 's/,//g; s/ //g')
  JDK_GA=$(cat available_releases \
          | grep 'most_recent_feature_release' \
          | cut -d':' -f 2 \
          | sed 's/,//g; s/ //g')
  rm available_releases
}

processArgs() {
  local arg
  local cleanRepo=false
  while [[ $# -gt 0 ]]
  do
    arg="$1"
    # Stop the script failing when passed an empty variable
    if [ -z "$arg" ]; then
      shift
      continue
    fi
    case $arg in
      -h | --help)
        usage
        exit 0
        ;;
      --openj9)
        OPENJ9=true
        shift
        ;;
      --build)
        BUILD=true
        shift
        ;;
      --clean)
        cleanRepo=true
        shift
        ;;
      --comments)
        COMMENTS=true
        shift
        ;;
      --dirs)
        DIRS="${2}"
        shift
        shift
        ;;
      --base-image)
        IMAGE="${2}"
        shift
        shift
        ;;
      --path)
        DOCKERFILE_DIR=$2
        shift
        shift
        ;;
      --print)
        PRINT=true
        shift
        ;;
      -v | --version)
    if [ "$2" == "jdk" ]; then
      JDK_VERSION=$JDK_MAX
    else
      # shellcheck disable=SC2060
      JDK_VERSION=$(echo "$2" | tr -d [:alpha:])
        fi
    checkJDK
        shift
        shift
        ;;
      --command)
        CMD="${2}"
        shift
        shift
        ;;
      *)
        echo "Unrecognised Argument: $1"
        exit 1
        ;;
    esac
  done

  if [ -z "$DOCKERFILE_DIR" ]; then
    DOCKERFILE_DIR=$PWD
  fi

  if [ ${cleanRepo} ]; then
    echo "Removing Dockerfile* from $DOCKERFILE_DIR" && rm -rf "$DOCKERFILE_DIR"/Dockerfile*
  fi

  DOCKERFILE_PATH="$DOCKERFILE_DIR/Dockerfile"
  if [ ${OPENJ9} == true ]; then
    DOCKERFILE_PATH="$DOCKERFILE_PATH-openj9"
  fi

  if [ -z "$CMD" ]; then
    if which podman > /dev/null; then
       CMD=podman
    else
       CMD=docker
    fi
  fi
}

usage() {
  echo " Usage: ./dockerfile_generator.sh [OPTIONS]
  Options:
      --help | -h        Print this message and exit
      --build        Build the docker image after generation and create interactive container
      --base-image   set the base image if used container. Default: $IMAGE 
      --clean        Remove all dockerfiles (Dockerfile*) from '--path'
      --comments        Prints comments into the dockerfile
      --dirs         space separated list of dirs to be created, with proper permissions
      --path <FILEPATH>    Specify where to save the dockerfile (Default: $PWD)
      --print        Print the Dockerfile to screen after generation
      --openj9        Make the Dockerfile able to build w/OpenJ9 JIT
      --version | -v <JDK>    Specify which JDK the docker image will be able to build (Default: jdk8)"
}

# Checks to ensure the input JDK is valid
checkJDK() {
  if ! ((JDK_VERSION >= 8 && JDK_VERSION <= JDK_MAX)); then
    echo "Please input a JDK between 8 & ${JDK_MAX}, or 'jdk'"
    exit 1
  fi
}

# Put in license, 'FROM' statement and 'LABEL' statement
printPreamble() {
  echo "
#
# ********************************************************************************
# Copyright (c) 2020 Contributors to the Eclipse Foundation
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

FROM $IMAGE

LABEL maintainer=\"AdoptOpenJDK <adoption-discuss@openjdk.java.net>\"
  " >> "$DOCKERFILE_PATH"
}


printAptPackagesBase() {
  if [ ${COMMENTS} == true ]; then
    echo "
# Install required OS tools to setup environment as .deb via apt-get
# dirmngr, gpg-agent & coreutils are all required for the apt-add repository command" >> "$DOCKERFILE_PATH"
  fi
  echo " 
RUN $UBUNTU_PREAMBLE
  && apt-get install -qq -y --no-install-recommends \\
    curl \\
    git \\
    unzip \\
    wget \\
    zip " >> "$DOCKERFILE_PATH"
  echo "
RUN rm -rf /var/lib/apt/lists/*" >> "$DOCKERFILE_PATH"
}

printDnfPackagesBase() {
  if [ ${COMMENTS} == true ]; then
    echo "
# Install required OS tools to setup environment as rpms via dnf" >> "$DOCKERFILE_PATH"
  fi
  local skipGpg="" # it may bite from time to time
  #local skipGpg="--nogpgcheck"
  local erasing="--allowerasing"
  if [ ${DNF_INSTALL} = yum ] ; then
    erasing=""
  fi
  if echo "${IMAGE}" | grep -e "stream8" -e "centos:7" ; then
    echo " 
RUN cd /etc/yum.repos.d/ ; sed -i 's/mirrorlist/#mirrorlist/g' /etc/yum.repos.d/CentOS-*
RUN cd /etc/yum.repos.d/ ; sed -i 's|#baseurl=http://mirror.centos.org|baseurl=http://vault.centos.org|g' /etc/yum.repos.d/CentOS-* " >> "$DOCKERFILE_PATH"
  fi
  echo " 
RUN ${DNF_INSTALL} $skipGpg -y update $erasing
RUN ${DNF_INSTALL} $skipGpg -y install $erasing \\
    bzip2-libs \\
    bzip2 \\
    curl \\
    git \\
    unzip \\
    /usr/bin/which \\
    wget \\
    zip " >> "$DOCKERFILE_PATH"
  echo " 
RUN ${DNF_INSTALL} clean all" >> "$DOCKERFILE_PATH"
}

printAptPackagesJdk() {
  if [ ${COMMENTS} == true ]; then
    echo "
# Install required OS tools to build JDK as .deb via apt-get
# dirmngr, gpg-agent & coreutils are all required for the apt-add repository command" >> "$DOCKERFILE_PATH"
  fi

  echo " 
RUN $UBUNTU_PREAMBLE
  && apt-get install -qq -y --no-install-recommends \\
    ant \\
    ant-contrib \\
    autoconf \\
    ca-certificates \\
    cmake \\
    cpio \\
    file \\
    libasound2-dev \\
    libcups2-dev \\
    libelf-dev \\
    libfontconfig1-dev \\
    libfreetype6-dev \\
    libx11-dev \\
    libxext-dev \\
    libxi-dev \\
    libxrandr-dev \\
    libxrender-dev \\
    libxt-dev \\
    libxtst-dev \\
    make \\
    perl \\
    ssh \\
    systemtap-sdt-dev \\" >> "$DOCKERFILE_PATH"

  if [ ${OPENJ9} = true ]; then
    echo "    gcc-7 \\
    g++-7 \\
    libexpat1-dev \\
    libdwarf-dev \\
    libffi-dev \\
    libfontconfig \\
    libnuma-dev \\
    libssl-dev \\
    nasm \\
    pkg-config \\
    xvfb \\
    zlib1g-dev \\" >> "$DOCKERFILE_PATH"
  else
    echo "    ccache \\
    g++ \\
    gcc \\" >> "$DOCKERFILE_PATH"
  fi

  # JDK8 uses zulu-7 as it's bootJDK
  if [ "${JDK_VERSION}" == 8 ]; then
    echo "    zulu-7 \\" >> "$DOCKERFILE_PATH"
  fi

  echo "  && rm -rf /var/lib/apt/lists/*" >> "$DOCKERFILE_PATH"
}

printDnfPackagesJdk() {
  if [ ${COMMENTS} == true ]; then
    echo "
# Install required OS tools to build JDK as rpms via dnf" >> "$DOCKERFILE_PATH"
  fi
  local skipGpg="" # it may bite from time to time
  #local skipGpg="--nogpgcheck"
  local erasing="--allowerasing"
  if [ ${DNF_INSTALL} = yum ] ; then
    erasing=""
  fi
  echo " 
RUN ${DNF_INSTALL} $skipGpg -y install $erasing \\
    ant \\
    autoconf \\
    automake \\
    ca-certificates \\
    cmake \\
    cpio \\
    diffutils \\
    file \\
    alsa-lib-devel \\
    cups-devel \\
    gcc \\
    gcc-c++ \\
    gdb \\
    fontconfig-devel \\
    freetype-devel \\
    libtool \\
    libX11-devel \\
    libXi-devel \\
    libXinerama-devel \\
    libXrandr-devel \\
    libXrender-devel \\
    libXt-devel \\
    libXtst-devel \\
    lksctp-tools-devel \\
    lksctp-tools pcsc-lite-libs \\
    make \\
    perl \\
    procps-ng \\
    openssh-clients \\
    openssl \\
    systemtap-sdt-devel \\
    kernel-headers \\
    \"lcms*\" \\
    nss-devel \\ " >> "$DOCKERFILE_PATH"
  if echo "${IMAGE}" | grep fedora ; then
    echo "    libstdc++-static \\
    pcsc-lite-devel \\	" >> "$DOCKERFILE_PATH"
  fi
  echo "    tzdata-java " >> "$DOCKERFILE_PATH"
  echo " 
RUN ${DNF_INSTALL} clean all" >> "$DOCKERFILE_PATH"
}

printCreateFolder() {
  echo "
RUN mkdir -p /openjdk/target
RUN mkdir -p /openjdk/build" >> "$DOCKERFILE_PATH"
}

printgcc() {
  if [ ${COMMENTS} == true ]; then
    echo "
# Make sure build uses GCC 7" >> "$DOCKERFILE_PATH"
  fi

  echo "
ENV CC=gcc-7 CXX=g++-7" >> "$DOCKERFILE_PATH"
}

printCustomDirs() {
  if [ ${COMMENTS} == true ]; then
    echo "# In podman (in docker do not harm) shared folder is owned by root, and is read for others, unless it already exists" >> "$DOCKERFILE_PATH"
    echo "# So we have to create all future-mounted dirs, with proper owner and permissions" >> "$DOCKERFILE_PATH"
  fi
  for dir in ${DIRS} ; do
    echo "RUN mkdir -p $dir"  >> "$DOCKERFILE_PATH"
    echo "RUN chmod 755 $dir"  >> "$DOCKERFILE_PATH"
    echo "RUN chown -R build $dir"  >> "$DOCKERFILE_PATH"
  done
}

printDockerJDKs() {
  if [ ${COMMENTS} == true ]; then
    echo "
    # Linking of boot jdk must happen after the system jdk is isntalled, as it is iverwriting whatever java/javac from system" >> "$DOCKERFILE_PATH"
  fi
  # JDK8 uses zulu-7 to as it's bootjdk
  if [ "${JDK_VERSION}" != 8 ] && [ "${JDK_VERSION}" != "${JDK_MAX}" ]; then
    if [ "${JDK_VERSION}" == 11 ]; then
      if [ ${COMMENTS} == true ]; then
        echo "
        # JDK 10 is not available on the adoptium API, extract JDK 11 to use as a boot jdk" >> "$DOCKERFILE_PATH"
      fi
      printJDK $((JDK_VERSION))
      echo "RUN ln -sf /usr/lib/jvm/jdk$((JDK_VERSION))/bin/java /usr/bin/java" >> "$DOCKERFILE_PATH"
      echo "RUN ln -sf /usr/lib/jvm/jdk$((JDK_VERSION))/bin/javac /usr/bin/javac" >> "$DOCKERFILE_PATH"
      echo "RUN ln -sf /usr/lib/jvm/jdk$((JDK_VERSION))/bin/keytool /usr/bin/keytool" >> "$DOCKERFILE_PATH"
    else
      if [ ${COMMENTS} == true ]; then
        echo "
        # Extract JDK$((JDK_VERSION-1)) to use as a boot jdk" >> "$DOCKERFILE_PATH"
      fi
      printJDK $((JDK_VERSION-1))
      echo "RUN ln -sf /usr/lib/jvm/jdk$((JDK_VERSION-1))/bin/java /usr/bin/java" >> "$DOCKERFILE_PATH"
      echo "RUN ln -sf /usr/lib/jvm/jdk$((JDK_VERSION-1))/bin/javac /usr/bin/javac" >> "$DOCKERFILE_PATH"
      echo "RUN ln -sf /usr/lib/jvm/jdk$((JDK_VERSION-1))/bin/keytool /usr/bin/keytool" >> "$DOCKERFILE_PATH"
    fi
  fi

  # Build 'jdk' with the most recent GA release
  if [ "${JDK_VERSION}" == "${JDK_MAX}" ]; then
    if [ ${COMMENTS} == true ]; then
      echo "
    # Extract JDK${JDK_GA} to use as a boot jdk" >> "$DOCKERFILE_PATH"
    fi
    printJDK "${JDK_GA}"
    echo "RUN ln -sf /usr/lib/jvm/jdk${JDK_GA}/bin/java /usr/bin/java" >> "$DOCKERFILE_PATH"
    echo "RUN ln -sf /usr/lib/jvm/jdk${JDK_GA}/bin/javac /usr/bin/javac" >> "$DOCKERFILE_PATH"
    echo "RUN ln -sf /usr/lib/jvm/jdk${JDK_GA}/bin/keytool /usr/bin/keytool" >> "$DOCKERFILE_PATH"
  fi

  # shellcheck disable=SC2086
  # if JDK_VERSION is 9, another jdk8 doesn't need to be extracted
  if [ ${JDK_VERSION} != 9 ]; then
    if [ ${COMMENTS} == true ]; then
      echo "# Extract JDK8 to run Gradle" >> "$DOCKERFILE_PATH"
    fi
    printJDK 8
  fi
}

printJDK() {
  local JDKVersion=$1
  echo "
RUN sh -c \"mkdir -p /usr/lib/jvm/jdk$JDKVersion && wget 'https://api.adoptium.net/v3/binary/latest/$JDKVersion/ga/linux/$(adoptiumArch)/jdk/hotspot/normal/adoptium?project=jdk' -O - | tar xzf - -C /usr/lib/jvm/jdk$JDKVersion --strip-components=1\"" >> "$DOCKERFILE_PATH"
}

printGitCloneJenkinsPipelines(){
  echo "
RUN git clone https://github.com/adoptium/ci-jenkins-pipelines /openjdk/pipelines" >> "$DOCKERFILE_PATH"
}

printCopyFolders(){
  echo "
COPY sbin /openjdk/sbin
COPY security /openjdk/security
COPY test /openjdk/test
COPY workspace/config /openjdk/config" >> "$DOCKERFILE_PATH"
}

printGitClone(){
  echo "
RUN git clone https://github.com/adoptium/temurin-build /openjdk/build/openjdk-build" >> "$DOCKERFILE_PATH"
}

printUserCreate(){
  echo "
ARG HostUID
ENV HostUID=\$HostUID
RUN useradd -u \$HostUID -ms /bin/bash build
WORKDIR /openjdk/build
RUN chown -R build /openjdk/" >> "$DOCKERFILE_PATH"
  printCustomDirs
}

printUserSet(){
  echo "
USER build" >> "$DOCKERFILE_PATH"
}

adoptiumArch() {
  local arch
  arch=$(uname -m)
  if [ "$arch" = "x86_64" ] ; then arch="x64" ; fi
  echo "$arch"
}

printContainerVars() {
  echo "
ARG OPENJDK_CORE_VERSION
ENV OPENJDK_CORE_VERSION=\$OPENJDK_CORE_VERSION
ENV ARCHITECTURE=$(adoptiumArch)
ENV JDK_PATH=jdk
ENV JDK8_BOOT_DIR=/usr/lib/jvm/jdk8" >> "$DOCKERFILE_PATH"
}

isRpm() {
  echo "${IMAGE}" | grep -i -e "fedora" -e "centos" -e "rocky" -e "stream" -e "rhel"
}

isDeb() {
  echo "${IMAGE}" | grep -i -e "ubuntu" -e "debian" 
}

isYum() {
  if echo "${IMAGE}" | grep -e "stream7" -e "centos:7" ; then
    DNF_INSTALL=yum
  else
    DNF_INSTALL=dnf
  fi
}

printDepsBase() {
  if isRpm ; then
    isYum
    printDnfPackagesBase
  elif isDeb ;  then
    printAptPackagesBase
    # OpenJ9 MUST use gcc7, HS doesn't have to
    if [ ${OPENJ9} == true ]; then
      printgcc
    fi
  else
    echo "Unknown system, can not install build deps: $IMAGE"
  fi
}

printDepsJdk() {
  if isRpm ; then
    isYum
    printDnfPackagesJdk
  elif isDeb ;  then
    printAptPackagesJdk
    # OpenJ9 MUST use gcc7, HS doesn't have to
    if [ ${OPENJ9} == true ]; then
      printgcc
    fi
  else
    echo "Unknown system, can not install build deps: $IMAGE"
  fi
}

generateFile() {
  mkdir -p "$DOCKERFILE_DIR"
  if [ -f "$DOCKERFILE_PATH" ]; then
    echo "Dockerfile already found"
    exit 1
  fi
  touch "$DOCKERFILE_PATH"
}

generateConfig() {
  if [ ! -f "$DOCKERFILE_DIR/dockerConfiguration.sh" ]; then
    touch "$DOCKERFILE_DIR/dockerConfiguration.sh"
    echo "
#!/bin/bash
# shellcheck disable=SC2034
# Disable for whole file

# This config is read in by configureBuild
BUILD_CONFIG[OS_KERNEL_NAME]=\"linux\"
BUILD_CONFIG[OS_ARCHITECTURE]=\"x86_64\"
BUILD_CONFIG[BUILD_FULL_NAME]=\"linux-x86_64-normal-server-release\"" >> "$DOCKERFILE_DIR/dockerConfiguration.sh"
fi
}

setJDKVars
processArgs "$@"
generateFile
generateConfig
printPreamble
printUserCreate
printDepsBase
printGitCloneJenkinsPipelines
# If building the image straight away, it can't be assumed the folders to be copied are in place
# Therefore create an image that instead git clones openjdk-build and a build can be started there
if [ ${BUILD} == false ]; then
  printCopyFolders
else
  printGitClone
fi
printDepsJdk
printDockerJDKs
printUserSet
printContainerVars

echo "Dockerfile created at $DOCKERFILE_PATH"
if [ "${PRINT}" == true ]; then
  cat "$DOCKERFILE_PATH"
fi
if [ "${BUILD}" == true ]; then
  commandString="/openjdk/build/openjdk-build/makejdk-any-platform.sh -v jdk"

  if [ "${JDK_VERSION}" != "${JDK_MAX}" ]; then
    commandString="${commandString}${JDK_VERSION}"
  fi

  if [ ${OPENJ9} == true ]; then
    commandString="${commandString} --build-variant openj9"
  fi

  # although this works for both docekr and podman with docker alias, it shodl honour the setup of BUILD_CONFIG[CONTAINER_COMMAND] (also maybe with  BUILD_CONFIG[CONTAINER_AS_ROOT] which set sudo/no sudo)
  ${CMD} build -t "jdk${JDK_VERSION}_build_image" -f "$DOCKERFILE_PATH" . --build-arg "OPENJDK_CORE_VERSION=${JDK_VERSION}" --build-arg "HostUID=${UID}"
  echo "To start a build run ${commandString}"
  ${CMD} run -it "jdk${JDK_VERSION}_build_image" bash
fi
