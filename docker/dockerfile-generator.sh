#!/bin/bash
set -eu

OPENJ9=false
BUILD=false
COMMENTS=false
PRINT=false
DOCKERFILE_DIR=
DOCKERFILE_PATH=
# Default to JDK8
JDK_VERSION=8
JDK_MAX=
JDK_GA=

setJDKVars() {
# shellcheck disable=SC2002 # Disable UUOC error
  wget -q https://api.adoptopenjdk.net/v3/info/available_releases
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
    if [ -z $arg ]; then
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
	if [ $2 == "jdk" ]; then
	  JDK_VERSION=$JDK_MAX
	else
	  JDK_VERSION=$(echo $2 | tr -d [:alpha:])
        fi
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
 
  if [ -z "$DOCKERFILE_DIR" ]; then
    DOCKERFILE_DIR=$PWD
  fi

  if [ ${cleanRepo} ]; then
    echo "Removing Dockerfile* from $DOCKERFILE_DIR" && rm -rf $DOCKERFILE_DIR/Dockerfile*
  fi

  DOCKERFILE_PATH="$DOCKERFILE_DIR/Dockerfile"
  if [ ${OPENJ9} == true ]; then
    DOCKERFILE_PATH="$DOCKERFILE_PATH-openj9"
  fi
}

usage() {
  echo" Usage: ./dockerfile_generator.sh [OPTIONS]
  Options:
	  --help | -h		Print this message and exit
	  --build		Build the docker image after generation and create interactive container
	  --clean		Remove all dockerfiles (Dockerfile*) from '--path'
	  --comments		Prints comments into the dockerfile
	  --path <FILEPATH>	Specify where to save the dockerfile (Default: $PWD)
	  --print		Print the Dockerfile to screen after generation
	  --openj9		Make the Dockerfile able to build w/OpenJ9 JIT
	  --version | -v <JDK>	Specify which JDK the docker image will be able to build (Default: jdk8)"
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
  " >> $DOCKERFILE_PATH
}

# Put in apt packages required for building a JDK
printAptPackages() {
  if [ ${COMMENTS} == true ]; then
    echo "
# Install required OS tools
# dirmngr, gpg-agent & coreutils are all required for the apt-add repository command" >> $DOCKERFILE_PATH
  fi

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
    ant \\
    ant-contrib \\
    autoconf \\
    ca-certificates \\
    cmake \\
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
    libxi-dev \\
    libxrandr-dev \\
    libxrender-dev \\
    libxt-dev \\
    libxtst-dev \\
    make \\
    perl \\
    ssh \\
    systemtap-sdt-dev \\
    unzip \\
    wget \\
    zip \\" >> $DOCKERFILE_PATH

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
    zlib1g-dev \\" >> $DOCKERFILE_PATH
  else 
    echo "    ccache \\
    g++ \\
    gcc \\" >> $DOCKERFILE_PATH
  fi
  
  # JDK8 uses zulu-7 as it's bootJDK
  if [ ${JDK_VERSION} == 8 ]; then 
    echo "    zulu-7 \\" >> $DOCKERFILE_PATH
  fi

  echo "  && rm -rf /var/lib/apt/lists/*" >> $DOCKERFILE_PATH
}

printCreateFolder() {
  echo "
RUN mkdir -p /openjdk/target
RUN mkdir -p /openjdk/build" >> $DOCKERFILE_PATH
}

printgcc() {
  if [ ${COMMENTS} == true ]; then
    echo "
# Make sure build uses GCC 7" >> $DOCKERFILE_PATH
  fi

  echo "
ENV CC=gcc-7 CXX=g++-7" >> $DOCKERFILE_PATH
}

