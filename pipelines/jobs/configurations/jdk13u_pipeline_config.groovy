class Config13 {
  final Map<String, Map<String, ?>> buildConfigurations = [
        x64Mac    : [
                os                  : 'mac',
                arch                : 'x64',
                additionalNodeLabels : 'macos10.12',
                test                : [
                        nightly: ['sanity.openjdk', 'sanity.system', 'extended.system', 'sanity.perf'],
                        weekly : []
                ],
                configureArgs       : '--enable-dtrace=auto'
        ],

        x64MacXL    : [
                os                   : 'mac',
                arch                 : 'x64',
                additionalNodeLabels : 'macos10.12',
                test                : [
                        nightly: ['sanity.openjdk', 'sanity.system', 'extended.system', 'sanity.perf'],
                        weekly : []
                ],
                additionalFileNameTag: "macosXL",
                configureArgs        : '--with-noncompressedrefs --enable-dtrace=auto'
        ],

        x64Linux  : [
                os                  : 'linux',
                arch                : 'x64',
                additionalNodeLabels: 'centos6',
                test                : [
                        nightly: ['sanity.openjdk', 'sanity.system', 'extended.system', 'sanity.perf', 'sanity.external'],
                        weekly : ['special.functional']
                ],
                configureArgs        : '--disable-ccache --enable-dtrace=auto'
        ],

        // Currently we have to be quite specific about which windows to use as not all of them have freetype installed
        x64Windows: [
                os                  : 'windows',
                arch                : 'x64',
                additionalNodeLabels: [
                        hotspot: 'win2012&&vs2017',
                        openj9:  'win2012&&vs2017'
                ],
                buildArgs : [
                        hotspot : '--jvm-variant client,server'
                ],
                test                : [
                        nightly: ['sanity.openjdk', 'sanity.system', 'extended.system', 'sanity.perf'],
                        weekly : []
                ]
        ],

        x64WindowsXL    : [
                os                   : 'windows',
                arch                 : 'x64',
                additionalNodeLabels : 'win2012&&vs2017',
                test                : [
                        nightly: ['sanity.openjdk', 'sanity.system', 'extended.system', 'sanity.perf'],
                        weekly : []
                ],
                additionalFileNameTag: "windowsXL",
                configureArgs        : '--with-noncompressedrefs'
        ],

        x32Windows: [
                os                  : 'windows',
                arch                : 'x86-32',
                additionalNodeLabels: [
                        hotspot: 'win2012&&vs2017',
                        openj9:  'win2012&&mingw-standalone'
                ],
                buildArgs : [
                        hotspot : '--jvm-variant client,server'
                ],
                test                : [
                        nightly: ['sanity.openjdk'],
                        weekly : []
                ]
        ],

        ppc64Aix    : [
                os                  : 'aix',
                arch                : 'ppc64',
                additionalNodeLabels: 'xlc16',
                test                : [
                        nightly: []
                        weekly: ['sanity.openjdk', 'sanity.system', 'extended.system']
                ]
        ],

        s390xLinux    : [
                os                  : 'linux',
                arch                : 's390x',
                test                : [
                        nightly: ['sanity.openjdk', 'sanity.system', 'extended.system', 'sanity.perf'],
                        weekly : []
                ],
                configureArgs        : '--disable-ccache --enable-dtrace=auto'
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
                test                : [
                        nightly: ['sanity.openjdk', 'sanity.system', 'extended.system', 'sanity.perf'],
                        weekly : []
                ],
                configureArgs       : '--disable-ccache --enable-dtrace=auto'

        ],

        arm32Linux    : [
                os                  : 'linux',
                arch                : 'arm',
                test                : [
                        nightly: ['sanity.openjdk'],
                        weekly : []
                ],
                configureArgs       : '--enable-dtrace=auto'
        ],

        aarch64Linux    : [
                os                  : 'linux',
                arch                : 'aarch64',
                additionalNodeLabels: 'centos7',
                test                : [
                        nightly: ['sanity.openjdk', 'sanity.system', 'extended.system', 'sanity.perf'],
                        weekly : []
                ],
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
                test                : [
                        nightly: ['sanity.openjdk', 'sanity.system', 'extended.system'],
                        weekly : []
                ],
                additionalFileNameTag: "linuxXL",
                configureArgs        : '--with-noncompressedrefs --disable-ccache --enable-dtrace=auto'
        ],
        s390xLinuxXL    : [
                os                   : 'linux',
                arch                 : 's390x',
                test                : [
                        nightly: ['sanity.openjdk', 'sanity.system', 'extended.system'],
                        weekly : []
                ],
                additionalFileNameTag: "linuxXL",
                configureArgs        : '--with-noncompressedrefs --disable-ccache --enable-dtrace=auto'
        ],
        ppc64leLinuxXL    : [
                os                   : 'linux',
                arch                 : 'ppc64le',
                test                : [
                        nightly: ['sanity.openjdk', 'sanity.system', 'extended.system'],
                        weekly : []
                ],
                additionalFileNameTag: "linuxXL",
                configureArgs        : '--with-noncompressedrefs --disable-ccache --enable-dtrace=auto'
        ],
  ]
  
}

Config13 config = new Config13()
return config.buildConfigurations