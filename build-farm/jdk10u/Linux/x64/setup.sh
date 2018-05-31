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
# Setup for JDK 10 builds on AdoptOpenJDK build farm nodes
#
################################################################################

[ -r /opt/rh/devtoolset-2/root/usr/bin/gcc ] && export CC=/opt/rh/devtoolset-2/root/usr/bin/gcc
[ -r /opt/rh/devtoolset-2/root/usr/bin/g++ ] && export CXX=/opt/rh/devtoolset-2/root/usr/bin/g++