printDockerJDKs() {
  # JDK8 uses zulu-7 to as it's bootjdk
  if [ ${JDK_VERSION} != 8 ] && [ ${JDK_VERSION} != ${JDK_MAX} ]; then
    if [ ${COMMENTS} == true ]; then
      echo "
    # Extract JDK$((JDK_VERSION-1)) to use as a boot jdk" >> $DOCKERFILE_PATH
    fi
    printJDK $((JDK_VERSION-1))
    echo "RUN ln -sf /usr/lib/jvm/jdk$((JDK_VERSION-1))/bin/java /usr/bin/java" >> $DOCKERFILE_PATH
    echo "RUN ln -sf /usr/lib/jvm/jdk$((JDK_VERSION-1))/bin/javac /usr/bin/javac" >> $DOCKERFILE_PATH
    echo "RUN ln -sf /usr/lib/jvm/jdk$((JDK_VERSION-1))/bin/keytool /usr/bin/keytool" >> $DOCKERFILE_PATH
  fi

  # Build 'jdk' with the most recent GA release
  if [ ${JDK_VERSION} == ${JDK_MAX} ]; then
    if [ ${COMMENTS} == true ]; then
      echo "
    # Extract JDK${JDK_GA} to use as a boot jdk" >> $DOCKERFILE_PATH
    fi
    printJDK ${JDK_GA}
    echo "RUN ln -sf /usr/lib/jvm/jdk${JDK_GA}/bin/java /usr/bin/java" >> $DOCKERFILE_PATH
    echo "RUN ln -sf /usr/lib/jvm/jdk${JDK_GA}/bin/javac /usr/bin/javac" >> $DOCKERFILE_PATH
    echo "RUN ln -sf /usr/lib/jvm/jdk${JDK_GA}/bin/keytool /usr/bin/keytool" >> $DOCKERFILE_PATH
  fi
 
  # if JDK_VERSION is 9, another jdk8 doesn't need to be extracted
  if [ ${JDK_VERSION} != 9 ]; then
    if [ ${COMMENTS} == true ]; then
      echo "# Extract JDK8 to run Gradle" >> $DOCKERFILE_PATH
    fi
    printJDK 8
  fi
}

printJDK() {
  local JDKVersion=$1
  echo "
RUN sh -c \"mkdir -p /usr/lib/jvm/jdk$JDKVersion && wget 'https://api.adoptopenjdk.net/v3/binary/latest/$JDKVersion/ga/linux/x64/jdk/hotspot/normal/adoptopenjdk?project=jdk' -O - | tar xzf - -C /usr/lib/jvm/jdk$JDKVersion --strip-components=1\"" >> $DOCKERFILE_PATH
}

printCopyFolders(){
  echo "
COPY sbin /openjdk/sbin
COPY security /openjdk/security
COPY workspace/config /openjdk/config
COPY pipelines /openjdk/pipelines" >> $DOCKERFILE_PATH
}

printGitClone(){
  echo "
RUN git clone https://github.com/adoptopenjdk/openjdk-build /openjdk/build/openjdk-build" >> $DOCKERFILE_PATH
}

printUserCreate(){
  echo "
ARG HostUID
ENV HostUID=\$HostUID
RUN useradd -u \$HostUID -ms /bin/bash build
WORKDIR /openjdk/build
RUN chown -R build /openjdk/
USER build" >> $DOCKERFILE_PATH
}

printContainerVars(){
  echo "
ARG OPENJDK_CORE_VERSION
ENV OPENJDK_CORE_VERSION=\$OPENJDK_CORE_VERSION
ENV ARCHITECTURE=x64
ENV JDK_PATH=jdk
ENV JDK8_BOOT_DIR=/usr/lib/jvm/jdk8" >> $DOCKERFILE_PATH
}

generateFile() {
  mkdir -p $DOCKERFILE_DIR
  if [ -f $DOCKERFILE_PATH ]; then
    echo "Dockerfile already found"
    exit 1
  fi
  touch $DOCKERFILE_PATH
}

generateConfig() {
  if [ ! -f $DOCKERFILE_DIR/dockerConfiguration.sh ]; then
    touch $DOCKERFILE_DIR/dockerConfiguration.sh
    echo "
#!/bin/bash
# shellcheck disable=SC2034
# Disable for whole file

# This config is read in by configureBuild
BUILD_CONFIG[OS_KERNEL_NAME]=\"linux\"
BUILD_CONFIG[OS_ARCHITECTURE]=\"x86_64\"
BUILD_CONFIG[BUILD_FULL_NAME]=\"linux-x86_64-normal-server-release\"" >> $DOCKERFILE_DIR/dockerConfiguration.sh
fi
}

setJDKVars
processArgs "$@"
generateFile
generateConfig
printPreamble
printAptPackages
# OpenJ9 MUST use gcc7, HS doesn't have to
if [ ${OPENJ9} == true ]; then
  printgcc
fi

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

echo "Dockerfile created at $DOCKERFILE_PATH"
if [ "${PRINT}" == true ]; then
  cat $DOCKERFILE_PATH
fi
if [ "${BUILD}" == true ]; then
  commandString="/openjdk/build/openjdk-build/makejdk-any-platform.sh -v jdk"

  if [ ${JDK_VERSION} != ${JDK_MAX} ]; then
    commandString="${commandString}${JDK_VERSION}"
  fi

  if [ ${OPENJ9} == true ]; then
    commandString="${commandString} --build-variant openj9"
  fi

  docker build -t jdk${JDK_VERSION}_build_image -f $DOCKERFILE_PATH . --build-arg "OPENJDK_CORE_VERSION=${JDK_VERSION}" --build-arg "HostUID=${UID}"
  echo "To start a build run ${commandString}"
  docker run -it jdk${JDK_VERSION}_build_image bash
fi
