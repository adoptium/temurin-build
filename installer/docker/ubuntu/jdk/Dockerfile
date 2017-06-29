# (C) Copyright IBM Corporation 2017.
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

# Dockerfile to create an image with AdoptOpenJDK jdk binary installed
# Note that the installation process removes demos manual and samples directories
# Build info is emitted to stderr
#
# Build example:  docker build --build-arg RELEASE=jdk8u162-b00 -t adoptopenjdk:jdk8u162 .
#

FROM ubuntu:16.10

MAINTAINER Steve Poole <spoole167@googlemail.com>

# default release / architecture to install (override with --build-arg RELEASE=?  option etc)

ARG RELEASE=latest
ARG ARCH=x64_linux

# envs
ENV JAVA_LOC=/opt/java/openjdk-$RELEASE
ENV API_URL=https://api.adoptopenjdk.net/releases/$ARCH/$RELEASE/binary

RUN ( >&2 echo "RELEASE=$RELEASE" ) && \
    ( >&2 echo "ARCH   =$ARCH"    ) && \
    ( >&2 echo "API URL=$API_URL" )

RUN apt-get update && apt-get install -y --no-install-recommends \
  	bash curl ca-certificates \
 	  && rm -rf /var/lib/apt/lists/*


RUN curl -LJ -s -o java.tar.gz  -H 'accept-version: 1.1.0' $API_URL \
    && mkdir -p /opt/java \
    && cd /opt/java && gunzip -c /java.tar.gz | tar xf - \
  	&& mv /opt/java/j2sdk-image $JAVA_LOC \
    && rm -rf $JAVA_LOC/demo  $JAVA_LOC/man  $JAVA_LOC/sample  \
		&& rm /java.tar.gz

ENV JAVA_HOME=$JAVA_LOC/jre \
    PATH=$JAVA_LOC/bin:$PATH

RUN (>&2 echo "JAVA INSTALL DIR=`which java`")
RUN (>&2 java -version)
