#!/usr/bin/python

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

import sys
import commands
import os

major = None
minor = None
security = None
build = None
opt = None
semver = None

if "TEST" in os.environ:
    output = os.environ['TEST']
    build_num = sys.argv[2]
else:
    java_cmd = sys.argv[1]
    build_num = sys.argv[2]
    status, output = commands.getstatusoutput(java_cmd + ' -version')

# version_string should look like OpenJDK Runtime Environment AdoptOpenJDK (build 11.0.2+7)
version_string = output.split('\n', 1)[1]

# returns a string like 1.8.0_202-b08 or 11.0.2+7
version = version_string.split('build ')[1].split(')')[0]

split_version = version.split('.')

try:
    isinstance(int(split_version[0]), (int, long))
except ValueError:
    split_version = version.split('+')

if int(split_version[0]) > 1:
    # detected openjdk 9 or above
    major = int(split_version[0]) # 11
    try:
        minor = int(split_version[1]) # 0
        security = int(split_version[2].split('+')[0]) # 2
        build = int(split_version[2].split('+')[1].split('-')[0]) # 9
        # test if a timestamp is defined
        try:
            opt = split_version[2].split('+')[1].split('-')[1]
        except IndexError:
            opt = None
    except ValueError:
        minor = 0
        security = 0
        build = int(split_version[1].split('-')[0]) # 9
        # test if a timestamp is defined
        try:
            opt = split_version[1].split('-')[1]
        except IndexError:
            opt = None
else:
    # detected openjdk 8
    major = int(split_version[1]) # 8
    minor = int(split_version[2].split('_')[0]) # 0
    security = int(split_version[2].split('_')[1].split('-')[0]) # 202
    # not int to prevent trimming of leading zeros
    build = split_version[2].split('-b')[1] # 08
    # test if a timestamp is defined
    try:
        opt = split_version[2].split('internal-')[1].split('-')[0]
    except IndexError:
        opt = None

semver = str(major) + '.' + str(minor) + '.' + str(security) + '+' + str(build) + '.' + build_num # 8.0.202+08.1

print str(major) + ", " + str(minor) + ", " + str(security) + ", " + str(build) + ", " + str(opt) + ", " + str(semver)
