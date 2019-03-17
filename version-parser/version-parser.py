#!/usr/bin/python

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
    java = sys.argv[1]
    build_num = sys.argv[2]
    status, output = commands.getstatusoutput(java + ' -version')

# version_string should look like OpenJDK Runtime Environment AdoptOpenJDK (build 11.0.2+7)
version_string = output.split('\n', 1)[1]

# returns a string like 1.8.0_202-b08 or 11.0.2+7
version = version_string.split('build ')[1].split(')')[0]

split_version = version.split('.')

if int(split_version[0]) > 1:
    # detected openjdk 9 or above
    major = int(split_version[0]) # 11
    minor = int(split_version[1]) # 0
    security = int(split_version[2].split('+')[0]) # 2
    build = int(split_version[2].split('+')[1].split('-')[0]) # 9
    # test if a timestamp is defined
    try:
        opt = split_version[2].split('+')[1].split('-')[1]
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
