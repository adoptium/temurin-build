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

MAINTAINER George Adams <george.adams@uk.ibm.com>

# Install required OS tools
RUN apt-get update \
  && apt-get install -qq -y --no-install-recommends \
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
    libelf-dev \
    libcups2-dev \
    libfreetype6-dev \
    libasound2-dev \
    openjdk-8-jdk \
    ccache \
    zip \
    wget \
    git \
    unzip \
    realpath \
&& rm -rf /var/lib/apt/lists/*

# Pick up build instructions
RUN mkdir -p /openjdk/target

ADD sbin /openjdk/sbin

WORKDIR /openjdk/build/

ENV JDK_BOOT_DIR=/usr/lib/jvm/java-1.8.0-openjdk-amd64

# Default actions
ENTRYPOINT ["/openjdk/sbin/build.sh"]

CMD ["images"]
