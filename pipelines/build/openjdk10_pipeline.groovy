def buildConfigurations = [
        x64Mac    : [
                os                  : 'mac',
                arch                : 'x64',
                bootJDK             : "/Users/jenkins/tools/hudson.model.JDK/JDK9.0.1",
                test                : ['openjdktest', 'systemtest']
        ],
        x64Linux  : [
                os                  : 'linux',
                arch                : 'x64',
                bootJDK             : "9",
                additionalNodeLabels: 'centos6',
                test                : ['openjdktest']
        ],

        // Currently we have to be quite specific about which windows to use as not all of them have freetype installed
        x64Windows: [
                os                  : 'windows',
                arch                : 'x64',
                bootJDK             : "9",
                additionalNodeLabels: 'win2012',
                test                : ['openjdktest']
        ],

        ppc64Aix    : [
                os                  : 'aix',
                arch                : 'ppc64',
                bootJDK             : "9",
                test                : false
        ],

        s390xLinux    : [
                os                 : 'linux',
                arch               : 's390x',
                bootJDK            : "9",
                additionalNodeLabels: 'ubuntu',
                test                : ['openjdktest', 'systemtest']
        ],

        ppc64leLinux    : [
                os                 : 'linux',
                arch               : 'ppc64le',
                bootJDK            : "9",
                additionalNodeLabels: 'centos7',
                test                : ['openjdktest', 'systemtest']
        ],

        arm32Linux    : [
                os                 : 'linux',
                arch               : 'arm',
                bootJDK            : "9",
                test                : ['openjdktest']
        ],

        aarch64Linux    : [
                os                 : 'linux',
                arch               : 'aarch64',
                bootJDK            : "9",
                additionalNodeLabels: 'centos7',
                test                : ['openjdktest']
        ],
]

def javaToBuild = "jdk10u"

node ("master") {
    checkout scm
    def buildFile = load "${WORKSPACE}/pipelines/build/BuildBaseFile.groovy"
    buildFile.doBuild(javaToBuild, buildConfigurations, osTarget)
}
