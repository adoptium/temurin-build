def buildConfigurations = [
        mac  : [os: 'mac', arch: 'x64', targetLabel: 'mac'],
        linux: [os: 'centos6', arch: 'x64', targetLabel: 'linux']
]

if (osTarget != "all") {
    buildConfigurations = buildConfigurations[osTarget];
}

def buildJobs = []
def jobs = [:]
for (int i = 0; i < buildConfigurations.size(); i++) {
    def index = i
    def config = buildConfigurations[index]

    def buildType = "${config.os}-${config.arch}"

    jobs[buildType] = {
        stage("build-${buildType}") {
            def buildJob = build job: "openjdk8_build-refactor", parameters: [[$class: 'LabelParameterValue', name: 'NODE_LABEL', label: "${config.os}&&${config.arch}&&build"]]
            buildJobs.add([
                    job   : buildJob,
                    config: config
            ]);
        }

    }
}
parallel jobs

node {
    buildJobs.each {
        buildJob ->
            if (buildJob.job.getResult() == 'SUCCESS') {
                copyArtifacts(
                        projectName: 'openjdk8_build-refactor',
                        selector: specific(buildJob.job.getNumber()),
                        filter: 'workspace/target/*',
                        fingerprintArtifacts: true,
                        target: "target/${buildJob.config.targetLabel}/${buildJob.config.arch}/",
                        flatten: true)
            }
    }

    archiveArtifacts artifacts: 'target/*/*/*'
}
