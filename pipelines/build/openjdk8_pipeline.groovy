def buildConfigurations = [
        [os: 'mac', arch: 'x64'],
        [os: 'centos6', arch: 'x64']
]

def jobs = [:]
for (int i = 0; i < buildConfigurations.size(); i++) {
    def index = i
    def config = buildConfigurations[index]

    def buildType = "${config.os}-${config.arch}"

    jobs[buildType] = {
        stage("build-${buildType}") {
            build job: "openjdk8_build-refactor", parameters: [[$class: 'LabelParameterValue', name: 'NODE_LABEL', label: "${config.os}&&${config.arch}&&build"]]
        }
        stage("archive-${buildType}") {
            archiveArtifacts artifacts: 'workspace/target/*.tar.gz, workspace/target/*.zip'
        }
    }
}
parallel jobs
