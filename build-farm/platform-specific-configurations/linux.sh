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

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# shellcheck source=sbin/common/constants.sh
source "$SCRIPT_DIR/../../sbin/common/constants.sh"
# Bundling our own freetype can cause problems, so we skip that on linux.
export BUILD_ARGS="${BUILD_ARGS} --skip-freetype"

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
    mkdir -p "$PWD/jdk-8"
    if [ "$(uname -m)" = "x86_64" ]; then
      curl -L "https://github.com/alibaba/dragonwell8/releases/download/dragonwell-8.11.12_jdk8u332-ga/Alibaba_Dragonwell_8.11.12_x64_linux.tar.gz" | tar xpzf - --strip-components=1 -C "$PWD/jdk-8"
    elif [ "$(uname -m)" = "aarch64" ]; then
      curl -L "https://github.com/alibaba/dragonwell8/releases/download/dragonwell-8.8.9_jdk8u302-ga/Alibaba_Dragonwell_8.8.9_aarch64_linux.tar.gz" | tar xpzf - --strip-components=1 -C "$PWD/jdk-8"
    else
      echo "Unknown architecture $(uname -m) for building Dragonwell - cannot download boot JDK"
      exit 1
    fi
    export "${BOOT_JDK_VARIABLE}"="$PWD/jdk-8"
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

function downloadBootJDK()
{
  ARCH=$1
  VER=$2
  export GNUPGHOME=$PWD/.gnupg-temp
  if [ ! -d "$GNUPGHOME" ]; then
    mkdir -m 700 "$GNUPGHOME"
  fi
  export downloadArch
  case "$ARCH" in
     "riscv64") downloadArch="$NATIVE_API_ARCH";;
             *) downloadArch="$ARCH";;
  esac
  releaseType="ga"
  vendor="eclipse"
  apiUrlTemplate="https://api.adoptium.net/v3/binary/latest/\${VER}/\${releaseType}/linux/\${downloadArch}/jdk/hotspot/normal/\${vendor}"
  apiURL=$(eval echo "${apiUrlTemplate}")
  echo "Downloading GA release of boot JDK version ${VER} from ${apiURL}"
  # make-adopt-build-farm.sh has 'set -e'. We need to disable that for
  # the fallback mechanism, as downloading of the GA binary might fail.
  set +e
  curl -L -o bootjdk.tar.gz "${apiURL}"
  apiSigURL=$(curl -v "${apiURL}" 2>&1 | tr -d \\r | awk '/^< Location:/{print $3 ".sig"}')
  if ! grep "No releases match the request" bootjdk.tar.gz; then
    curl -L -o bootjdk.tar.gz.sig "${apiSigURL}"
    gpg --keyserver keyserver.ubuntu.com --recv-keys 3B04D753C9050D9A5D343F39843C48A565F8F04B
    echo -e "5\ny\n" |  gpg --batch --command-fd 0 --expert --edit-key 3B04D753C9050D9A5D343F39843C48A565F8F04B trust;
    gpg --verify bootjdk.tar.gz.sig bootjdk.tar.gz || exit 1
    mkdir "$bootDir"
    tar xpzf bootjdk.tar.gz --strip-components=1 -C "$bootDir"
    set -e
  else
    # We must be a JDK HEAD build for which no boot JDK exists other than
    # nightlies?
    echo "Downloading GA release of boot JDK version ${VER} failed."
    # shellcheck disable=SC2034
    releaseType="ea"
    # shellcheck disable=SC2034
    vendor="adoptium"
    apiURL=$(eval echo ${apiUrlTemplate})
    echo "Attempting to download EA release of boot JDK version ${VER} from ${apiURL}"
    set +e
    curl -L -o bootjdk.tar.gz "${apiURL}"
    if ! grep "No releases match the request" bootjdk.tar.gz; then
      apiSigURL=$(curl -v "${apiURL}" 2>&1 | tr -d \\r | awk '/^< Location:/{print $3 ".sig"}')
      curl -L -o bootjdk.tar.gz.sig "${apiSigURL}"
      gpg --keyserver keyserver.ubuntu.com --recv-keys 3B04D753C9050D9A5D343F39843C48A565F8F04B
      echo -e "5\ny\n" |  gpg --batch --command-fd 0 --expert --edit-key 3B04D753C9050D9A5D343F39843C48A565F8F04B trust;
      gpg --verify bootjdk.tar.gz.sig bootjdk.tar.gz || exit 1
      mkdir "$bootDir"
      tar xpzf bootjdk.tar.gz --strip-components=1 -C "$bootDir"
    else
      # If no binaries are available then try from adoptopenjdk
      echo "Downloading Temurin release of boot JDK version ${VER} failed."
      # shellcheck disable=SC2034
      releaseType="ga"
      # shellcheck disable=SC2034
      vendor="adoptium"
      apiURL=$(eval echo ${apiUrlTemplate})
      echo "Attempting to download GA release of boot JDK version ${VER} from ${apiURL}"
      curl -L "${apiURL}" | tar xpzf - --strip-components=1 -C "$bootDir"
    fi
  fi
}

if [ "${ARCHITECTURE}" == "x64" ]
then
  export PATH=/opt/rh/devtoolset-2/root/usr/bin:$PATH
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
    CUDA_VERSION=9.0
    CUDA_HOME=/usr/local/cuda-$CUDA_VERSION
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
  bootDir="$PWD/jdk-$JDK_BOOT_VERSION"
  # Note we export $BOOT_JDK_VARIABLE (i.e. JDKXX_BOOT_DIR) here
  # instead of BOOT_JDK_VARIABLE (no '$').
  export "${BOOT_JDK_VARIABLE}"="$bootDir"
  if [ ! -x "$bootDir/bin/javac" ]; then
    # Set to a default location as linked in the ansible playbooks
    if [ -x "/usr/lib/jvm/jdk-${JDK_BOOT_VERSION}/bin/javac" ]; then
      echo "Could not use ${BOOT_JDK_VARIABLE} - using /usr/lib/jvm/jdk-${JDK_BOOT_VERSION}"
      # shellcheck disable=SC2140
      export "${BOOT_JDK_VARIABLE}"="/usr/lib/jvm/jdk-${JDK_BOOT_VERSION}"
    elif [ "$JDK_BOOT_VERSION" -ge 8 ]; then # Adoptium has no build pre-8
      downloadBootJDK "${ARCHITECTURE}" "${JDK_BOOT_VERSION}"
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

if [ "${VARIANT}" == "${BUILD_VARIANT_DRAGONWELL}" ] && [ "$JAVA_FEATURE_VERSION" -eq 11 ] && [ -r /usr/local/gcc9/ ] && [ "${ARCHITECTURE}" == "aarch64" ]; then
  # GCC9 rather than 10 requested by Alibaba for now
  # Ref https://github.com/adoptium/temurin-build/issues/2250#issuecomment-732958466
  export PATH=/usr/local/gcc9/bin:$PATH
  export CC=/usr/local/gcc9/bin/gcc-9.3
  export CXX=/usr/local/gcc9/bin/g++-9.3
  # Enable GCC 10 for Java 17+ for repeatable builds, but not for our supported releases
  # Ref https://github.com/adoptium/temurin-build/issues/2787
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

if [ "$JAVA_FEATURE_VERSION" -ge 20 ]; then
  if [ -r /usr/local/lib/libcapstone.so.4 ]; then
    export CONFIGURE_ARGS_FOR_ANY_PLATFORM="${CONFIGURE_ARGS_FOR_ANY_PLATFORM} --with-capstone=/usr/local"
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
