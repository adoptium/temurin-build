def buildPlatforms = ['mac', 'centos6']

def jobs = [:]
for (int i = 0; i < buildPlatforms.size(); i++) {
    def index = i
    def platform = buildPlatforms[index]
    jobs[platform] = {
        def buildJob
        stage('build') {
            buildJob = build job: "openjdk8_build_x86-64_linux-refactor", parameters: [[$class: 'LabelParameterValue', name: 'NODE_LABEL', label: "${platform}&&x64&&build"]]
        }

        archiveArtifacts artifacts: 'workspace/target/*.tar.gz, workspace/target/*.zip'
    }
}
parallel jobs
