def buildConfigurations = [
        mac    : [
                os                 : 'mac',
                arch               : 'x64',
                bootJDK            : "8"
        ],

        linux  : [
                os                 : 'centos6',
                arch               : 'x64',
                bootJDK            : "8"
        ],

        // Currently we have to be quite specific about which windows to use as not all of them have freetype installed
        windows: [
                os                  : 'windows',
                arch                : 'x64',
                bootJDK             : "8",
                additionalNodeLabels: 'win2012'
        ],

        aix    : [
                os                 : 'aix',
                arch               : 'ppc64',
                bootJDK            : "8"
        ],

        s390x    : [
                os                 : 'linux',
                arch               : 's390x',
                bootJDK            : "8",
                additionalNodeLabels: 'ubuntu'
        ],

        ppc64le    : [
                os                 : 'linux',
                arch               : 'ppc64le',
                bootJDK            : "8",
                additionalNodeLabels: 'centos7'
        ],

        arm32    : [
                os                 : 'linux',
                arch               : 'arm',
                bootJDK            : "8"
        ],

        aarch64    : [
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
