class Config15 {
  final Map<String, Map<String, ?>> buildConfigurations = [
        x64Mac    : [
                os                  : 'mac',
                arch                : 'x64',
                additionalNodeLabels: 'macos10.14',
                test                : ['sanity.openjdk', 'sanity.system', 'extended.system', 'sanity.perf'],
                configureArgs       : '--enable-dtrace'
        ],

        x64MacXL    : [
                os                   : 'mac',
                arch                 : 'x64',
                additionalNodeLabels : 'macos10.14',
                test                 : ['sanity.openjdk', 'sanity.system', 'extended.system', 'sanity.perf'],
                additionalFileNameTag: "macosXL",
                configureArgs        : '--with-noncompressedrefs --enable-dtrace'
        ],

        x64Linux  : [
                os                  : 'linux',
                arch                : 'x64',
                dockerImage         : 'adoptopenjdk/centos7_build_image',
                dockerFile: [
                        openj9  : 'pipelines/build/dockerFiles/cuda.dockerfile'
                ],
                test                : ['sanity.openjdk', 'sanity.system', 'extended.system', 'sanity.perf', 'sanity.external', 'special.functional'],
                configureArgs       : [
                        "openj9"      : '--enable-dtrace --enable-jitserver',
                        "hotspot"     : '--enable-dtrace'
                ]
        ],

        x64LinuxXL  : [
                os                  : 'linux',
                arch                : 'x64',
                dockerImage         : 'adoptopenjdk/centos7_build_image',
                dockerFile: [
                        openj9  : 'pipelines/build/dockerFiles/cuda.dockerfile'
                ],
                test                : ['sanity.openjdk', 'sanity.system', 'extended.system'],
                additionalFileNameTag: "linuxXL",
                configureArgs       : '--with-noncompressedrefs --enable-dtrace --enable-jitserver'
        ],

        // Currently we have to be quite specific about which windows to use as not all of them have freetype installed
        x64Windows: [
                os                  : 'windows',
                arch                : 'x64',
                additionalNodeLabels: [
                        hotspot: 'win2012&&vs2017'
                ],
                buildArgs : [
                        hotspot : '--jvm-variant client,server'
                ],
                test                : ['sanity.openjdk', 'sanity.perf', 'sanity.system', 'extended.system']
        ],

        x64WindowsXL: [
                os                  : 'windows',
                arch                : 'x64',
                additionalNodeLabels: 'win2012&&vs2017',
                test                : ['sanity.openjdk', 'sanity.perf', 'sanity.system', 'extended.system'],
                additionalFileNameTag: "windowsXL",
                configureArgs        : '--with-noncompressedrefs'
        ],

        x32Windows: [
                os                  : 'windows',
                arch                : 'x86-32',
                additionalNodeLabels: [
                        hotspot: 'win2012&&vs2017'
                ],
                buildArgs : [
                        hotspot : '--jvm-variant client,server'
                ],
                test                : ['sanity.openjdk']
        ],

        ppc64Aix    : [
                os                  : 'aix',
                arch                : 'ppc64',
                additionalNodeLabels: [
                        hotspot: 'xlc16&&aix710',
                        openj9:  'xlc16&&aix715'
                ],
                test                : [
                        nightly: ['sanity.openjdk'],
                        release: ['sanity.openjdk', 'sanity.system', 'extended.system']
                ]
        ],

        s390xLinux    : [
                os                  : 'linux',
                arch                : 's390x',

                test                : ['sanity.openjdk', 'sanity.system', 'extended.system', 'sanity.perf'],
                configureArgs       : '--enable-dtrace'
        ],

        s390xLinuxXL  : [
                os                   : 'linux',
                arch                 : 's390x',
                test                 : ['sanity.openjdk', 'sanity.system', 'extended.system'],
                additionalFileNameTag: "linuxXL",
                configureArgs        : '--with-noncompressedrefs --enable-dtrace'
        ],

        ppc64leLinux    : [
                os                  : 'linux',
                arch                : 'ppc64le',
                test                : ['sanity.openjdk', 'sanity.system', 'extended.system', 'sanity.perf'],
                configureArgs       : [
                        "hotspot"     : '--enable-dtrace',
                        "openj9"      : '--enable-dtrace --enable-jitserver'
                ]
        ],

        ppc64leLinuxXL    : [
                os                   : 'linux',
                arch                 : 'ppc64le',
                test                 : ['sanity.openjdk', 'sanity.system', 'extended.system'],
                additionalFileNameTag: "linuxXL",
                configureArgs        : '--with-noncompressedrefs --disable-ccache --enable-dtrace'
        ],

        arm32Linux    : [
                os                  : 'linux',
                arch                : 'arm',
                // TODO Temporarily remove the ARM tests because we don't have fast enough hardware
                //test                : ['sanity.openjdk', 'sanity.perf'],
                test                : false,
                configureArgs       : '--enable-dtrace'
        ],

        aarch64Linux    : [
                os                  : 'linux',
                arch                : 'aarch64',
                dockerImage         : 'adoptopenjdk/centos7_build_image',
                test                : ['sanity.openjdk', 'sanity.system', 'extended.system', 'sanity.perf'],
                configureArgs       : '--enable-dtrace'
        ],

        aarch64LinuxXL    : [
                os                   : 'linux',
                dockerImage          : 'adoptopenjdk/centos7_build_image',
                arch                 : 'aarch64',
                test                 : ['sanity.openjdk', 'sanity.system', 'extended.system'],
                additionalFileNameTag: "linuxXL",
                configureArgs        : '--with-noncompressedrefs --enable-dtrace'
        ],
  ]

}

Config15 config = new Config15()
return config.buildConfigurations
