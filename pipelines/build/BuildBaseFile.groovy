//TODO: make it a shared library


def buildConfiguration(javaToBuild, variant, configuration) {

    def buildTag = "build"

    if (configuration.os == "windows" && variant == "openj9") {
        buildTag = "buildj9"
    } else if (configuration.arch == "s390x" && variant == "openj9") {
        buildTag = "openj9"
    }

    def additionalNodeLabels;
    if (configuration.containsKey("additionalNodeLabels")) {
        // hack as jenkins sandbox wont allow instanceof
        if ("java.util.LinkedHashMap".equals(configuration.additionalNodeLabels.getClass().getName())) {
            additionalNodeLabels = configuration.additionalNodeLabels.get(variant)
        } else {
            additionalNodeLabels = configuration.additionalNodeLabels;
        }

        additionalNodeLabels = "${additionalNodeLabels}&&${buildTag}";
    } else {
        additionalNodeLabels = buildTag;
    }

    def buildParams = [
            string(name: 'JAVA_TO_BUILD', value: "${javaToBuild}"),
            [$class: 'LabelParameterValue', name: 'NODE_LABEL', label: "${additionalNodeLabels}&&${configuration.os}&&${configuration.arch}"]
    ];

    if (configuration.containsKey('bootJDK')) buildParams += string(name: 'JDK_BOOT_VERSION', value: "${configuration.bootJDK}");
    if (configuration.containsKey('configureArgs')) buildParams += string(name: 'CONFIGURE_ARGS', value: "${configuration.configureArgs}");
    if (configuration.containsKey('buildArgs')) buildParams += string(name: 'BUILD_ARGS', value: "${configuration.buildArgs}");

    buildParams += string(name: 'VARIANT', value: "${variant}")
    buildParams += string(name: 'ARCHITECTURE', value: "${configuration.arch}")
    buildParams += choice(name: 'OS', value: "${configuration.os}")

    return [
            javaVersion: javaToBuild,
            arch       : configuration.arch,
            os         : configuration.os,
            variant    : variant,
            parameters : buildParams,
            test       : configuration.test,
            publish    : true
    ]
}

def getJobConfigurations(javaToBuild, buildConfigurations, osTarget) {
    def jobConfigurations = [:]

    new groovy.json.JsonSlurper().parseText(osTarget).each { target ->
        if (buildConfigurations.containsKey(target.key)) {
            def configuration = buildConfigurations.get(target.key)
            target.value.each { variant ->
                def name = "${configuration.os}-${configuration.arch}-${variant}"
                jobConfigurations[name] = buildConfiguration(javaToBuild, variant, configuration);
            }
        }
    }

    return jobConfigurations;
}

def determineTestJobName(config, testType) {

    def variant;
    def number;


    if (config.javaVersion == "jdk8u") {
        number = 8
    } else if (config.javaVersion == "jdk9u") {
        number = 9
    } else if (config.javaVersion == "jdk10u") {
        number = 10
    }

    if (config.variant == "hotspot") {
        variant = "hs"
    } else if (config.variant == "openj9") {
        variant = "j9"
    }

    def arch = config.arch
    if (arch == "x64") {
        arch = "x86-64"
    }

    def os = config.os;
    if (os == "mac") {
        os = "macos"
    }

    return "openjdk${number}_${variant}_${testType}_${arch}_${os}"
}


def doBuild(javaToBuild, buildConfigurations, osTarget, enableTests, publish) {
    def jobConfigurations = getJobConfigurations(javaToBuild, buildConfigurations, osTarget)
    def jobs = [:]
    def buildJobs = [:]

    def downstreamJob="openjdk_build_refactor_pipeline"

    jobConfigurations.each { configuration ->
        jobs[configuration.key] = {
            catchError {
                def job;
                def config = configuration.value;
                stage(configuration.key) {
                    job = build job: downstreamJob, displayName: configuration.key, propagate: false, parameters: configuration.value.parameters
                    buildJobs[configuration.key] = job;
                }

                if (enableTests && config.test) {
                    stage("test ${configuration.key}") {
                        if (job.getResult() == 'SUCCESS') {
                            config.test.each { testType ->
                                def jobName = determineTestJobName(config, testType)
                                catchError {
                                    build job: jobName,
                                            propagate: false,
                                            parameters: [string(name: 'UPSTREAM_JOB_NUMBER', value: "${job.getNumber()}"),
                                                         string(name: 'UPSTREAM_JOB_NAME', value: "openjdk_build_refactor")]
                                }
                            }
                        }
                    }
                }

                if (publish && config.publish) {
                    sh "echo execute openjdk_release_tool REPO: nightly, TAG: jdk8u172-b00"
                    /*
                        stage("publish nightly ${configuration.key}") {
                            build job: 'openjdk_release_tool',
                                    parameters: [string(name: 'REPO', value: 'nightly'),
                                                 string(name: 'TAG', value: 'jdk8u172-b00'),
                                                 string(name: 'VERSION', value: 'jdk8'),
                                                 string(name: 'CHECKSUM_JOB_NAME', value: "openjdk8_build_checksum"),
                                                 string(name: 'CHECKSUM_JOB_NUMBER', value: "${checksumJob.getNumber()}")]
                        }
                */
                }
            }
        }
    }

    try {
        parallel jobs
    } finally {
        node('master') {
            buildJobs.each {
                buildJob ->
                    def job = buildJob.value
                    def name = buildJob.key
                    def configuration = jobConfigurations[name];

                    if (job.getResult() == 'SUCCESS') {
                        currentBuild.result = 'SUCCESS'
                        sh "rm target/${configuration.os}/${configuration.arch}/${configuration.variant}/* || true"

                        copyArtifacts(
                                projectName: downstreamJob,
                                selector: specific("${job.getNumber()}"),
                                filter: 'workspace/target/*',
                                fingerprintArtifacts: true,
                                target: "target/${configuration.os}/${configuration.arch}/${configuration.variant}/",
                                flatten: true)


                        sh 'for file in $(ls target/*/*/*/*.tar.gz target/*/*/*/*.zip); do sha256sum "$file" > $file.sha256.txt ; done'
                        archiveArtifacts artifacts: "target/${configuration.os}/${configuration.arch}/${configuration.variant}/*"
                    }
            }
        }
    }
}

return this