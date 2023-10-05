#!/bin/bash
# shellcheck disable=SC1091
# ********************************************************************************
# Copyright (c) 2018 Contributors to the Eclipse Foundation
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

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# shellcheck source=sbin/common/constants.sh
source "$SCRIPT_DIR/../../sbin/common/constants.sh"
source "$SCRIPT_DIR/../../sbin/common/downloaders.sh"

if [[ "$JAVA_FEATURE_VERSION" -ge 21 ]]; then
  # jdk-21+ uses "bundled" FreeType
  export BUILD_ARGS="${BUILD_ARGS} --freetype-dir bundled"
else
  # Bundling our own freetype can cause problems, so we skip that on linux.
  export BUILD_ARGS="${BUILD_ARGS} --skip-freetype"
fi

## This affects Alpine docker images and also evaluation pipelines
if [ "$(pwd | wc -c)" -gt 83 ]; then
  # Use /tmp for alpine in preference to $HOME as Alpine fails gpg operation if PWD > 83 characters
  # Alpine also cannot create ~/.gpg-temp within a docker context
  GNUPGHOME="$(mktemp -d /tmp/.gpg-temp.XXXXXX)"
else
  GNUPGHOME="${WORKSPACE:-$PWD}/.gpg-temp"
fi
if [ ! -d "$GNUPGHOME" ]; then
    mkdir -m 700 "$GNUPGHOME"
fi
export GNUPGHOME

NATIVE_API_ARCH=$(uname -m)
if [ "${NATIVE_API_ARCH}" = "x86_64" ]; then NATIVE_API_ARCH=x64; fi
if [ "${NATIVE_API_ARCH}" = "armv7l" ]; then NATIVE_API_ARCH=arm; fi

function locateDragonwell8BootJDK()
{
  if [ -d /opt/dragonwell8 ]; then
    export "${BOOT_JDK_VARIABLE}"=/opt/dragonwell8
  elif [ -d /usr/lib/jvm/dragonwell8 ]; then
    export "${BOOT_JDK_VARIABLE}"=/usr/lib/jvm/dragonwell8
  else
    echo Dragonwell 8 requires a Dragonwell boot JDK - downloading one ...
    mkdir -p "$PWD/jdk8"
    # if [ "$(uname -m)" = "x86_64" ]; then
    #   curl -L "https://github.com/alibaba/dragonwell8/releases/download/dragonwell-8.11.12_jdk8u332-ga/Alibaba_Dragonwell_8.11.12_x64_linux.tar.gz" | tar xpzf - --strip-components=1 -C "$PWD/jdk8"
    # elif [ "$(uname -m)" = "aarch64" ]; then
    #   curl -L "https://github.com/alibaba/dragonwell8/releases/download/dragonwell-8.8.9_jdk8u302-ga/Alibaba_Dragonwell_8.8.9_aarch64_linux.tar.gz" | tar xpzf - --strip-components=1 -C "$PWD/jdk8"
    # else
    #   echo "Unknown architecture $(uname -m) for building Dragonwell - cannot download boot JDK"
    #   exit 1
    # fi
    ## Secure Dragonwell Downloads By Validating Checksums
    if [ "$(uname -m)" = "x86_64" ]; then
      DOWNLOAD_URL="https://github.com/alibaba/dragonwell8/releases/download/dragonwell-8.11.12_jdk8u332-ga/Alibaba_Dragonwell_8.11.12_x64_linux.tar.gz"
      EXPECTED_SHA256="E03923f200dffddf9eee2aadc0c495674fe0b87cc2eece94a9a8dec84812d12bd"
    elif [ "$(uname -m)" = "aarch64" ]; then
      DOWNLOAD_URL="https://github.com/alibaba/dragonwell8/releases/download/dragonwell-8.8.9_jdk8u302-ga/Alibaba_Dragonwell_8.8.9_aarch64_linux.tar.gz"
      EXPECTED_SHA256="ff0594f36d13883972ca0b302d35cca5099f10b8be54c70c091f626e4e308774"
    else
      echo "Unknown architecture $(uname -m) for building Dragonwell - cannot download boot JDK"
      exit 1
    fi
    # Download the file and calculate its SHA256 checksum
    TMP_FILE=$(mktemp)
    curl -L "$DOWNLOAD_URL" -o "$TMP_FILE"

    # Calculate the SHA256 checksum of the downloaded file
    ACTUAL_SHA256=$(sha256sum "$TMP_FILE" | awk '{print $1}')

    # Compare the actual and expected SHA256 checksums
    if [ "$ACTUAL_SHA256" != "$EXPECTED_SHA256" ]; then
      echo "Checksum verification failed for downloaded file!"
      rm "$TMP_FILE"
      exit 1
    fi

    # Extract the downloaded file
    tar xpzf "$TMP_FILE" --strip-components=1 -C "$PWD/jdk8"

    # Clean up the temporary file
    rm "$TMP_FILE"
    export "${BOOT_JDK_VARIABLE}"="$PWD/jdk8"
  fi
}

