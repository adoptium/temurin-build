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

def excludedConfigurations = []

def variants = ["hotspot", "openj9"]

def javaToBuild = "jdk9"

///////////////////////////////////////////////////
//Do build is the same for all pipelines

if (osTarget != "all") {
    buildConfigurations = buildConfigurations
            .findAll { it.key == osTarget }
}

if (variant != "all") {
    variants = [variant];
}

doBuild(javaToBuild, buildConfigurations, variants, excludedConfigurations)

//TODO: make it a shared library
def doBuild(javaToBuild, buildConfigurations, variants, excludedConfigurations) {
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
            def buildParams = [
                    string(name: 'JAVA_TO_BUILD', value: "${javaToBuild}"),
                    [$class: 'LabelParameterValue', name: 'NODE_LABEL', label: "${configuration.aditionalNodeLabels}&&${configuration.os}&&${configuration.arch}"]
            ];

            if (configuration.containsKey('bootJDK')) buildParams += string(name: 'JDK_BOOT_VERSION', value: "${configuration.bootJDK}");
            if (configuration.containsKey('path')) buildParams += string(name: 'USER_PATH', value: "${configuration.path}");
            if (configuration.containsKey('configureArgs')) buildParams += string(name: 'CONFIGURE_ARGS', value: "${configuration.configureArgs}");
            if (configuration.containsKey('xCodeSwitchPath')) buildParams += string(name: 'XCODE_SWITCH_PATH', value: "${configuration.xCodeSwitchPath}");
            if (configuration.containsKey('buildArgs')) buildParams += string(name: 'BUILD_ARGS', value: "${configuration.buildArgs}");

            variants.each { variant ->
                if (excludedConfigurations.containsKey(buildConfiguration.key)) {
                    if (excludedConfigurations.get(buildConfiguration.key).contains(variant)) {
                        return
                    }
                }

                catchError {
                    stage("build-${buildType}-${variant}") {

                        def parameters = buildParams.clone();
                        parameters += string(name: 'VARIANT', value: "${variant}");
                        def buildJob = build job: "openjdk_build_refactor", parameters: parameters

                        buildJobs.add([
                                job        : buildJob,
                                config     : configuration,
                                targetLabel: buildConfiguration.key
                        ]);
                    }
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
