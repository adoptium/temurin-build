def buildConfigurations = [
        mac    : [
                os                 : 'mac',
                arch               : 'x64',
                bootJDK            : "7",
                xCodeSwitchPath    : "/Applications/Xcode.app",
                aditionalNodeLabels: 'build'
        ],

        linux  : [
                os                 : 'centos6',
                arch               : 'x64',
                bootJDK            : "7",
                aditionalNodeLabels: 'build'
        ],

        // Currently we have to be quite specific about which windows to use as not all of them have freetype installed
        windows: [
                os                 : 'windows',
                arch               : 'x64',
                bootJDK            : "7",
                path               : "/cygdrive/c/Program Files (x86)/Microsoft Visual Studio 10.0/VC/bin/amd64/:/cygdrive/C/Projects/OpenJDK/make-3.82/",
                configureArgs      : "with_freetype=/cygdrive/C/Projects/OpenJDK/freetype --disable-ccache",
                buildArgs          : "--tmp-space-build",
                aditionalNodeLabels: 'build&&win2008'
        ]
]

if (osTarget != "all") {
    buildConfigurations = buildConfigurations
            .findAll { it.key == osTarget }
}

doBuild("jdk8u", buildConfigurations)

///////////////////////////////////////////////////
//Do build is the same for all pipelines
//TODO: make it a shared library
def doBuild(javaToBuild, buildConfigurations) {
    if (osTarget != "all") {
        buildConfigurations = buildConfigurations
                .findAll { it.key == osTarget }
    }

    def buildJobs = []
    def jobs = [:]

    buildConfigurations.each { buildConfiguration ->
        def configuration = buildConfiguration.value

        def buildType = "${configuration.os}-${configuration.arch}"

        jobs[buildType] = {

            catchError {
                stage("build-${buildType}") {
                    def buildParams = [
                            string(name: 'JAVA_TO_BUILD', value: "${javaToBuild}"),
                            [$class: 'LabelParameterValue', name: 'NODE_LABEL', label: "${configuration.aditionalNodeLabels}&&${configuration.os}&&${configuration.arch}"]
                    ];

                    if (configuration.containsKey('bootJDK')) buildParams += string(name: 'JDK_BOOT_VERSION', value: "${configuration.bootJDK}");
                    if (configuration.containsKey('path')) buildParams += string(name: 'USER_PATH', value: "${configuration.path}");
                    if (configuration.containsKey('configureArgs')) buildParams += string(name: 'CONFIGURE_ARGS', value: "${configuration.configureArgs}");
                    if (configuration.containsKey('xCodeSwitchPath')) buildParams += string(name: 'XCODE_SWITCH_PATH', value: "${configuration.xCodeSwitchPath}");
                    if (configuration.containsKey('buildArgs')) buildParams += string(name: 'BUILD_ARGS', value: "${configuration.buildArgs}");

                    def buildJob = build job: "openjdk_build_refactor", parameters: buildParams


                    buildJobs.add([
                            job        : buildJob,
                            config     : configuration,
                            targetLabel: buildConfiguration.key
                    ]);
                }
            }

        }
    }
    try {
        parallel jobs
    } finally {
        node('linux&&build') {
            buildJobs.each {
                buildJob ->
                    if (buildJob.job.getResult() == 'SUCCESS') {
                        copyArtifacts(
                                projectName: 'openjdk_build_refactor',
                                selector: specific("${buildJob.job.getNumber()}"),
                                filter: 'workspace/target/*',
                                fingerprintArtifacts: true,
                                target: "target/${buildJob.targetLabel}/${buildJob.config.arch}/",
                                flatten: true)
                    }
            }

            archiveArtifacts artifacts: 'target/*/*/*'
        }
    }
}