function setCrossCompilerEnvironment()
{
  if [ "${VARIANT}" == "${BUILD_VARIANT_OPENJ9}" ]; then
    export BUILDJDK=${WORKSPACE:-$PWD}/buildjdk
    echo "RISCV cross-compilation for OpenJ9 ... Downloading required nightly OpenJ9/${NATIVE_API_ARCH} as build JDK to $BUILDJDK"
    rm -rf "$BUILDJDK"
    mkdir "$BUILDJDK"
    # TOFIX: Switch this back once Semeru has an API to pull the nightly builds.
    curl -L "https://api.adoptopenjdk.net/v3/binary/latest/${JAVA_FEATURE_VERSION}/ga/linux/${NATIVE_API_ARCH}/jdk/openj9/normal/adoptopenjdk" | tar xpzf - --strip-components=1 -C "$BUILDJDK"
    "$BUILDJDK/bin/java" -version 2>&1 | sed 's/^/CROSSBUILD JDK > /g' || exit 1
    CONFIGURE_ARGS_FOR_ANY_PLATFORM="${CONFIGURE_ARGS_FOR_ANY_PLATFORM} --with-build-jdk=$BUILDJDK --disable-ddr"
    if [ -d /usr/local/openssl102 ]; then
      CONFIGURE_ARGS_FOR_ANY_PLATFORM="${CONFIGURE_ARGS_FOR_ANY_PLATFORM} --with-openssl=/usr/local/openssl102"
    fi
  elif [ "${VARIANT}" == "${BUILD_VARIANT_BISHENG}" ]; then
    if [ -r /usr/local/gcc/bin/gcc-7.5 ]; then
      BUILD_CC=/usr/local/gcc/bin/gcc-7.5
      BUILD_CXX=/usr/local/gcc/bin/g++-7.5
      BUILD_LIBRARY_PATH=/usr/local/gcc/lib64:/usr/local/gcc/lib
    fi
    # Check if BUILD_CXX/BUILD_CC for Bisheng RISC-V exists
    if [ ! -x "$BUILD_CXX" ]; then
      echo "Bisheng RISC-V host compiler BUILD_CXX=$BUILD_CXX does not exist on this system - cannot continue"
      exit 1
    fi
  fi

  # RISC-V cross compile settings for all VARIANT values
  echo RISC-V cross-compilation setup ...  Setting RISCV64, LD_LIBRARY_PATH, PATH, CC, CXX
  export RISCV64=/opt/riscv_toolchain_linux
  export LD_LIBRARY_PATH=$RISCV64/lib64
  if [ "${VARIANT}" == "${BUILD_VARIANT_BISHENG}" ]; then
    export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$BUILD_LIBRARY_PATH
  fi

  if [ -r "$RISCV64/bin/riscv64-unknown-linux-gnu-g++" ]; then
    export CC=$RISCV64/bin/riscv64-unknown-linux-gnu-gcc
    export CXX=$RISCV64/bin/riscv64-unknown-linux-gnu-g++
    export PATH="$RISCV64/bin:$PATH"
  elif [ -r /usr/bin/riscv64-linux-gnu-g++ ]; then
    export CC=/usr/bin/riscv64-linux-gnu-gcc
    export CXX=/usr/bin/riscv64-linux-gnu-g++
    # This is required for OpenJ9 if not using "riscv64-unknown-linux-gnu-*"
    # i.e. if using the default cross compiler supplied with Debian/Ubuntu
    export RISCV_TOOLCHAIN_TYPE=install
  fi
  RISCV_SYSROOT=${RISCV_SYSROOT:-/opt/fedora28_riscv_root}
  if [ ! -d "${RISCV_SYSROOT}" ]; then
     echo "RISCV_SYSROOT=${RISCV_SYSROOT} is undefined or does not exist - cannot proceed"
     exit 1
  fi
  CONFIGURE_ARGS_FOR_ANY_PLATFORM="${CONFIGURE_ARGS_FOR_ANY_PLATFORM} --openjdk-target=riscv64-unknown-linux-gnu --with-sysroot=${RISCV_SYSROOT} -with-boot-jdk=$JDK_BOOT_DIR"

  # RISC-V cross compilation does not work with OpenJ9's option: --with-openssl=fetched
  # TODO: This file needs an overhaul as it's getting too long and hard to maintain ...
  if [ "${VARIANT}" == "${BUILD_VARIANT_OPENJ9}" ]; then
    # shellcheck disable=SC2001
    CONFIGURE_ARGS_FOR_ANY_PLATFORM=$(echo "$CONFIGURE_ARGS_FOR_ANY_PLATFORM" | sed "s,with-openssl=[^ ]*,with-openssl=${RISCV_SYSROOT}/usr,g")
    if ! which qemu-riscv64-static; then
      # don't download it if we already have it from a previous build
      if [ ! -x "$WORKSPACE/qemu-riscv64-static" ]; then
        echo Download qemu-riscv64-static as it is required for the OpenJ9 cross build ...
        curl https://ci.adoptium.net/userContent/riscv/qemu-riscv64-static.xz | xz -d > "$WORKSPACE/qemu-riscv64-static" && \
        chmod 755 "$WORKSPACE/qemu-riscv64-static"
      fi
      export PATH="$PATH:$WORKSPACE" && \
      qemu-riscv64-static --version
    fi
  fi

  if [ "${VARIANT}" == "${BUILD_VARIANT_BISHENG}" ]; then
    CONFIGURE_ARGS_FOR_ANY_PLATFORM="${CONFIGURE_ARGS_FOR_ANY_PLATFORM} --with-jvm-features=shenandoahgc BUILD_CC=$BUILD_CC BUILD_CXX=$BUILD_CXX"
  fi
  BUILD_ARGS="${BUILD_ARGS} --cross-compile -F"
  if [ ! -x "$CXX" ]; then
    echo "RISC-V cross compiler CXX=$CXX does not exist on this system - cannot continue"
    exit 1
  fi
}

