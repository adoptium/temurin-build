def buildConfigurations = [
        mac    : [os: 'mac', arch: 'x64', aditionalNodeLabels: 'build'],
        linux  : [os: 'centos6', arch: 'x64', aditionalNodeLabels: 'build'],

        // Currently we have to be quite specific about which windows to use as not all of them have freetype installed
        windows: [os: 'windows', arch: 'x64', aditionalNodeLabels: 'build&&win2008']
]

if (osTarget != "all") {
    buildConfigurations = buildConfigurations
            .findAll { it.key == osTarget }
}

node {
    checkout scm
    def rootDir = pwd()
    def OpenJDKBuild = load("${rootDir}/pipelines/build/OpenJDKBuild.groovy")

    OpenJDKBuild.doBuild("jdk9", buildConfigurations)
}