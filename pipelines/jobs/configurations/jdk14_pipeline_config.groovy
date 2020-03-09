def buildConfigurations = [
        x64Mac    : [
                os                  : 'mac',
                arch                : 'x64',
                additionalNodeLabels : 'macos10.14',
                test                : [
                        nightly: false,
                        release: ['sanity.openjdk', 'sanity.system', 'extended.system', 'sanity.perf']
                ]
        ],

        x64MacXL: [
                os                   : 'mac',
                arch                 : 'x64',
                additionalNodeLabels : 'macos10.14',
                test                 : [
                        nightly: false,
                        release: ['sanity.openjdk', 'sanity.system', 'extended.system', 'sanity.perf']
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
                configureArgs        : '--disable-ccache'
        ],

        x64LinuxXL    : [
                os                   : 'linux',
                additionalNodeLabels : 'centos6',
                arch                 : 'x64',
                test                 : [
                        nightly: false,
                        release: ['sanity.openjdk', 'sanity.system', 'extended.system']
                ],
                additionalFileNameTag: "linuxXL",
                configureArgs        : '--with-noncompressedrefs --disable-ccache'
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
                test                : [
                        nightly: false,
                        release: ['sanity.openjdk', 'sanity.perf', 'sanity.system', 'extended.system']
                ]
        ],

        x64WindowsXL    : [
                os                   : 'windows',
                arch                 : 'x64',
                additionalNodeLabels : 'win2012&&vs2017',
                test                 : [
                        nightly: false,
                        release: ['sanity.openjdk', 'sanity.perf', 'sanity.system', 'extended.system']
                ],
                additionalFileNameTag: "windowsXL",
                configureArgs        : '--with-noncompressedrefs'
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

        s390xLinuxXL    : [
                os                   : 'linux',
                arch                 : 's390x',
                test                 : [
                        nightly: false,
                        release: ['sanity.openjdk', 'sanity.system', 'extended.system']
                ],
                additionalFileNameTag: "linuxXL",
                configureArgs        : '--with-noncompressedrefs --disable-ccache'
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

        ppc64leLinuxXL    : [
                os                   : 'linux',
                arch                 : 'ppc64le',
                test                 : [
                        nightly: false,
                        release: ['sanity.openjdk', 'sanity.system', 'extended.system']
                ],
                additionalFileNameTag: "linuxXL",
                configureArgs        : '--with-noncompressedrefs --disable-ccache'
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

]

return buildConfigurations