if [ "${ARCHITECTURE}" == "x64" ]
then
  export PATH=/opt/rh/devtoolset-2/root/usr/bin:$PATH
fi

## Fix For Issue https://github.com/adoptium/temurin-build/issues/3547
## Add Missing Library Path For Ubuntu 22+
if [ -e /etc/os-release ]; then
  ID=$(grep "^ID=" /etc/os-release | awk -F'=' '{print $2}')
  INT_VERSION_ID=$(grep "^VERSION_ID=" /etc/os-release | awk -F'"' '{print $2}' | awk -F'.' '{print $1}')
  LIB_ARCH=$(uname -m)-linux-gnu
  if [ "$ID" == "ubuntu" ] && [ "$INT_VERSION_ID" -ge "22" ]; then
      export LIBRARY_PATH=/usr/lib/$LIB_ARCH:$LIBRARY_PATH
  fi
fi

if [ "${ARCHITECTURE}" == "s390x" ]
then
  export LANG=C

  if [ "${VARIANT}" == "${BUILD_VARIANT_OPENJ9}" ]
  then
    # Any version below 11
    if [ "$JAVA_FEATURE_VERSION" -lt 11 ]
    then
      if which g++-4.8; then
        export CC=gcc-4.8
        export CXX=g++-4.8
      fi
    fi
  fi
