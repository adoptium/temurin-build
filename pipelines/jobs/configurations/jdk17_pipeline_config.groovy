class Config17 {
  final Map<String, Map<String, ?>> buildConfigurations = [
        x64Mac    : [
                os                  : 'mac',
                arch                : 'x64',
                additionalNodeLabels: 'macos10.14',
                test                : [
                        nightly: [],
                        weekly : ['sanity.openjdk', 'sanity.system', 'extended.system', 'sanity.perf']
                ],
                configureArgs       : '--enable-dtrace'
        ],
        
        x64MacXL    : [
                os                   : 'mac',
                arch                 : 'x64',
                additionalNodeLabels : 'macos10.14',
                test                 : 'default',
                additionalFileNameTag: "macosXL",
                configureArgs        : '--with-noncompressedrefs --enable-dtrace'
        ],

        x64Linux  : [
                os                  : 'linux',
                arch                : 'x64',
                dockerImage: [
                        hotspot     : 'adoptopenjdk/centos6_build_image',
                        openj9      : 'adoptopenjdk/centos7_build_image'
                ],
                dockerFile: [
                        openj9  : 'pipelines/build/dockerFiles/cuda.dockerfile'
                ],
                test                : [
                        nightly: [],
                        weekly : ['sanity.openjdk', 'sanity.system', 'extended.system', 'sanity.perf', 'sanity.external', 'special.functional']
                ],
                configureArgs       : [
                        "openj9"      : '--enable-dtrace --enable-jitserver',
                        "hotspot"     : '--enable-dtrace'
                ]
        ],
        
        x64LinuxXL  : [
                os                   : 'linux',
                arch                 : 'x64',
                dockerImage          : 'adoptopenjdk/centos7_build_image',
                dockerFile: [
                        openj9  : 'pipelines/build/dockerFiles/cuda.dockerfile'
                ],
                test                 : 'default',
                additionalFileNameTag: "linuxXL",
                configureArgs        : '--with-noncompressedrefs --enable-dtrace --enable-jitserver'
        ],

        x64AlpineLinux  : [
                os                  : 'alpine-linux',
                arch                : 'x64',
                dockerImage         : 'adoptopenjdk/alpine3_build_image',
                test                : [
                        // TODO: enable tests
                        nightly: [],
                        // release: ['sanity.openjdk', 'sanity.system', 'extended.system', 'sanity.perf', 'sanity.external', 'special.functional']
                        release: []
                ]
        ],

        x64Windows: [
                os                  : 'windows',
                arch                : 'x64',
                additionalNodeLabels: 'win2012&&vs2017',
                test                : [
                        nightly: [],
                        weekly : ['sanity.openjdk', 'sanity.perf', 'sanity.system', 'extended.system']
                ]
        ],
        
        x64WindowsXL: [
                os                   : 'windows',
                arch                 : 'x64',
                additionalNodeLabels : 'win2012&&vs2017',
                test                 : 'default',
                additionalFileNameTag: "windowsXL",
                configureArgs        : '--with-noncompressedrefs'
        ],

        aarch64Windows: [
                os                  : 'windows',
                arch                : 'aarch64',
                crossCompile        : 'x64',
                buildArgs           : '--cross-compile',
                additionalNodeLabels: 'win2016&&vs2019',
                test                : [
                        nightly: [],
                        weekly : []
                ]
        ],


        x32Windows: [
                os                  : 'windows',
                arch                : 'x86-32',
                additionalNodeLabels: 'win2012&&vs2017',
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
                        nightly: [],
                        weekly : ['sanity.openjdk', 'sanity.system', 'extended.system']
                ]
        ],


        s390xLinux    : [
                os                  : 'linux',
                arch                : 's390x',
                test                : [
                        nightly: [],
                        weekly : ['sanity.openjdk', 'sanity.system', 'extended.system', 'sanity.perf']
                ],
                configureArgs       : '--enable-dtrace'
        ],
        
        s390xLinuxXL  : [
                os                   : 'linux',
                arch                 : 's390x',
                test                 : 'default',
                additionalFileNameTag: "linuxXL",
                configureArgs        : '--with-noncompressedrefs --enable-dtrace'
        ],

        ppc64leLinux    : [
                os                  : 'linux',
                arch                : 'ppc64le',
                test                : [
                        nightly: [],
                        weekly: ['sanity.openjdk', 'sanity.system', 'extended.system', 'sanity.perf']
                ],
                configureArgs       : [
                        "hotspot"     : '--enable-dtrace',
                        "openj9"      : '--enable-dtrace --enable-jitserver'
                ]

        ],
        
        ppc64leLinuxXL    : [
                os                   : 'linux',
                arch                 : 'ppc64le',
                test                 : 'default',
                additionalFileNameTag: "linuxXL",
                configureArgs        : '--with-noncompressedrefs --disable-ccache --enable-dtrace'
        ],

        aarch64Linux    : [
                os                  : 'linux',
                arch                : 'aarch64',
                dockerImage         : 'adoptopenjdk/centos7_build_image',
                test                : [
                        nightly: [],
                        weekly : ['sanity.openjdk', 'sanity.system', 'extended.system', 'sanity.perf']
                ],
                configureArgs       : '--enable-dtrace'
        ],
        
        aarch64LinuxXL    : [
                os                   : 'linux',
                dockerImage          : 'adoptopenjdk/centos7_build_image',
                arch                 : 'aarch64',
                test                 : 'default',
                additionalFileNameTag: "linuxXL",
                configureArgs        : '--with-noncompressedrefs --enable-dtrace'
        ],

        arm32Linux    : [
                os                  : 'linux',
                arch                : 'arm',
                test                : [
                        nightly: ['sanity.openjdk'],
                        weekly : []
                ],
                configureArgs       : '--enable-dtrace'
        ]
  ]

}

Config17 config = new Config17()
return config.buildConfigurations
