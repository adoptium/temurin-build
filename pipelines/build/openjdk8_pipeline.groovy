def buildConfigurations = [
        mac    : [
                os                 : 'mac',
                arch               : 'x64',
                bootJDK            : "7"
        ],

        linux  : [
                os                 : 'centos6',
                arch               : 'x64',
                bootJDK            : "7"
        ],

        // Currently we have to be quite specific about which windows to use as not all of them have freetype installed
        windows: [
                os                 : 'windows',
                arch               : 'x64',
                bootJDK            : "7",
                aditionalNodeLabels: [
                        hotspot: 'win2008',
                        openj9:  'win2012'
                ]
        ],

        aix    : [
                os                 : 'aix',
                arch               : 'ppc64',
                bootJDK            : "7"
        ],
]


def javaToBuild = "jdk8u"

///////////////////////////////////////////////////
//Do build is the same for all pipelines

/*
def osTarget = '''{
    "windows": ["hotspot", "openj9"],
    "linux": ["hotspot", "openj9"],
    "aix": ["hotspot", "openj9"],
    "mac": ["hotspot"]
}'''
*/


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
                }

                if (configuration.containsKey("additionalNodeLabels")) {
                    if (configuration.additionalNodeLabels instanceof Map) {
                        configuration.additionalNodeLabels = configuration.additionalNodeLabels.get(variant)
                    }
                    configuration.additionalNodeLabels = "${configuration.additionalNodeLabels}&&${buildTag}";
                } else {
                    configuration.additionalNodeLabels = buildTag;
                }

                def buildParams = [
                        string(name: 'JAVA_TO_BUILD', value: "${javaToBuild}"),
                        [$class: 'LabelParameterValue', name: 'NODE_LABEL', label: "${configuration.additionalNodeLabels}&&${configuration.os}&&${configuration.arch}"]
                ];

                if (configuration.containsKey('bootJDK')) buildParams += string(name: 'JDK_BOOT_VERSION', value: "${configuration.bootJDK}");
                if (configuration.containsKey('configureArgs')) buildParams += string(name: 'CONFIGURE_ARGS', value: "${configuration.configureArgs}");
                if (configuration.containsKey('buildArgs')) buildParams += string(name: 'BUILD_ARGS', value: "${configuration.buildArgs}");

                buildParams += string(name: 'VARIANT', value: "${variant}");

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