fi

if [ "${VARIANT}" == "${BUILD_VARIANT_OPENJ9}" ]
then
  # OpenJ9 fetches the latest OpenSSL in their get_source.sh
  export CONFIGURE_ARGS_FOR_ANY_PLATFORM="${CONFIGURE_ARGS_FOR_ANY_PLATFORM} --with-openssl=fetched"

  if [ "${ARCHITECTURE}" == "ppc64le" ] || [ "${ARCHITECTURE}" == "x64" ]
  then
    CUDA_HOME=/usr/local/cuda
    if [ -f $CUDA_HOME/include/cuda.h ]
    then
      export CONFIGURE_ARGS_FOR_ANY_PLATFORM="${CONFIGURE_ARGS_FOR_ANY_PLATFORM} --enable-cuda --with-cuda=$CUDA_HOME"
    fi
  fi
fi

if [ "${ARCHITECTURE}" == "ppc64le" ]
then
  export LANG=C
fi

# Solves issues seen on 4GB HC4 systems with two large ld processes
if [ "$(awk '/^MemTotal:/{print$2}' < /proc/meminfo)" -lt "5000000" ]
then
  export CONFIGURE_ARGS_FOR_ANY_PLATFORM="${CONFIGURE_ARGS_FOR_ANY_PLATFORM} --with-extra-ldflags=-Wl,--no-keep-memory"
fi

if [ "${ARCHITECTURE}" == "arm" ]
then
  if lscpu | grep aarch64; then
     echo Validating 32-bit environment on 64-bit host - perhaps it is a docker container ...
     if ! file /bin/ls | grep "32-bit.*ARM"; then
       echo /bin/ls is not a 32-bit binary but ARCHITECTURE=arm. Non-32-bit userland is invalid without extra work
       exit 1
     fi
     echo Looks reasonable - configuring to allow building that way ...
     export CONFIGURE_ARGS_FOR_ANY_PLATFORM="${CONFIGURE_ARGS_FOR_ANY_PLATFORM} --target=armv7l-unknown-linux-gnueabihf --host=armv7l-unknown-linux-gnueabihf"
  fi
  # "4" is a temporary override which allows us to utilise all build
  # cores on our scaleway systems while they are still in use but still
  # allow more on larger machines. Can be revisited post-Scaleway
  if [ "$(lscpu|awk '/^CPU\(s\)/{print$2}')" = "4" ]; then
    export CONFIGURE_ARGS_FOR_ANY_PLATFORM="${CONFIGURE_ARGS_FOR_ANY_PLATFORM} --with-jobs=4 --with-memory-size=2000"
  fi
  if [ "$JAVA_FEATURE_VERSION" -eq 8 ]; then
    export CONFIGURE_ARGS_FOR_ANY_PLATFORM="${CONFIGURE_ARGS_FOR_ANY_PLATFORM} --with-extra-ldflags=-latomic"
  fi
  if [ "$JAVA_FEATURE_VERSION" -ge 11 ]; then
    export CONFIGURE_ARGS_FOR_ANY_PLATFORM="${CONFIGURE_ARGS_FOR_ANY_PLATFORM} --disable-warnings-as-errors"
  fi
  if [ -n "${NUM_PROCESSORS}" ]
  then
    export BUILD_ARGS="${BUILD_ARGS} --processors $NUM_PROCESSORS"
  fi
  echo "=== START OF ARM32 STATUS CHECK ==="
  uptime
  free
  ps -fu jenkins
  echo "=== END OF ARM32 STATUS CHECK ==="
fi

BOOT_JDK_VARIABLE="JDK${JDK_BOOT_VERSION}_BOOT_DIR"
if [ "${VARIANT}" == "${BUILD_VARIANT_DRAGONWELL}" ] && [ "$JAVA_FEATURE_VERSION" -eq 8 ]; then
  locateDragonwell8BootJDK
