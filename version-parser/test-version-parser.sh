#!/bin/bash

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

unset TEST

read -r -d '' java8 << EOM
openjdk version "1.8.0_202"
OpenJDK Runtime Environment (AdoptOpenJDK)(build 1.8.0_202-b08)
OpenJDK 64-Bit Server VM (AdoptOpenJDK)(build 25.202-b08, mixed mode)
EOM

export TEST=$java8
RESULT=$(python version-parser.py fake/path/java 1)
EXPECTED="8, 0, 202, 08, None, 8.0.202+08.1, 1.8.0_202-b08"
echo "testing if $RESULT == $EXPECTED"
if [ "$RESULT" != "$EXPECTED" ]; then exit 1; else echo ✅; fi

read -r -d '' java8j9 << EOM
openjdk version "1.8.0_202"
OpenJDK Runtime Environment (build 1.8.0_202-b08)
Eclipse OpenJ9 VM (build openj9-0.12.1, JRE 1.8.0 Mac OS X amd64-64-Bit Compressed References 20190205_147 (JIT enabled, AOT enabled)
OpenJ9   - 90dd8cb40
OMR      - d2f4534b
JCL      - d002501a90 based on jdk8u202-b08)
EOM

export TEST=$java8j9
RESULT=$(python version-parser.py fake/path/java 1)
EXPECTED="8, 0, 202, 08, None, 8.0.202+08.1, 1.8.0_202-b08"
echo "testing if $RESULT == $EXPECTED"
if [ "$RESULT" != "$EXPECTED" ]; then exit 1; else echo ✅; fi

read -r -d '' java8Nightly << EOM
openjdk version "1.8.0_181-internal"
OpenJDK Runtime Environment (AdoptOpenJDK)(build 1.8.0_181-internal-201903130451-b13)
OpenJDK 64-Bit Server VM (AdoptOpenJDK)(build 25.181-b13, mixed mode)
EOM

export TEST=$java8Nightly
RESULT=$(python version-parser.py fake/path/java 12)
EXPECTED="8, 0, 181, 13, 201903130451, 8.0.181+13.12, 1.8.0_181-internal-201903130451-b13"
echo "testing if $RESULT == $EXPECTED"
if [ "$RESULT" != "$EXPECTED" ]; then exit 1; else echo ✅; fi

read -r -d '' java11 << EOM
openjdk version "11.0.2" 2018-10-16
OpenJDK Runtime Environment AdoptOpenJDK (build 11.0.2+7)
OpenJDK 64-Bit Server VM AdoptOpenJDK (build 11.0.2+7, mixed mode)
EOM

export TEST=$java11
RESULT=$(python version-parser.py fake/path/java 3)
EXPECTED="11, 0, 2, 7, None, 11.0.2+7.3, 11.0.2+7"
echo "testing if $RESULT == $EXPECTED"
if [ "$RESULT" != "$EXPECTED" ]; then exit 1; else echo ✅; fi

read -r -d '' java11Nightly << EOM
openjdk version "11.0.3" 2019-04-16
OpenJDK Runtime Environment AdoptOpenJDK (build 11.0.3+9-201903122221)
OpenJDK 64-Bit Server VM AdoptOpenJDK (build 11.0.3+9-201903122221, mixed mode)
EOM

export TEST=$java11Nightly
RESULT=$(python version-parser.py fake/path/java 7)
EXPECTED="11, 0, 3, 9, 201903122221, 11.0.3+9.7, 11.0.3+9-201903122221"
echo "testing if $RESULT == $EXPECTED"
if [ "$RESULT" != "$EXPECTED" ]; then exit 1; else echo ✅; fi

read -r -d '' java11Nightlyj9 << EOM
openjdk version "11.0.3" 2019-04-16
OpenJDK Runtime Environment AdoptOpenJDK (build 11.0.3+2-201903171939)
Eclipse OpenJ9 VM AdoptOpenJDK (build master-f2782748f, JRE 11 Linux ppc64le-64-Bit Compressed References 20190317_164 (JIT enabled, AOT enabled)
OpenJ9   - f2782748f
OMR      - 9b73e2bd
JCL      - 3cd1a589af based on jdk-11.0.3+2)
EOM

export TEST=$java11Nightlyj9
RESULT=$(python version-parser.py fake/path/java 7)
EXPECTED="11, 0, 3, 2, 201903171939, 11.0.3+2.7, 11.0.3+2-201903171939"
echo "testing if $RESULT == $EXPECTED"
if [ "$RESULT" != "$EXPECTED" ]; then exit 1; else echo ✅; fi

read -r -d '' java12Nightly << EOM
openjdk version "12" 2019-03-19
OpenJDK Runtime Environment AdoptOpenJDK (build 12+33-201903171631)
OpenJDK 64-Bit Server VM AdoptOpenJDK (build 12+33-201903171631, mixed mode, sharing)
EOM

export TEST=$java12Nightly
RESULT=$(python version-parser.py fake/path/java 11)
EXPECTED="12, 0, 0, 33, 201903171631, 12.0.0+33.11, 12+33-201903171631"
echo "testing if $RESULT == $EXPECTED"
if [ "$RESULT" != "$EXPECTED" ]; then exit 1; else echo ✅; fi

unset TEST
