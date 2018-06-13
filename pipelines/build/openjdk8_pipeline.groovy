def buildConfigurations = [
        mac    : [
                os                 : 'mac',
                arch               : 'x64',
                bootJDK            : "7"
        ],

        linux  : [
                os                 : 'centos6',
                arch               : 'x64',
                bootJDK            : "7"
        ],

        // Currently we have to be quite specific about which windows to use as not all of them have freetype installed
        windows: [
                os                 : 'windows',
                arch               : 'x64',
                bootJDK            : "7",
                additionalNodeLabels: [
                        hotspot: 'win2008',
                        openj9:  'win2012'
                ]
        ],

        aix    : [
                os                 : 'aix',
                arch               : 'ppc64',
                bootJDK            : "7"
        ],

        s390x    : [
                os                 : 'linux',
                arch               : 's390x',
                bootJDK            : "7",
                additionalNodeLabels: 'ubuntu'
        ],

        ppc64le    : [
                os                 : 'linux',
                arch               : 'ppc64le',
                bootJDK            : "7",
                additionalNodeLabels: 'centos7'
        ],

        arm32    : [
                os                 : 'linux',
                arch               : 'arm',
                bootJDK            : "7"
        ],
]


def javaToBuild = "jdk8u"

///////////////////////////////////////////////////
//Do build is the same for all pipelines

/*
def osTarget = '''{
    "windows": ["hotspot", "openj9"],
    "linux": ["hotspot", "openj9"],
    "aix": ["hotspot", "openj9"],
    "mac": ["hotspot"]
}'''
*/
node ("master") {
    checkout scm
    def buildFile = load "${WORKSPACE}/pipelines/build/BuildBaseFile.groovy"
    buildFile.doBuild(javaToBuild, buildConfigurations, osTarget)
}

