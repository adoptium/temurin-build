#!/bin/bash

################################################################################
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
################################################################################

################################################################################
#
# Setup for JDK 8 builds on AdoptOpenJDK build farm nodes
#
################################################################################

export PATH=/opt/rh/devtoolset-2/root/usr/bin:$PATH
if [ -r /opt/rh/devtoolset-2/root/usr/bin/g++-NO ]; then
  export CC=/opt/rh/devtoolset-2/root/usr/bin/gcc
  export CXX=/opt/rh/devtoolset-2/root/usr/bin/g++
  ls -l $CC $CXX
  $CC --version
  $CXX --version
fi