#!/bin/bash

if [ "${PLATFORM}" == "Linux" ] && [ "${ARCHITECTURE}" == "x64" ]
then
  export PATH=/opt/rh/devtoolset-2/root/usr/bin:$PATH
  if [ -r /opt/rh/devtoolset-2/root/usr/bin/g++-NO ]; then
    export CC=/opt/rh/devtoolset-2/root/usr/bin/gcc
    export CXX=/opt/rh/devtoolset-2/root/usr/bin/g++
    ls -l $CC $CXX
    $CC --version
    $CXX --version
  fi
fi

if [ "${PLATFORM}" == "Windows" ]
then
  export ANT_HOME=/cygdrive/C/Projects/OpenJDK/apache-ant-1.10.1
  export ALLOW_DOWNLOADS=true
  export LANG=C
  export JAVA_HOME=$JDK_BOOT_DIR
  export BUILD_ARGS="--tmp-space-build ${BUILD_ARGS}"

  if [ "${ARCHITECTURE}" == "x64" ] && [ "${VARIANT}" == "openj9" ]
  then
    export PATH="/usr/bin:$PATH"

    if [ "${JAVA_TO_BUILD}" == "jdk8u" ]
    then
      export INCLUDE="C:\Program Files\Debugging Tools for Windows (x64)\sdk\inc;%INCLUDE%"
      export CONFIGURE_ARGS_FOR_ANY_PLATFORM="${CONFIGURE_ARGS_FOR_ANY_PLATFORM} --with-freetype-include=/cygdrive/c/openjdk/freetype-2.5.3/include --with-freetype-lib=/cygdrive/c/openjdk/freetype-2.5.3/lib64 --with-freemarker-jar=/cygdrive/c/openjdk/freemarker.jar"
    elif [ "${JAVA_TO_BUILD}" == "jdk9" ]
    then
      export CONFIGURE_ARGS_FOR_ANY_PLATFORM="${CONFIGURE_ARGS_FOR_ANY_PLATFORM} --with-freetype-src=/cygdrive/c/openjdk/freetype-2.5.3 --with-toolchain-version=2013 --with-freemarker-jar=/cygdrive/c/openjdk/freemarker.jar"
    elif [ "${JAVA_TO_BUILD}" == "jdk10u" ]
    then
      export CONFIGURE_ARGS_FOR_ANY_PLATFORM="${CONFIGURE_ARGS_FOR_ANY_PLATFORM} --with-freemarker-jar=/cygdrive/c/openjdk/freemarker.jar"
    fi
  fi
fi

if [ "${PLATFORM}" == "Mac" ]
then
  export MACOSX_DEPLOYMENT_TARGET=10.8
  sudo xcode-select --switch "${XCODE_SWITCH_PATH}"
fi

if [ "${PLATFORM}" == "Aix" ] && [ "${ARCHITECTURE}" == "x64" ] && [ "${VARIANT}" == "openj9" ]
then
    export CONFIGURE_ARGS_FOR_ANY_PLATFORM="${CONFIGURE_ARGS_FOR_ANY_PLATFORM} --with-freemarker-jar=/ramdisk0/build/workspace/openjdk9_openj9_build_ppc64_aix/freemarker-2.3.8/lib/freemarker.jar DF=/usr/sysv/bin/df"
fi