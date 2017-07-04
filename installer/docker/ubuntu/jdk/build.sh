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

# Script to create a Docker image using Ubuntu and latest AdoptOpenJDK  linux binary
# This script works in conjunction with jenkins plugins
# The script assumes that Jenkins has placesd the tar.gz of the binary
# in the root of the workspace. (WORKSPACE envar is set by jenkins)
#
# REPO defines the target docker repository for tagging images with
# ARCH defines the computer architecture tag to be used for docker image tags
# that are machine specific.
# 
# This script builds the docker image but does not push to docker hub.
# The docker plugin could build the image but is not dynamically configurable
# so is only used to push the created image.
#

: ${WORKSPACE:=$PWD}
: ${REPO:=adoptopenjdk/openjdk8}
: ${ARCH:=x86_64}

# remove any locally built images before building

images=`docker images | grep "^$REPO"  | awk '{print $3}' | uniq`

for i in $images
do
   docker rmi -f $i
done

# create place to hold image to be dockerized
rm -rf docker_image
mkdir -p docker_image

# add contents to image
cp Dockerfile docker_image
cd docker_image
mv $WORKSPACE/OpenJDK8*.tar.gz .
gunzip -c OpenJDK8*.tar.gz | tar xf -

# java release determined from directory name of unzipped image
RELEASE=`find . -mindepth 1 -maxdepth 1 -type d  \( ! -iname ".*" \) | sed 's|^\./||g'`

# remove unwanted files and directories
rm -rf $RELEASE/demo  $RELEASE/man  $RELEASE/sample

# create docker image locally
# build arg RELEASE is required
docker build --no-cache=true --build-arg RELEASE=$RELEASE -t $REPO:$RELEASE -t $REPO:latest -t $REPO:$ARCH-$RELEASE  -t $REPO:$ARCH-latest .
