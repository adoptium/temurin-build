class Config11 {
  final Map<String, Map<String, ?>> buildConfigurations = [
        x64Mac    : [
                os                  : 'mac',
                arch                : 'x64',
                additionalNodeLabels : 'macos10.14',
                test                : 'default',
                additionalFileNameTag: [
                        "openj9"    : "mixedrefs"
                ],
                configureArgs       : [
                        "openj9"      : '--enable-dtrace=auto --with-cmake --with-mixedrefs',
                        "hotspot"     : '--enable-dtrace=auto'
                ]
        ],

        x64Linux  : [
                os                  : 'linux',
                arch                : 'x64',
                dockerImage         : 'adoptopenjdk/centos6_build_image',
                dockerFile: [
                        openj9  : 'pipelines/build/dockerFiles/cuda.dockerfile'
                ],
                test                : 'default',
                additionalFileNameTag: [
                        "openj9"    : "mixedrefs"
                ],
                configureArgs       : [
                        "openj9"      : '--enable-jitserver --enable-dtrace=auto --with-mixedrefs',
                        "hotspot"     : '--enable-dtrace=auto',
                        "corretto"    : '--enable-dtrace=auto',
                        "SapMachine"  : '--enable-dtrace=auto',
                        "dragonwell"  : '--enable-dtrace=auto --enable-unlimited-crypto --with-jvm-variants=server --with-zlib=system --with-jvm-features=zgc'
                ]
        ],

        x64Windows: [
                os                  : 'windows',
                arch                : 'x64',
                additionalNodeLabels: [
                        hotspot:    'win2012',
                        openj9:     'win2012&&vs2017',
                        dragonwell: 'win2012'
                ],
                buildArgs : [
                        hotspot : '--jvm-variant client,server'
                ],
                configureArgs       : [
                        "openj9"      : '--with-mixedrefs'
                ],
                additionalFileNameTag: [
                        "openj9"    : "mixedrefs"
                ],
                test                : 'default'
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
                test                : 'default'
        ],

        ppc64Aix    : [
                os                  : 'aix',
                arch                : 'ppc64',
                additionalNodeLabels: [
                        hotspot: 'xlc13&&aix710',
                        openj9:  'xlc13&&aix715'
                ],
                test                : 'default',
                configureArgs       : [
                        "openj9"      : '--with-mixedrefs'
                ],
                additionalFileNameTag: [
                        "openj9"    : "mixedrefs"
                ],
                cleanWorkspaceAfterBuild: true
        ],

        s390xLinux    : [
                os                  : 'linux',
                arch                : 's390x',
                test                : 'default',
                additionalFileNameTag: [
                        "openj9"    : "mixedrefs"
                ],
                configureArgs       : [
                        "openj9"      : '--enable-dtrace=auto --with-mixedrefs',
                        "hotspot"     : '--enable-dtrace=auto'
                ]
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
                additionalNodeLabels : 'centos7',
                test                : 'default',
                additionalFileNameTag: [
                        "openj9"    : "mixedrefs"
                ],
                configureArgs       : [
                        "hotspot"     : '--enable-dtrace=auto',
                        "openj9"      : '--enable-dtrace=auto --enable-jitserver --with-mixedrefs'
                ]

        ],

        arm32Linux    : [
                os                  : 'linux',
                arch                : 'arm',
                test                : 'default',
                configureArgs       : '--enable-dtrace=auto'
        ],

        aarch64Linux    : [
                os                  : 'linux',
                arch                : 'aarch64',
                dockerImage         : 'adoptopenjdk/centos7_build_image',
                test                : 'default',
                additionalFileNameTag: [
                        "openj9"    : "mixedrefs"
                ],
                configureArgs       : [
                        "hotspot" : '--enable-dtrace=auto',
                        "openj9" : '--enable-dtrace=auto --with-mixedrefs',
                        "corretto" : '--enable-dtrace=auto',
                        "dragonwell" : "--enable-dtrace=auto --with-extra-cflags=\"-march=armv8.2-a+crypto\" --with-extra-cxxflags=\"-march=armv8.2-a+crypto\""
                ]
        ],

        riscv64Linux      :  [
                os                   : 'linux',
                dockerImage          : 'adoptopenjdk/centos6_build_image',
                arch                 : 'riscv64',
                crossCompile         : 'x64',
                buildArgs            : '--cross-compile',
                configureArgs        : '--disable-ddr --openjdk-target=riscv64-unknown-linux-gnu --with-sysroot=/opt/fedora28_riscv_root'
        ],
  ]

}

Config11 config = new Config11()
return config.buildConfigurations
