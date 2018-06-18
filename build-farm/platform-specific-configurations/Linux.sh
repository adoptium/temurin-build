#!/bin/bash

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# shellcheck source=sbin/common/constants.sh
source "$SCRIPT_DIR/../../sbin/common/constants.sh"

if [ "${ARCHITECTURE}" == "x64" ]
then
  export PATH=/opt/rh/devtoolset-2/root/usr/bin:$PATH
  if [ -r /opt/rh/devtoolset-2/root/usr/bin/g++-NO ]; then
    export CC=/opt/rh/devtoolset-2/root/usr/bin/gcc
    export CXX=/opt/rh/devtoolset-2/root/usr/bin/g++
    ls -l $CC $CXX
    $CC --version
    $CXX --version
  fi
elif [ "${ARCHITECTURE}" == "s390x" ]
then
  export LANG=C

  if [ "${VARIANT}" == "openj9" ]
  then
    export PATH="/usr/bin:$PATH"

    if [ "${JAVA_TO_BUILD}" == "${JDK8_VERSION}" ]
    then
      if which g++-4.8; then
        export CC=gcc-4.8
        export CXX=g++-4.8
      fi
    fi
  fi
elif [ "${ARCHITECTURE}" == "ppc64le" ]
then
  export LANG=C
elif [ "${ARCHITECTURE}" == "arm" ]
then
  export CONFIGURE_ARGS_FOR_ANY_PLATFORM="--with-jobs=4 --with-memory-size=2000"
fi

if [ "${ARCHITECTURE}" == "s390x" ] || [ "${ARCHITECTURE}" == "ppc64le" ]
then
    if [ "${JAVA_TO_BUILD}" == "${JDK10_VERSION}" ] && [ "${VARIANT}" == "openj9" ]
    then
      if [ -z "$JDK9_BOOT_DIR" ]; then
        export JDK9_BOOT_DIR=$PWD/jdk-9+181
        if [ ! -r $JDK9_BOOT_DIR ]; then
          wget -O -  https://github.com/AdoptOpenJDK/openjdk9-releases/releases/download/jdk-9%2B181/OpenJDK9_s390x_Linux_jdk-9.181.tar.gz | tar xpfz -
        fi
      fi

      export JDK_BOOT_DIR=$JDK9_BOOT_DIR
      export CC=gcc-4.8
      export CXX=g++-4.8
    fi
fi