fi

if [ ! -d "$(eval echo "\$$BOOT_JDK_VARIABLE")" ]; then
  bootDir="$PWD/jdk$JDK_BOOT_VERSION"
  # Note we export $BOOT_JDK_VARIABLE (i.e. JDKXX_BOOT_DIR) here
  # instead of BOOT_JDK_VARIABLE (no '$').
  export "${BOOT_JDK_VARIABLE}"="$bootDir"
  if [ ! -x "$bootDir/bin/javac" ]; then
    # Set to a default location as linked in the ansible playbooks
    if [ -x "/usr/lib/jvm/jdk${JDK_BOOT_VERSION}/bin/javac" ]; then
      echo "Could not use ${BOOT_JDK_VARIABLE} - using /usr/lib/jvm/jdk${JDK_BOOT_VERSION}"
      # shellcheck disable=SC2140
      export "${BOOT_JDK_VARIABLE}"="/usr/lib/jvm/jdk${JDK_BOOT_VERSION}"
    elif [ "$JDK_BOOT_VERSION" -ge 8 ]; then # Adoptium has no build pre-8
      downloadLinuxBootJDK "${ARCHITECTURE}" "${JDK_BOOT_VERSION}" "$bootDir"
    fi
  fi
fi

# shellcheck disable=SC2155
export JDK_BOOT_DIR="$(eval echo "\$$BOOT_JDK_VARIABLE")"
"$JDK_BOOT_DIR/bin/java" -version 2>&1 | sed 's/^/BOOT JDK: /'
"$JDK_BOOT_DIR/bin/java" -version >/dev/null 2>&1
executedJavaVersion=$?
if [ $executedJavaVersion -ne 0 ]; then
    echo "Failed to obtain or find a valid boot jdk"
    exit 1
fi

if [[ "${CONFIGURE_ARGS}" =~ .*"--with-devkit=".* ]]; then
  echo "Using gcc from DevKit toolchain specified in configure args"
elif [[ "${BUILD_ARGS}" =~ .*"--use-adoptium-devkit".* ]]; then
  echo "Using gcc from Adoptium DevKit toolchain specified in --use-adoptium-devkit build args"
