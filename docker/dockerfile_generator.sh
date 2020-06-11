#!/bin/bash

OPENJ9=false
BUILD=false
COMMENTS=false
DFDIR=
DFPATH=
# Default to JDK8
JDK=8

# This refers to the number 'JDKnext' will be
JDK_MAX=15

processArgs() {
  local key
  local cleanRepo
  while [[ $# -gt 0 ]]
  do	
    key="$1"
    case $key in
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
      --path)
        DFDIR=$2
        shift
        shift
        ;;
      --print)
	PRINT=true
	shift
	;;
      --jdk)
        JDK="$2"
	checkJDK
	shift
	shift
	;;
      *)
        echo "Unrecognised Argument: $1"
        exit 1
        ;;
    esac
  done
  
  [ -z "$DFDIR" ] && DFDIR=$PWD
  [ ${cleanRepo} ] && echo "Removing Dockerfile.JDK* from $DFDIR" && rm -rf $DFDIR/Dockerfile.JDK*
  DFPATH="$DFDIR/Dockerfile"
  [ ${OPENJ9} == true ] && DFPATH="$DFPATH-openj9"
}

debug() {
  echo "VARIABLES:
    OPENJ9=${OPENJ9}
    BUILD=${BUILD}
    DFDIR=${DFDIR}
    DFPATH=${DFPATH}
    JDK=${JDK}"
}

usage() {
  echo" Usage: ./dockerfile_generator.sh [OPTIONS]
  Options:
	  --help | -h		Print this message and exit
	  --build		Build the docker image after generation and create interactive container
	  --clean		Remove all dockerfiles (Dockerfile.JDK*) from '--path'
	  --comments		Prints comments into the dockerfile
	  --jdk			Specify which JDK the docker image will be able to build (Default: 8)
	  --path <FILEPATH>	Specify where to save the dockerfile (Default: $PWD)
	  --print		Print the Dockerfile to screen after generation
	  --openj9		Make the Dockerfile able to build w/OpenJ9 JIT"
}

# Checks to ensure the input JDK is valid
checkJDK() {
  [ ${JDK} == "next" ] && JDK=${JDK_MAX}
  if ! ((JDK >=8 && JDK <= JDK_MAX)); then
    echo "Please input a JDK between 8 & ${JDK_MAX} or 'next'"
    exit 1
  fi

}

# Put in license, 'FROM' statement and 'LABEL' statement
printPreamble() {
  echo "
#
# Licensed under the Apache License, Version 2.0 (the \"License\");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an \"AS IS\" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

FROM ubuntu:18.04

LABEL maintainer=\"AdoptOpenJDK <adoption-discuss@openjdk.java.net>\"
  " >> $DFPATH
}

# Put in apt packages required for building a JDK
printAptPackages() {
  [ ${COMMENTS} == true ] && echo "
# Install required OS tools
# dirmngr, gpg-agent & coreutils are all required for the apt-add repository command" >> $DFPATH

  echo " 
RUN apt-get update \\
  && apt-get install -qq -u --no-install-recommends \\
    software-properties-common \\
    dirmngr \\
    gpg-agent \\
    coreutils \\
  && apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys 0x219BD9C9 \\
  && add-apt-repository 'deb http://repos.azulsystems.com/ubuntu stable main' \\
  && apt-get update \\
  && apt-get -y upgrade \\
  && apt-get install -qq -y --no-install-recommends \\
    autoconf \\
    cpio \\
    curl \\
    file \\
    git \\
    libasound2-dev \\
    libcups2-dev \\
    libelf-dev \\
    libfontconfig1-dev \\
    libfreetype6-dev \\
    libx11-dev \\
    libxext-dev \\
    libxrandr-dev \\
    libxrender-dev \\
    libxt-dev \\
    libxtst-dev \\
    make \\
    ssh \\
    systemtap-sdt-dev \\
    unzip \\
    wget \\
    zip \\" >> $DFPATH

  if [ ${OPENJ9} = true ]; then
    echo "    libdwarf-dev \\
    libnuma-dev \\
    nasm \\
    pkg-config \\" >> $DFPATH
  else 
    echo "    ccache \\
    g++ \\
    gcc \\" >> $DFPATH
  fi
  
  # JDK8 uses zulu-7 as it's bootJDK
  [ ${JDK} == 8 ] && echo "    zulu-7 \\" >> $DFPATH

  echo "  && rm -rf /var/lib/apt/lists/*" >> $DFPATH
}

printCreateFolder() {
  echo "
RUN mkdir -p /openjdk/target
RUN mkdir -p /openjdk/build" >> $DFPATH
}

