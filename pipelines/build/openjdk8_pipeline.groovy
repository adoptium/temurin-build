/*
Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

     https://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

def buildConfigurations = [
        x64Mac    : [
                os                  : 'mac',
                arch                : 'x64',
                additionalNodeLabels: [
                        hotspot: 'build-macstadium-macos1010-1',
                        openj9:  'build-macstadium-macos1010-2'
                ],
                test                : ['openjdktest', 'systemtest']
        ],

        x64MacXL    : [
                os                   : 'mac',
                arch                 : 'x64',
                additionalNodeLabels : 'build-macstadium-macos1010-2',
                test                 : ['openjdktest', 'systemtest', 'perftest'],
                additionalFileNameTag: "macosXL",
                configureArgs        : '--with-noncompressedrefs'
        ],

        x64Linux  : [
                os                  : 'linux',
                arch                : 'x64',
                additionalNodeLabels: [
                        hotspot: 'centos6',
                        openj9:  'build-joyent-centos69-x64-1'
                ],
                test                : ['openjdktest', 'systemtest', 'perftest', 'externaltest', 'externaltest_extended']
        ],

        // Currently we have to be quite specific about which windows to use as not all of them have freetype installed
        x64Windows: [
                os                  : 'windows',
                arch                : 'x64',
                additionalNodeLabels: [
                        hotspot: 'win2008',
                        openj9:  'win2012&&mingw-cygwin'
                ],
                buildArgs: [
                        openj9:  '--skip-freetype'
                ],
                test                : ['openjdktest']
        ],

        x32Windows: [
                os                  : 'windows',
                arch                : 'x86-32',
                additionalNodeLabels: [
                        hotspot: 'win2008',
                        openj9:  'win2012&&mingw-cygwin'
                ],
                buildArgs: [
                        openj9:  '--skip-freetype'
                ],
                test                : ['openjdktest']
        ],

        ppc64Aix    : [
                os                  : 'aix',
                arch                : 'ppc64',
                test                : [
                        nightly: false,
                        release: ['openjdktest', 'systemtest']
                ]
        ],

        s390xLinux    : [
                os                  : 'linux',
                arch                : 's390x',
                test                : ['openjdktest', 'systemtest']
        ],

        ppc64leLinux    : [
                os                  : 'linux',
                arch                : 'ppc64le',
                test                : ['openjdktest', 'systemtest']
        ],

        arm32Linux    : [
                os                  : 'linux',
                arch                : 'arm',
                test                : ['openjdktest']
        ],

        aarch64Linux    : [
                os                  : 'linux',
                arch                : 'aarch64',
                additionalNodeLabels: 'centos7',
                test                : ['openjdktest', 'systemtest']
        ],

        linuxXL    : [
                os                   : 'linux',
                additionalNodeLabels : 'centos6',
                arch                 : 'x64',
                additionalFileNameTag: "linuxXL",
                test                 : ['openjdktest', 'systemtest'],
                configureArgs        : '--with-noncompressedrefs'
        ],
]

def javaToBuild = "jdk8u"

node ("master") {
    def scmVars = checkout scm
    def buildFile = load "${WORKSPACE}/pipelines/build/build_base_file.groovy"
    buildFile.doBuild(
            javaToBuild,
            buildConfigurations,
            targetConfigurations,
            enableTests,
            publish,
            releaseTag,
            branch,
            additionalConfigureArgs,
            scmVars,
            additionalBuildArgs,
            additionalFileNameTag,
            cleanWorkspaceBeforeBuild)
}