else
  if [ "${VARIANT}" == "${BUILD_VARIANT_DRAGONWELL}" ] && [ "$JAVA_FEATURE_VERSION" -eq 11 ] && [ -r /usr/local/gcc9/ ] && [ "${ARCHITECTURE}" == "aarch64" ]; then
    # GCC9 rather than 10 requested by Alibaba for now
    # Ref https://github.com/adoptium/temurin-build/issues/2250#issuecomment-732958466
    export PATH=/usr/local/gcc9/bin:$PATH
    export CC=/usr/local/gcc9/bin/gcc-9.3
    export CXX=/usr/local/gcc9/bin/g++-9.3
    # Enable GCC 10 for Java 17+ for repeatable builds, but not for our supported releases
    # Ref https://github.com/adoptium/temurin-build/issues/2787
  elif [ "${ARCHITECTURE}" == "riscv64" ] && [ -r /usr/bin/gcc-10 ]; then
    # Enable GCC 10 for RISC-V, given the rapid evolution of RISC-V, the newer the GCC toolchain, the better
    [ -r /usr/bin/gcc-10 ] && export  CC=/usr/bin/gcc-10
    [ -r /usr/bin/g++-10 ] && export CXX=/usr/bin/g++-10
  elif [ "$JAVA_FEATURE_VERSION" -ge 19 ] && [ -r /usr/local/gcc11/bin/gcc-11.2 ]; then
    export PATH=/usr/local/gcc11/bin:$PATH
    [ -r /usr/local/gcc11/bin/gcc-11.2 ] && export  CC=/usr/local/gcc11/bin/gcc-11.2
    [ -r /usr/local/gcc11/bin/g++-11.2 ] && export CXX=/usr/local/gcc11/bin/g++-11.2
    export LD_LIBRARY_PATH=/usr/local/gcc11/lib64:/usr/local/gcc11/lib
  elif [ "$JAVA_FEATURE_VERSION" -ge 17 ] && [ -r /usr/local/gcc10/bin/gcc-10.3 ]; then
    export PATH=/usr/local/gcc10/bin:$PATH
    [ -r /usr/local/gcc10/bin/gcc-10.3 ] && export  CC=/usr/local/gcc10/bin/gcc-10.3
    [ -r /usr/local/gcc10/bin/g++-10.3 ] && export CXX=/usr/local/gcc10/bin/g++-10.3
    export LD_LIBRARY_PATH=/usr/local/gcc10/lib64:/usr/local/gcc10/lib
  elif [ "$JAVA_FEATURE_VERSION" -gt 17 ] && [ -r /usr/bin/gcc-10 ]; then
    [ -r /usr/bin/gcc-10 ] && export  CC=/usr/bin/gcc-10
    [ -r /usr/bin/g++-10 ] && export CXX=/usr/bin/g++-10
  # Continue to use GCC 7 if present for JDK<=17 and where 10 does not exist
  elif [ -r /usr/local/gcc/bin/gcc-7.5 ]; then
    export PATH=/usr/local/gcc/bin:$PATH
    [ -r /usr/local/gcc/bin/gcc-7.5 ] && export  CC=/usr/local/gcc/bin/gcc-7.5
    [ -r /usr/local/gcc/bin/g++-7.5 ] && export CXX=/usr/local/gcc/bin/g++-7.5
    export LD_LIBRARY_PATH=/usr/local/gcc/lib64:/usr/local/gcc/lib
  elif [ -r /usr/bin/gcc-7 ]; then
    [ -r /usr/bin/gcc-7 ] && export  CC=/usr/bin/gcc-7
    [ -r /usr/bin/g++-7 ] && export CXX=/usr/bin/g++-7
  fi
fi

if [ "$JAVA_FEATURE_VERSION" -ge 20 ] && [ "${VARIANT}" == "${BUILD_VARIANT_TEMURIN}" ]; then
  # hsdis+capstone only supported on these two in openjdk
  if [ "${ARCHITECTURE}" = "x64" ] || [ "${ARCHITECTURE}" = "aarch64" ]; then
    if [ -r /usr/local/lib/libcapstone.so.4 ]; then
      export CONFIGURE_ARGS_FOR_ANY_PLATFORM="${CONFIGURE_ARGS_FOR_ANY_PLATFORM} --enable-hsdis-bundling --with-hsdis=capstone --with-capstone=/usr/local"
    fi
  fi
fi

if [ "${VARIANT}" == "${BUILD_VARIANT_BISHENG}" ]; then
  # BUILD_C/CXX required for native (non-cross) RISC-V builds of Bisheng
  if [ -n "$CXX" ]; then
    export BUILD_CC="$CC"
    export BUILD_CXX="$CXX"
  fi
  # Bisheng on aarch64 has a KAE option which requires openssl 1.1.1 to be used
  BISHENG_OPENSSL_111_LOCATION=${BISHENG_OPENSSL_111_LOCATION:-/usr/local/openssl-1.1.1}
  if [ -x "${BISHENG_OPENSSL_111_LOCATION}/lib/libcrypto.so.1.1" ]; then
    export CONFIGURE_ARGS_FOR_ANY_PLATFORM="${CONFIGURE_ARGS_FOR_ANY_PLATFORM} --with-extra-cflags=-I${BISHENG_OPENSSL_111_LOCATION}/include  --with-extra-cxxflags=-I${BISHENG_OPENSSL_111_LOCATION}/include --with-extra-ldflags=-L${BISHENG_OPENSSL_111_LOCATION}/lib"
  fi
fi

# Handle cross compilation environment for RISC-V
if [ "${ARCHITECTURE}" == "riscv64" ] && [ "${NATIVE_API_ARCH}" != "riscv64" ]; then
  setCrossCompilerEnvironment
fi
