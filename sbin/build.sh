#!/bin/bash
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

# Script to download any additional packages for building OpenJDK
# before calling ./configure (using JDK 7 as the base)

WORKING_DIR=$1
TARGET_DIR=$2
OPENJDK_REPO_NAME=$3
BUILD_FULL_NAME=$4
JVM_VARIANT=${5:=normal}

# Escape code
esc=$(echo -en "\033")

# Set colors
error="${esc}[0;31m"
good="${esc}[0;32m"
info="${esc}[0;33m"
git="${esc}[0;34m"
normal=$(echo -en "${esc}[m\017")


# If on docker

if [[ -f /.dockerenv ]] ; then
  echo "Detected we're in docker"
  WORKING_DIR=/openjdk/jdk8u
  TARGET_DIR=$WORKING_DIR
fi

# E.g. /openjdk/jdk8u if you're building in a Docker container
# otherwise ensure it's a writable area e.g. /home/youruser/myopenjdkarea

if [ -z "$WORKING_DIR" ] || [ -z "$TARGET_DIR" ] ; then
    echo "build.sh is called by makejdk.sh and requires two parameters"
    echo "Are you sure you want to call it directly?"
    echo "Usage: bash ./build.sh <workingarea> <targetforjdk>"
    echo "Note that you must have the OpenJDK source before using this script!"
    echo "This script will try to move ./openjdk to the source directory for you, "
    echo "and this will be your working area where all required files will be downloaded to."
    echo "You can override the JDK boot directory by setting the environment variable JDK_BOOT_DIR"
    exit;
fi

echo "Making the working directory to store source files and extensions: $WORKING_DIR"

mkdir -p $WORKING_DIR

cd $WORKING_DIR

############################################

echo "Downloading required dependencies..."

# ALSA first for sound

echo "Checking for ALSA"

FOUND_ALSA=$(find "$WORKING_DIR" -name "alsa-lib-1.0.27.2")

if [[ ! -z $FOUND_ALSA ]] ; then
  echo "Skipping ALSA download"
else
  wget -nc ftp://ftp.alsa-project.org/pub/lib/alsa-lib-1.0.27.2.tar.bz2
  tar xvf alsa-lib-1.0.27.2.tar.bz2
  rm alsa-lib-1.0.27.2.tar.bz2
fi

echo "Checking for freetype"

FOUND_FREETYPE=$(find "$WORKING_DIR/$OPENJDK_REPO_NAME/installedfreetype/lib" -name "libfreetype.so.6.5.0")

if [[ ! -z $FOUND_FREETYPE ]] ; then
  echo "Skipping FreeType download"
else
  # Then FreeType for fonts: make it and use
  wget -nc http://ftp.acc.umu.se/mirror/gnu.org/savannah/freetype/freetype-2.4.0.tar.gz
   
  tar xvf freetype-2.4.0.tar.gz
  rm freetype-2.4.0.tar.gz

  cd freetype-2.4.0

  if [ $(uname -m) = "ppc64le" ]; then
    PARAMS="--build=$(rpm --eval %{_host})"
  fi
   
  # We get the files we need at $WORKING_DIR/installedfreetype
  bash ./configure --prefix=$WORKING_DIR/$OPENJDK_REPO_NAME/installedfreetype $PARAMS && make all && make install

  if [ $? -ne 0 ]; then
    echo "${error}Failed to configure and build libfreetype, exiting"
    exit;
  else
    echo "${good}Built the JDK!"
  fi
  echo $normal
fi

###########################################

cd $WORKING_DIR

echo "Retrieving cacerts file"

# Ensure it's the latest we pull in
rm -rf $WORKING_DIR/cacerts_area

git clone https://github.com/AdoptOpenJDK/openjdk-build.git cacerts_area
echo "cacerts should be here..."
file $WORKING_DIR/cacerts_area/security/cacerts

if [ $? -ne 0 ]; then
  echo "Failed to retrieve the cacerts file, exiting..."
  exit;
fi

###########################################

