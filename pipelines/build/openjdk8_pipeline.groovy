def buildConfigurations = [
        [os: 'mac', arch: 'x64'],
        [os: 'centos6', arch: 'x64']
]

def jobs = [:]
for (int i = 0; i < buildConfigurations.size(); i++) {
    def index = i
    def config = buildConfigurations[index]

    def buildType = "${config.os}-${config.arch}"
    def buildJobNum

    jobs[buildType] = {
        stage("build-${buildType}") {

            node {
                copyArtifacts(
                        projectName: 'openjdk8_build-refactor',
                        selector: specific("13"),
                        filter: 'workspace/target/*',
                        fingerprintArtifacts: true,
                        target: 'target/${config.arch}/',
                        flatten: true)
            }
            //buildJob = build job: "openjdk8_build-refactor", parameters: [[$class: 'LabelParameterValue', name: 'NODE_LABEL', label: "${config.os}&&${config.arch}&&build"]]
            //buildJobNum = buildJob.getNumber()
            //archiveArtifacts artifacts: 'workspace/target/*.tar.gz, workspace/target/*.zip'


        }

    }
}
parallel jobs

node {
    archiveArtifacts artifacts: 'target/*/*.tar.gz, target/*/*.zip'
}
