//TODO: make it a shared library
def doBuild(javaToBuild, buildConfigurations, osTarget) {
    def jobConfigurations = [:]

    new groovy.json.JsonSlurper().parseText(osTarget).each { target ->
        if (buildConfigurations.containsKey(target.key)) {
            def configuration = buildConfigurations.get(target.key)

            def buildType = "${configuration.os}-${configuration.arch}"

            target.value.each { variant ->

                def buildTag = "build"

                if (target.key == "windows" && variant == "openj9") {
                    buildTag = "buildj9"
                } else if (target.key == "s390x" && variant == "openj9") {
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
                buildParams += string(name: 'ARCHITECTURE', value: "${configuration.arch}"); ;

                def name = "${buildType}-${variant}"

                jobConfigurations[name] = [
                        config     : configuration,
                        variant    : variant,
                        targetLabel: target.key,
                        parameters : buildParams,
                        name       : "${buildType}-${variant}"
                ]
            }
        }
    }

    def jobs = [:]
    def buildJobs = [:]

    jobConfigurations.each { configuration ->
        jobs[configuration.key] = {
            catchError {
                def job;
                stage(configuration.key) {

                    sh "echo \"a build stage of openjdk_build_refactor ${configuration.key} ${job.getNumber()}\""
                    /*
                    job = build job: "openjdk_build_refactor", propagate: false, parameters: configuration.value.parameters
                    buildJobs[configuration.key];
                    */
                }

                stage("test ${configuration.key}") {
                    sh "echo \"a test stage of openjdk_build_refactor ${configuration.key} ${job.getNumber()}\""
                    /*
                    build job: "openjdk8_hs_${it}_${archOS}",
                            propagate: false,
                            parameters: [string(name: 'UPSTREAM_JOB_NUMBER', value: "${job.getNumber()}"),
                                         string(name: 'UPSTREAM_JOB_NAME', value: "openjdk_build_refactor")]
                                         */
                }

                stage("publish nightly ${configuration.key}") {
                    sh "echo \"a publish stage of openjdk_build_refactor ${configuration.key} ${job.getNumber()}\""
                    /*
                    build job: 'openjdk_release_tool',
                            parameters: [string(name: 'REPO', value: 'nightly'),
                                         string(name: 'TAG', value: 'jdk8u172-b00'),
                                         string(name: 'VERSION', value: 'jdk8'),
                                         string(name: 'CHECKSUM_JOB_NAME', value: "openjdk8_build_checksum"),
                                         string(name: 'CHECKSUM_JOB_NUMBER', value: "${checksumJob.getNumber()}")]
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
                        sh "rm target/${configuration.targetLabel}/${configuration.config.arch}/${configuration.variant}/* || true"

                        copyArtifacts(
                                projectName: 'openjdk_build_refactor',
                                selector: specific("${job.getNumber()}"),
                                filter: 'workspace/target/*',
                                fingerprintArtifacts: true,
                                target: "target/${configuration.targetLabel}/${configuration.config.arch}/${configuration.variant}/",
                                flatten: true)


                        sh 'for file in $(ls target/*/*/*/*.tar.gz target/*/*/*/*.zip); do sha256sum "$file" > $file.sha256.txt ; done'
                    }
            }

            archiveArtifacts artifacts: 'target/*/*/*/*'
        }
    }
}

return this