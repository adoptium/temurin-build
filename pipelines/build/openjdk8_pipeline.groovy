def buildConfigurations = [
        x64Mac    : [
                os                  : 'mac',
                arch                : 'x64',
                bootJDK             : "7",
                test                : ['openjdktest', 'systemtest']
        ],

        x64Linux  : [
                os                 : 'linux',
                arch               : 'x64',
                bootJDK            : "7",
                additionalNodeLabels: 'centos6',
                test                : ['openjdktest', 'systemtest', 'perftest', 'externaltest']
        ],

        // Currently we have to be quite specific about which windows to use as not all of them have freetype installed
        x64Windows: [
                os                 : 'windows',
                arch               : 'x64',
                bootJDK            : "7",
                additionalNodeLabels: [
                        hotspot: 'win2008',
                        openj9:  'win2012'
                ],
                test                : ['openjdktest']
        ],

        ppc64Aix    : [
                os                 : 'aix',
                arch               : 'ppc64',
                bootJDK            : "7",
                test               : false
        ],

        s390xLinux    : [
                os                 : 'linux',
                arch               : 's390x',
                bootJDK            : "7",
                additionalNodeLabels: 'ubuntu',
                test                : ['openjdktest', 'systemtest']
        ],

        ppc64leLinux    : [
                os                 : 'linux',
                arch               : 'ppc64le',
                bootJDK            : "7",
                additionalNodeLabels: 'centos7',
                test                : ['openjdktest', 'systemtest']
        ],

        arm32Linux    : [
                os                 : 'linux',
                arch               : 'arm',
                bootJDK            : "7",
                test                : ['openjdktest']
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

