def buildConfigurations = [
        mac    : [
                os                 : 'mac',
                arch               : 'x64',
                bootJDK            : "8",
                path               : "/Users/jenkins/ccache-3.2.4",
                configureArgs      : "--disable-warnings-as-errors",
                xCodeSwitchPath    : "/",
                aditionalNodeLabels: 'build'
        ],

        linux  : [
                os                 : 'centos6',
                arch               : 'x64',
                bootJDK            : "8",
                configureArgs      : "--disable-warnings-as-errors",
                aditionalNodeLabels: 'build'
        ],

        // Currently we have to be quite specific about which windows to use as not all of them have freetype installed
        windows: [
                os                 : 'windows',
                arch               : 'x64',
                bootJDK            : "8",
                path               : "/usr/bin:/cygdrive/c/Program Files (x86)/Microsoft Visual Studio 10.0/VC/bin/amd64/",
                configureArgs      : "--disable-warnings-as-errors --with-freetype=/cygdrive/C/openjdk/freetype --disable-ccache",
                aditionalNodeLabels: 'build&&win2012'
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

            def buildParams = [
                    string(name: 'JAVA_TO_BUILD', value: "${javaToBuild}"),
                    [$class: 'LabelParameterValue', name: 'NODE_LABEL', label: "${configuration.aditionalNodeLabels}&&${configuration.os}&&${configuration.arch}"]
            ];

            if (configuration.containsKey('bootJDK')) buildParams += string(name: 'JDK_BOOT_VERSION', value: "${configuration.bootJDK}");
            if (configuration.containsKey('path')) buildParams += string(name: 'USER_PATH', value: "${configuration.path}");
            if (configuration.containsKey('configureArgs')) buildParams += string(name: 'CONFIGURE_ARGS', value: "${configuration.configureArgs}");
            if (configuration.containsKey('xCodeSwitchPath')) buildParams += string(name: 'XCODE_SWITCH_PATH', value: "${configuration.xCodeSwitchPath}");
            if (configuration.containsKey('buildArgs')) buildParams += string(name: 'BUILD_ARGS', value: "${configuration.buildArgs}");

            target.value.each { variant ->
                def parameters = buildParams.clone();
                parameters += string(name: 'VARIANT', value: "${variant}");

                def name = "${buildType}-${variant}"

                jobConfigurations[name] = [
                        config     : configuration,
                        targetLabel: target.key,
                        parameters : parameters,
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
                    buildJobs[configuration.key] = build job: "openjdk_build_refactor", parameters: configuration.value.parameters
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

                        copyArtifacts(
                                projectName: 'openjdk_build_refactor',
                                selector: specific("${job.getNumber()}"),
                                filter: 'workspace/target/*',
                                fingerprintArtifacts: true,
                                target: "target/${configuration.targetLabel}/${configuration.config.arch}/",
                                flatten: true)
                    }
            }

            archiveArtifacts artifacts: 'target/*/*/*'
        }
    }
}
