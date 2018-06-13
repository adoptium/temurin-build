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
                bootJDK            : "8"
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

doBuild(javaToBuild, buildConfigurations, osTarget)

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

                buildParams += string(name: 'VARIANT', value: "${variant}");
                buildParams += string(name: 'ARCHITECTURE', value: "${configuration.arch}");

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
                stage(configuration.key) {
                    buildJobs[configuration.key] = build job: "openjdk_build_refactor", propagate: false, parameters: configuration.value.parameters
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
                    }
            }

            archiveArtifacts artifacts: 'target/*/*/*/*'
        }
    }
}