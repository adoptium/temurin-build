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
                test                : [
                        nightly: false,
                        release: ['sanity.openjdk', 'sanity.system', 'extended.system', 'sanity.perf']
                ]
        ],

        x64MacXL    : [
                os                   : 'mac',
                arch                 : 'x64',
                additionalNodeLabels : 'build-macstadium-macos1010-2',
                test                : [
                        nightly: false,
                        release: ['sanity.openjdk', 'sanity.system', 'extended.system']
                ],
                additionalFileNameTag: "macosXL",
                configureArgs        : '--with-noncompressedrefs'
        ],

        x64Linux  : [
                os                  : 'linux',
                arch                : 'x64',
                additionalNodeLabels: 'centos6',
                test                : [
                        nightly: false,
                        release: ['sanity.openjdk', 'sanity.system', 'extended.system', 'sanity.perf', 'sanity.external', 'special.functional']
                ],
                configureArgs       : [
                        "openj9"      : '--disable-ccache --enable-jitserver',
                        "hotspot"     : '--disable-ccache',
                        "hotspot-jfr" : '--disable-ccache',
                        "corretto"    : '--disable-ccache',
                        "SapMachine"  : '--disable-ccache'
                ]
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
                test                : [
                        nightly: false,
                        release: ['sanity.openjdk', 'sanity.perf', 'sanity.system', 'extended.system']
                ]
        ],

        x64WindowsXL    : [
                os                   : 'windows',
                arch                 : 'x64',
                additionalNodeLabels : 'win2012&&vs2017',
                test                : [
                        nightly: false,
                        release: ['sanity.openjdk', 'sanity.system']
                ],
                additionalFileNameTag: "windowsXL",
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
                test                : [
                        nightly: false,
                        release: ['sanity.openjdk']
                ]
        ],

        ppc64Aix    : [
                os                  : 'aix',
                arch                : 'ppc64',
                additionalNodeLabels: 'xlc13',
                test                : [
                        nightly: false,
                        release: ['sanity.openjdk', 'sanity.system', 'extended.system']
                ]
        ],

        s390xLinux    : [
                os                  : 'linux',
                arch                : 's390x',
                test                : [
                        nightly: false,
                        release: ['sanity.openjdk', 'sanity.system', 'extended.system', 'sanity.perf']
                ],
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
                test                : [
                        nightly: false,
                        release: ['sanity.openjdk', 'sanity.system', 'extended.system', 'sanity.perf']
                ],
                configureArgs       : '--disable-ccache'

        ],

        arm32Linux    : [
                os                  : 'linux',
                arch                : 'arm',
                // TODO Temporarily remove the ARM tests because we don't have fast enough hardware
                //test                : ['sanity.openjdk', 'sanity.perf']
                test                : false
        ],

        aarch64Linux    : [
                os                  : 'linux',
                arch                : 'aarch64',
                additionalNodeLabels: 'centos7',
                test                : [
                        nightly: false,
                        release: ['sanity.openjdk', 'sanity.system', 'extended.system', 'sanity.perf']
                ]
        ],

        /*
        "x86-32Windows"    : [
                os                 : 'windows',
                arch               : 'x86-32',
                additionalNodeLabels: 'win2012&&x86-32',
                test                : false
        ],
        */
        x64LinuxXL    : [
                os                   : 'linux',
                additionalNodeLabels : 'centos6',
                arch                 : 'x64',
                test                : [
                        nightly: false,
                        release: ['sanity.openjdk', 'sanity.system', 'extended.system']
                ],
                additionalFileNameTag: "linuxXL",
                configureArgs        : '--with-noncompressedrefs --disable-ccache --enable-jitserver'
        ],
        s390xLinuxXL    : [
                os                   : 'linux',
                arch                 : 's390x',
                test                : [
                        nightly: false,
                        release: ['sanity.openjdk', 'sanity.system', 'extended.system']
                ],
                additionalFileNameTag: "linuxXL",
                configureArgs        : '--with-noncompressedrefs --disable-ccache'
        ],
        ppc64leLinuxXL    : [
                os                   : 'linux',
                arch                 : 'ppc64le',
                test                : [
                        nightly: false,
                        release: ['sanity.openjdk', 'sanity.system', 'extended.system']
                ],
                additionalFileNameTag: "linuxXL",
                configureArgs        : '--with-noncompressedrefs --disable-ccache'
        ],
        aarch64LinuxXL    : [
                os                   : 'linux',
                additionalNodeLabels : 'centos7',
                arch                 : 'aarch64',
                test                : [
                        nightly: false,
                        release: ['sanity.openjdk', 'sanity.system', 'extended.system']
                ],
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
