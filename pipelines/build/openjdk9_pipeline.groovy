def buildConfigurations = [
        x64Mac    : [
                os                 : 'mac',
                arch               : 'x64',
                bootJDK            : "8"
        ],

        x64Linux  : [
                os                 : 'linux',
                arch               : 'x64',
                bootJDK            : "8",
                additionalNodeLabels: 'centos6'
        ],

        // Currently we have to be quite specific about which windows to use as not all of them have freetype installed
        x64Windows: [
                os                  : 'windows',
                arch                : 'x64',
                bootJDK             : "8",
                additionalNodeLabels: 'win2012'
        ],

        ppc64Aix    : [
                os                 : 'aix',
                arch               : 'ppc64',
                bootJDK            : "8"
        ],

        s390xLinux    : [
                os                 : 'linux',
                arch               : 's390x',
                bootJDK            : "8",
                additionalNodeLabels: 'ubuntu'
        ],

        ppc64leLinux    : [
                os                 : 'linux',
                arch               : 'ppc64le',
                bootJDK            : "8",
                additionalNodeLabels: 'centos7'
        ],

        arm32Linux    : [
                os                 : 'linux',
                arch               : 'arm',
                bootJDK            : "8"
        ],

        aarch64Linux    : [
                os                 : 'linux',
                arch               : 'aarch64',
                bootJDK            : "8",
                additionalNodeLabels: 'centos7'
        ],
]

def javaToBuild = "jdk9"

node ("master") {
    checkout scm
    def buildFile = load "${WORKSPACE}/pipelines/build/BuildBaseFile.groovy"
    buildFile.doBuild(javaToBuild, buildConfigurations, osTarget)
}