printgcc() {
  [ ${COMMENTS} == true ] && echo "
# Make sure build uses GCC 7.3
# Create links for GCC to access the C library and gcc,g++" >> $DFPATH

  echo "
RUN cd /usr/local \\
  && wget -O gcc-7.tar.xz "https://ci.adoptopenjdk.net/userContent/gcc/gcc730+ccache.x86_64.tar.xz" \\
  && tar -xJf gcc-7.tar.xz \\
  && rm -rf gcc-7.tar.xz" >> $DFPATH

  echo "
RUN ln -s /usr/lib/x86_64-linux-gnu /usr/lib64 \\
  && ln -s /usr/include/x86_64-linux-gnu/* /usr/local/gcc/include \\
  && ln -s /usr/local/gcc/bin/g++-7.3 /usr/bin/g++ \\
  && ln -s /usr/local/gcc/bin/gcc-7.3 /usr/bin/gcc \\
  && ln -s /usr/local/gcc/bin/ccache /usr/local/bin/ccache" >> $DFPATH
}

printDockerJDKs() {
  if [ ${JDK} != 8 ]; then
    [ ${COMMENTS} == true ] && echo "
    # Extract JDK$((JDK-1)) to use as a boot jdk" >> $DFPATH
    printJDK $((JDK-1))
    echo "RUN ln -sf /usr/lib/jvm/jdk$((JDK-1))/bin/java /usr/bin/java" >> $DFPATH
    echo "RUN ln -sf /usr/lib/jvm/jdk$((JDK-1))/bin/javac /usr/bin/javac" >> $DFPATH
  fi  
  if [ ${JDK} != 9 ]; then
    [ ${COMMENTS} == true ] && echo "# Extract JDK8 to run Gradle" >> $DFPATH
    printJDK 8
  fi
}

printJDK() {
  local JDKVersion=$1
  echo "
RUN sh -c \"mkdir -p /usr/lib/jvm/jdk$JDKVersion && wget 'https://api.adoptopenjdk.net/v3/binary/latest/$JDKVersion/ga/linux/x64/jdk/hotspot/normal/adoptopenjdk?project=jdk' -O - | tar xzf - -C /usr/lib/jvm/jdk$JDKVersion --strip-components=1\"" >> $DFPATH
}

printCopyFolders(){
  echo "
COPY sbin /openjdk/sbin
COPY workspace/config /openjdk/config
COPY pipelines /openjdk/pipelines" >> $DFPATH
}

printGitClone(){
  echo "
RUN git clone https://github.com/adoptopenjdk/openjdk-build /openjdk/build/openjdk-build" >> $DFPATH
}

printUserCreate(){
  echo "
ARG HostUID
ENV HostUID=\$HostUID
RUN useradd -u \$HostUID -ms /bin/bash build
RUN chown -R build /openjdk/
USER build
WORKDIR /openjdk/build/" >> $DFPATH
}

printContainerVars(){
  echo "
ARG OPENJDK_CORE_VERSION
ENV OPENJDK_CORE_VERSION=\$OPENJDK_CORE_VERSION
ENV ARCHITECTURE=x64
ENV JDK_PATH=jdk
ENV JDK8_BOOT_DIR=/usr/lib/jvm/jdk8" >> $DFPATH
}

generateFile() {
  mkdir -p $DFDIR
  [ -f $DFPATH ] && echo "Dockerfile already found" && exit 1
  touch $DFPATH
}

generateConfig() {
  if [ ! -f $DFDIR/dockerConfiguration.sh ]; then
    touch $DFDIR/dockerConfiguration.sh
    echo "
#!/bin/bash
# shellcheck disable=SC2034
# Disable for whole file

# This config is read in by configureBuild
BUILD_CONFIG[OS_KERNEL_NAME]=\"linux\"
BUILD_CONFIG[OS_ARCHITECTURE]=\"x86_64\"
BUILD_CONFIG[BUILD_FULL_NAME]=\"linux-x86_64-normal-server-release\"" >> $DFDIR/dockerConfiguration.sh
fi
}

processArgs "$@"
generateFiles
generateConfig
printPreamble
printAptPackages
printTargetFolder
# OpenJ9 MUST use gcc7, HS doesn't have to
[ ${OPENJ9} == true ] && printgcc

printDockerJDKs

# If building the image straight away, it can't be assumed the folders to be copied are in place
# Therefore create an image that instead git clones openjdk-build and a build can be started there
if [ ${BUILD} == false ]; then
  printCopyFolders
else
  printGitClone
fi

printUserCreate
printContainerVars

echo "Dockerfile created at $DFPATH"
[ "${PRINT}" == true ] && cat $DFPATH
if [ "${BUILD}" == true ]; then
  commandString="/openjdk/build/openjdk-build/makejdk-any-platform.sh -v jdk"
  [ ${JDK} == ${JDK_MAX} ] || commandString="${commandString}${JDK}"
  [ ${OPENJ9} == true ] && commandString="${commandString} --build-variant openj9"
  docker build -t jdk${JDK}_build_image -f $DFPATH . --build-arg "OPENJDK_CORE_VERSION=${JDK}" --build-arg "HostUID=${UID}"
  echo "To start a build run ${commandString}"
  docker run -it jdk${JDK}_build_image bash
fi
