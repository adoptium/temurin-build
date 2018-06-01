def buildConfigurations = [
        mac    : [
                os                 : 'mac',
                arch               : 'x64',
                bootJDK            : "/Users/jenkins/tools/hudson.model.JDK/JDK9.0.1",
                path               : "/Users/jenkins/ccache-3.2.4",
                xCodeSwitchPath    : "/",
                configureArgs      : "--disable-warnings-as-errors",
                aditionalNodeLabels: 'build'
        ],

        linux  : [
                os                 : 'centos6',
                arch               : 'x64',
                bootJDK            : "9",
                configureArgs      : "--disable-warnings-as-errors",
                aditionalNodeLabels: 'build'
        ],

        // Currently we have to be quite specific about which windows to use as not all of them have freetype installed
        windows: [
                os                 : 'windows',
                arch               : 'x64',
                bootJDK            : "9",
                path               : "/usr/bin:/cygdrive/c/Program Files (x86)/Microsoft Visual Studio 10.0/VC/bin/amd64/",
                configureArgs      : "--disable-warnings-as-errors --with-freetype-src=/cygdrive/c/openjdk/freetype-2.5.3 --with-toolchain-version=2013 --disable-ccache",
                aditionalNodeLabels: 'build&&win2012'
        ],

        aix    : [
                os                 : 'aix',
                arch               : 'ppc64',
                bootJDK            : "9",
                path               : "/opt/freeware/bin:/usr/local/bin:/opt/IBM/xlC/13.1.3/bin:/opt/IBM/xlc/13.1.3/bin",
                configureArgs      : "--disable-warnings-as-errors --with-memory-size=18000 --with-cups-include=/opt/freeware/include --with-extra-ldflags=-lpthread --with-extra-cflags=-lpthread --with-extra-cxxflags=-lpthread",
                buildArgs          : '--skip-freetype',
                aditionalNodeLabels: 'build',
        ],
]

def excludedConfigurations = [
        mac: ["openj9"]
]

def variants = ["hotspot", "openj9"]

def javaToBuild = "jdk10u"

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

    def jobs = []

    buildConfigurations.each { buildConfiguration ->
        def configuration = buildConfiguration.value

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

        variants.each { variant ->
            if (excludedConfigurations.containsKey(buildConfiguration.key)) {
                if (excludedConfigurations.get(buildConfiguration.key).contains(variant)) {
                    return
                }
            }

            def parameters = buildParams.clone();
            parameters += string(name: 'VARIANT', value: "${variant}");

            jobs.add([
                    config     : configuration,
                    targetLabel: buildConfiguration.key,
                    parameters : parameters,
                    name       : "${buildType}-${variant}"
            ]);
        }
    }

    def buildJobs = [:]
    def buildContexts = []

    jobs.each { job ->
        buildJobs[job.name] = {
            catchError {
                stage(job.name) {
                    def buildJob = build job: "openjdk_build_refactor", parameters: job.parameters
                    buildContexts.add(buildJob)
                }
            }
        }
    }

    try {
        parallel buildJobs
    } finally {
        node('master') {
            buildContexts.each {
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
