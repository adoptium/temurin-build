#!/bin/bash

export ANT_HOME=/cygdrive/C/Projects/OpenJDK/apache-ant-1.10.1
export ALLOW_DOWNLOADS=true
export LANG=C
export JAVA_HOME=$JDK_BOOT_DIR
export BUILD_ARGS="--tmp-space-build ${BUILD_ARGS}"


if [ "${JAVA_TO_BUILD}" == "jdk8u" ]
then
  export PATH="/cygdrive/c/Program Files (x86)/Microsoft Visual Studio 10.0/VC/bin/amd64/:/cygdrive/C/Projects/OpenJDK/make-3.82/:$PATH"
  export CONFIGURE_ARGS_FOR_ANY_PLATFORM="${CONFIGURE_ARGS_FOR_ANY_PLATFORM} with_freetype=/cygdrive/C/Projects/OpenJDK/freetype  --disable-ccache"
elif [ "${JAVA_TO_BUILD}" == "jdk9" ]
then
  export PATH="/usr/bin:/cygdrive/c/Program Files (x86)/Microsoft Visual Studio 10.0/VC/bin/amd64/:$PATH"
  export CONFIGURE_ARGS_FOR_ANY_PLATFORM="${CONFIGURE_ARGS_FOR_ANY_PLATFORM} --with-freetype=/cygdrive/C/openjdk/freetype --disable-ccache"
elif [ "${JAVA_TO_BUILD}" == "jdk10u" ]
then
  export PATH="/usr/bin:/cygdrive/c/Program Files (x86)/Microsoft Visual Studio 10.0/VC/bin/amd64/:$PATH"
  export CONFIGURE_ARGS_FOR_ANY_PLATFORM="${CONFIGURE_ARGS_FOR_ANY_PLATFORM} --with-freetype-src=/cygdrive/c/openjdk/freetype-2.5.3 --with-toolchain-version=2013 --disable-ccache"
fi


if [ "${ARCHITECTURE}" == "x64" ] && [ "${VARIANT}" == "openj9" ]
then
  export PATH="/usr/bin:$PATH"

  if [ "${JAVA_TO_BUILD}" == "jdk8u" ]
  then
    export INCLUDE="C:\Program Files\Debugging Tools for Windows (x64)\sdk\inc;%INCLUDE%"
    export PATH="$PATH:/c/cygwin64/bin"
    export CONFIGURE_ARGS_FOR_ANY_PLATFORM="${CONFIGURE_ARGS_FOR_ANY_PLATFORM} --with-freetype-include=/cygdrive/c/openjdk/freetype-2.5.3/include --with-freetype-lib=/cygdrive/c/openjdk/freetype-2.5.3/lib64 --with-freemarker-jar=/cygdrive/c/openjdk/freemarker.jar"
  elif [ "${JAVA_TO_BUILD}" == "jdk9" ]
  then
    export CONFIGURE_ARGS_FOR_ANY_PLATFORM="${CONFIGURE_ARGS_FOR_ANY_PLATFORM} --with-freetype-src=/cygdrive/c/openjdk/freetype-2.5.3 --with-toolchain-version=2013 --with-freemarker-jar=/cygdrive/c/openjdk/freemarker.jar"
  elif [ "${JAVA_TO_BUILD}" == "jdk10u" ]
  then
    export CONFIGURE_ARGS_FOR_ANY_PLATFORM="${CONFIGURE_ARGS_FOR_ANY_PLATFORM} --with-freemarker-jar=/cygdrive/c/openjdk/freemarker.jar"
  fi
fi