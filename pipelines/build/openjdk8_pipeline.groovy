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
                configureArgs      : "with_freetype=/cygdrive/C/Projects/OpenJDK/freetype  --disable-ccache",
                aditionalNodeLabels: 'win2008'
        ],

        aix    : [
                os                 : 'aix',
                arch               : 'ppc64',
                bootJDK            : "7",
                path               : "/opt/freeware/bin:/usr/local/bin:/opt/IBM/xlC/13.1.3/bin:/opt/IBM/xlc/13.1.3/bin",
                configureArgs      : "--with-memory-size=18000 --with-cups-include=/opt/freeware/include --with-extra-ldflags=-lpthread --with-extra-cflags=-lpthread --with-extra-cxxflags=-lpthread",
                buildArgs          : '--skip-freetype',
                aditionalNodeLabels: 'build',
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

                if(target.key == "windows" && variant == "openj9") {
                    configuration.aditionalNodeLabels = configuration.aditionalNodeLabels.replace("build", "buildj9")
                }

                def buildParams = [
                        string(name: 'JAVA_TO_BUILD', value: "${javaToBuild}"),
                        [$class: 'LabelParameterValue', name: 'NODE_LABEL', label: "${configuration.aditionalNodeLabels}&&${configuration.os}&&${configuration.arch}"]
                ];

                if (configuration.containsKey('bootJDK')) buildParams += string(name: 'JDK_BOOT_VERSION', value: "${configuration.bootJDK}");
                if (configuration.containsKey('path')) buildParams += string(name: 'USER_PATH', value: "${configuration.path}");
                if (configuration.containsKey('configureArgs')) buildParams += string(name: 'CONFIGURE_ARGS', value: "${configuration.configureArgs}");
                if (configuration.containsKey('xCodeSwitchPath')) buildParams += string(name: 'XCODE_SWITCH_PATH', value: "${configuration.xCodeSwitchPath}");
                if (configuration.containsKey('buildArgs')) buildParams += string(name: 'BUILD_ARGS', value: "${configuration.buildArgs}");

                buildParams += string(name: 'VARIANT', value: "${variant}");

                def name = "${buildType}-${variant}"

                jobConfigurations[name] = [
                        config     : configuration,
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

