#!/bin/bash
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

set -e

# This script demonstrates how to build an identical Windows Temurin binary without directly using temurin-build scripts
# for the purpose of trusted reproducible build validation.

TSTAMP=$1
BOOTJDK_HOME=$2
VCTOOLS=$3
TAG=$4

if [ -z "$TAG" ]; then
    echo "Syntax: windows_build_as_temurin.sh <ISO8601_timestamp> <BootJDK_Home> <VC Tools directory> <Tag being built>"
    echo "  eg: windows_build_as_temurin.sh 2023-03-20T09:06:00Z /cygdrive/c/workspace/jdk-19.0.2+7 /cygdrive/d/VS2019/VC/Tools jdk-20+36"
    exit 1
fi

echo "Checking out tag $TAG..."
if ! git checkout "$TAG"; then
  echo "Failed to checkout tag $TAG"
  exit 1
fi

TSTAMP_ID=${TSTAMP:0:4}${TSTAMP:5:2}${TSTAMP:8:2}${TSTAMP:11:2}${TSTAMP:14:2}
VER_FULL=$(echo "$TAG" | cut -d'-' -f2)
BLD=$(echo "$VER_FULL" | cut -d'+' -f2)

echo "Performing configure as Temurin..."
configStr="bash ./configure --verbose  --with-vendor-name=\"Eclipse Adoptium\" --with-vendor-url=https://adoptium.net/ --with-vendor-bug-url=https://github.com/adoptium/adoptium-support/issues --with-vendor-vm-bug-url=https://github.com/adoptium/adoptium-support/issues --with-version-opt=${TSTAMP_ID} --with-version-pre=beta --with-version-build=${BLD} --with-vendor-version-string=Temurin-${VER_FULL}-${TSTAMP_ID} --with-boot-jdk=${BOOTJDK_HOME} --with-debug-level=release --with-native-debug-symbols=external --with-source-date=${TSTAMP} --with-hotspot-build-time=${TSTAMP} --with-build-user=temurin --with-jvm-variants=server --disable-warnings-as-errors --disable-ccache --with-toolchain-version=2019 --with-tools-dir=${VCTOOLS}  --with-freetype=bundled"
echo "${configStr}"
eval "${configStr}"

echo "Building as Temurin..."
make product-images legacy-jre-image test-image static-libs-image

