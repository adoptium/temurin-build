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
                configureArgs      : "with_freetype=/cygdrive/C/Projects/OpenJDK/freetype --with-tools-dir=/cygdrive/c/Program\\ Files\\ \\(x86\\)/Microsoft\\ Visual\\ Studio\\ 10.0/VC/bin/ --with-freetype-lib=/cygdrive/c/openjdk/freetype-2.5.3/lib64 --with-freemarker-jar=/cygdrive/c/openjdk/freemarker.jar --disable-ccache",
                aditionalNodeLabels: 'build&&win2008'
        ],
]

def excludedConfigurations = [
        mac: ["openj9"]
]

def variants = ["hotspot", "openj9"]

def javaToBuild = "jdk8u"

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

    def jobConfigurations = [:]

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

            def name = "${buildType}-${variant}"

            jobConfigurations[name] = [
                    config     : configuration,
                    targetLabel: buildConfiguration.key,
                    parameters : parameters,
                    name       : "${buildType}-${variant}"
            ]
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
