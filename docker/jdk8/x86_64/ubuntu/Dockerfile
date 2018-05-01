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

FROM ubuntu:16.04

MAINTAINER Adopt OpenJDK <adoptopenjdk@gmail.com>

# Install required OS tools.  Yes we have to apt-get update first in order to
# get to software-properties-common, which includes the apt-add-repository
# package, so we can add the Azul repo and then apt-get update that so we cam
# get zulu-7.  This is why we can't have nice things.
RUN apt-get update \
  && apt-get install -y software-properties-common \
  && apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys 0x219BD9C9 \
  && apt-add-repository 'deb http://repos.azulsystems.com/ubuntu stable main' \
  && apt-get update \
  && apt-get -y upgrade \
  && apt-get install -qq -y --no-install-recommends \
    git \
    cpio \
    make \
    gcc \
    g++ \
    file \
    libx11-dev \
    libxext-dev \
    libxrender-dev \
    libxtst-dev \
    libxt-dev \
    libcups2-dev \
    libfreetype6-dev \
    libasound2-dev \
    zulu-7 \
    ccache \
    zip \
    wget \
    git \
    unzip \
&& rm -rf /var/lib/apt/lists/*

# Pick up build instructions
RUN mkdir -p /openjdk/target

ADD sbin /openjdk/sbin
ADD workspace/config /openjdk/config

WORKDIR /openjdk/build/

# Default actions
ENTRYPOINT ["/openjdk/sbin/build.sh"]

CMD ["images"]

ARG OPENJDK_CORE_VERSION
ENV OPENJDK_CORE_VERSION=$OPENJDK_CORE_VERSION
ENV JDK_PATH=j2sdk-image
ENV JRE_PATH=j2re-image
