def buildConfigurations = [
        mac  : [os: 'mac', arch: 'x64'],
        linux: [os: 'centos6', arch: 'x64']
]

if (osTarget != "all") {
    buildConfigurations = buildConfigurations
            .findAll { it.value.targetLabel == osTarget }
}

def buildJobs = []
def jobs = [:]

buildConfigurations.each { buildConfiguration ->
    config = buildConfiguration.value

    def buildType = "${config.os}-${config.arch}"

    jobs[buildType] = {
        stage("build-${buildType}") {
            def buildJob = build job: "openjdk8_build-refactor", parameters: [[$class: 'LabelParameterValue', name: 'NODE_LABEL', label: "${config.os}&&${config.arch}&&build"]]
            buildJobs.add([
                    job   : buildJob,
                    config: config,
                    targetLabel: buildConfiguration.key
            ]);
        }

    }
}
parallel jobs

node {
    buildJobs.each {
        buildJob ->
            if (buildJob.job.getResult() == 'SUCCESS') {
                def buildNum =buildJob.job.getNumber();
                copyArtifacts(
                        projectName: 'openjdk8_build-refactor',
                        selector: specific("${buildNum}"),
                        filter: 'workspace/target/*',
                        fingerprintArtifacts: true,
                        target: "target/${buildJob.targetLabel}/${buildJob.config.arch}/",
                        flatten: true)
            }
    }

    archiveArtifacts artifacts: 'target/*/*/*'
}
