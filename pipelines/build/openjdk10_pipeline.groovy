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
                additionalNodeLabels: 'build-macstadium-macos1010-1',
                test                : ['sanity.openjdk', 'sanity.system'],
                configureArgs       : '--enable-dtrace=auto'
        ],
        x64Linux  : [
                os                  : 'linux',
                arch                : 'x64',
                additionalNodeLabels: 'centos6',
                test                : ['sanity.openjdk', 'sanity.system', 'sanity.external'],
                configureArgs       : '--enable-dtrace=auto'
        ],

        // Currently we have to be quite specific about which windows to use as not all of them have freetype installed
        x64Windows: [
                os                  : 'windows',
                arch                : 'x64',
                additionalNodeLabels: [
                        hotspot: 'win2012',
                        openj9:  'win2012&&mingw-cygwin'
                ],
                test                : ['sanity.openjdk']
        ],

        ppc64Aix    : [
                os                  : 'aix',
                arch                : 'ppc64',
                test                : false
        ],

        s390xLinux    : [
                os                  : 'linux',
                arch                : 's390x',
                additionalNodeLabels: [
                        hotspot: 'rhel7'
                ],
                test                : ['sanity.openjdk', 'sanity.system'],
                configureArgs       : '--enable-dtrace=auto'
        ],

        sparcv9Solaris    : [
                os                  : 'solaris',
                arch                : 'sparcv9',
                test                : false,
                configureArgs       : '--enable-dtrace=auto'
        ],

        ppc64leLinux    : [
                os                  : 'linux',
                arch                : 'ppc64le',
                test                : ['sanity.openjdk', 'sanity.system'],
                configureArgs       : '--enable-dtrace=auto'
        ],

        arm32Linux    : [
                os                  : 'linux',
                arch                : 'arm',
                test                : ['sanity.openjdk'],
                configureArgs       : '--enable-dtrace=auto'
        ],

        aarch64Linux    : [
                os                  : 'linux',
                arch                : 'aarch64',
                additionalNodeLabels: 'centos7',
                test                : ['sanity.openjdk'],
                configureArgs       : '--enable-dtrace=auto'
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
                test                 : false,
                additionalFileNameTag: "linuxXL",
                configureArgs        : '--with-noncompressedrefs --enable-dtrace=auto'
        ],
]

def javaToBuild = "jdk10u"

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