echo "Building up the configure command..."

if [ -z "$JDK_BOOT_DIR" ] ; then
  echo "JDK_BOOT_DIR is $JDK_BOOT_DIR"
  JDK_BOOT_DIR=/usr/lib/java-1.7.0
else
  echo "Overriding JDK_BOOT_DIR, set to $JDK_BOOT_DIR"
fi

echo "Boot dir set to $JDK_BOOT_DIR"

CONFIGURE_CMD=" --with-boot-jdk=$JDK_BOOT_DIR"

if [ ! -z $(which ccache) ]; then
  CONFIGURE_CMD="$CONFIGURE_CMD --enable-ccache"
fi

CONFIGURE_CMD="$CONFIGURE_CMD --with-jvm-variants=$JVM_VARIANT"
CONFIGURE_CMD="$CONFIGURE_CMD --with-cacerts-file=$WORKING_DIR/cacerts_area/security/cacerts"
CONFIGURE_CMD="$CONFIGURE_CMD --with-alsa=$WORKING_DIR/alsa-lib-1.0.27.2"
CONFIGURE_CMD="$CONFIGURE_CMD --with-freetype=$WORKING_DIR/$OPENJDK_REPO_NAME/installedfreetype"

# These will have been installed by the package manager (see our Dockerfile)
CONFIGURE_CMD="$CONFIGURE_CMD --with-x=/usr/include/X11"

# We don't want any extra debug symbols - ensure it's set to release,
# other options include fastdebug and slowdebug
CONFIGURE_CMD="$CONFIGURE_CMD --with-debug-level=release"

#CONFIGURE_CMD="$CONFIGURE_CMD --with-adds-and-overrides=$WORKING_DIR/$OPENJDK_REPO_NAME/addsandoverrides"

###########################################

# Make sure we're in the source directory for OpenJDK now

cd $WORKING_DIR/$OPENJDK_REPO_NAME

echo "Should have the source, I'm at $PWD"

CONFIGURED_JDK_ALREADY=$(find -name "config.status")

if [[ ! -z $CONFIGURED_JDK_ALREADY ]] ; then
  echo "Not reconfiguring due to the presence of config.status in $WORKING_DIR"
else
  echo "Running ./configure with $CONFIGURE_CMD"
  bash ./configure $CONFIGURE_CMD
  if [ $? -ne 0 ]; then
    echo ${fail}
    echo "Failed to configure the JDK, exiting"
    echo "Did you set the JDK boot directory correctly? Override by exporting JDK_BOOT_DIR"
    echo "For example, on RHEL you would do export JDK_BOOT_DIR=/usr/lib/jvm/java-1.7.0-openjdk-1.7.0.131-2.6.9.0.el7_3.x86_64"
    echo "Current JDK_BOOT_DIR value: $JDK_BOOT_DIR"
    exit;
  else
    echo "${good}Configured the JDK"
  fi
  echo ${normal}
fi

###########################################

if [ $(uname -m) == "s390x" ]; then
  makeCMD="make CONF=$BUILD_FULL_NAME DEBUG_BINARIES=true images"
else
  makeCMD="make images"
fi

echo "Building the JDK: calling $makeCMD"
$makeCMD

if [ $? -ne 0 ]; then
   echo "${fail}Failed to make the JDK, exiting"
  exit;
else
  echo "${good}Built the JDK!"
fi
echo ${normal}

###########################################

echo "Removing unneccessary files now..."

rm -rf cacerts_area

cd build/*/images

# Remove files we don't need
rm -rf j2sdk-image/demo/applets
rm -rf j2sdk-image/demo/jfc/Font2DTest
rm -rf j2sdk-image/demo/jfc/SwingApplet
find . -name "*.diz" -type f -delete

GZIP=-9 tar -cvzf OpenJDK.tar.gz ./j2sdk-image

mv OpenJDK.tar.gz $TARGET_DIR

echo "${good}Your final tar.gz is here at $PWD${normal}"
cd $TARGET_DIR
ls
echo "All done!"
