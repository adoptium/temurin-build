def buildConfigurations = [
        mac    : [
                os                 : 'mac',
                arch               : 'x64',
                bootJDK            : "/Users/jenkins/tools/hudson.model.JDK/JDK9.0.1",
                path               : "/Users/jenkins/ccache-3.2.4",
                xCodeSwitchPath    : "/",
                configureArgs      : "--disable-warnings-as-errors",
                aditionalNodeLabels: 'x64&&build'
        ],

        linux  : [
                os                 : 'centos6',
                arch               : 'x64',
                bootJDK            : "9",
                configureArgs      : "--disable-warnings-as-errors",
                aditionalNodeLabels: 'x64&&build'
        ],

        // Currently we have to be quite specific about which windows to use as not all of them have freetype installed
        windows: [
                os                 : 'windows',
                arch               : 'x64',
                bootJDK            : "9",
                path               : "/usr/bin:/cygdrive/c/Program Files (x86)/Microsoft Visual Studio 10.0/VC/bin/amd64/",
                configureArgs      : "--disable-warnings-as-errors --with-freetype-src=/cygdrive/c/openjdk/freetype-2.5.3 --with-toolchain-version=2013 --disable-ccache",
                aditionalNodeLabels: 'build&&x64&&win2012'
        ]
]

if (osTarget != "all") {
    buildConfigurations = buildConfigurations
            .findAll { it.key == osTarget }
}

doBuild("jdk10u", buildConfigurations)

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
                stage("archive-${buildType}") {
                    archiveArtifacts artifacts: 'workspace/target/*'
                }
            }
        }
    }
    parallel jobs
}

