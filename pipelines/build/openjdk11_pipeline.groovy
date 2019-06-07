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
                test                : ['openjdktest', 'systemtest', 'perftest']
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
                additionalNodeLabels: 'centos6',
                test                : [
                        nightly: ['openjdktest', 'systemtest', 'perftest', 'externaltest'],
                        release: ['openjdktest', 'systemtest', 'perftest', 'externaltest']
                ],
                configureArgs        : '--disable-ccache'
        ],

        // Currently we have to be quite specific about which windows to use as not all of them have freetype installed
        x64Windows: [
                os                  : 'windows',
                arch                : 'x64',
                additionalNodeLabels: [
                        hotspot: 'win2012',
                        openj9:  'win2012&&vs2017'
                ],
                buildArgs : [
                        hotspot : '--jvm-variant client,server'
                ],
                test                : ['openjdktest', 'perftest', 'systemtest']
        ],

        x64WindowsXL    : [
                os                   : 'windows',
                arch                 : 'x64',
                additionalNodeLabels : 'win2012&&vs2017',
                test                 : ['openjdktest', 'perftest', 'systemtest'],
                configureArgs        : '--with-noncompressedrefs'
        ],

        x32Windows: [
                os                  : 'windows',
                arch                : 'x86-32',
                additionalNodeLabels: [
                        hotspot: 'win2012',
                        openj9:  'win2012&&mingw-standalone'
                ],
                buildArgs : [
                        hotspot : '--jvm-variant client,server'
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
                test                : ['openjdktest', 'systemtest', 'perftest'],
                configureArgs        : '--disable-ccache'
        ],

        sparcv9Solaris    : [
                os                  : 'solaris',
                arch                : 'sparcv9',
                test                : false
        ],

        ppc64leLinux    : [
                os                  : 'linux',
                arch                : 'ppc64le',
                test                : ['openjdktest', 'systemtest', 'perftest'],
                configureArgs       : '--disable-ccache'

        ],

        arm32Linux    : [
                os                  : 'linux',
                arch                : 'arm',
                // TODO Temporarily remove the ARM tests because we don't have fast enough hardware
                //test                : ['openjdktest', 'perftest']
                test                : false
        ],

        aarch64Linux    : [
                os                  : 'linux',
                arch                : 'aarch64',
                additionalNodeLabels: 'centos7',
                test                : ['openjdktest', 'systemtest', 'perftest']
        ],

        /*
        "x86-32Windows"    : [
                os                 : 'windows',
                arch               : 'x86-32',
                additionalNodeLabels: 'win2012&&x86-32',
                test                : false
        ],
        */
        linuxXL    : [
                os                   : 'linux',
                additionalNodeLabels : 'centos6',
                arch                 : 'x64',
                test                 : ['openjdktest', 'systemtest'],
                additionalFileNameTag: "linuxXL",
                configureArgs        : '--with-noncompressedrefs --disable-ccache'
        ],
]

def javaToBuild = "jdk11u"

node ("master") {
    def scmVars = checkout scm
    load "${WORKSPACE}/pipelines/build/common/import_lib.groovy"
    Closure configureBuild = load "${WORKSPACE}/pipelines/build/common/build_base_file.groovy"

    configureBuild(
            javaToBuild,
            buildConfigurations,
            targetConfigurations,
            enableTests,
            releaseType,
            scmReference,
            overridePublishName,
            additionalConfigureArgs,
            scmVars,
            additionalBuildArgs,
            overrideFileNameVersion,
            cleanWorkspaceBeforeBuild,
            adoptBuildNumber,
            propagateFailures,
            currentBuild,
            this,
            env
    ).doBuild()
}
