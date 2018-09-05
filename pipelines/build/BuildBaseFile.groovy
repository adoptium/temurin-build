import groovy.json.JsonSlurper

/*
Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

def toBuildParams(params) {

    List buildParams = []

    buildParams += [$class: 'LabelParameterValue', name: 'NODE_LABEL', label: params.get("NODE_LABEL")]

    params
            .findAll { it.key != 'NODE_LABEL' }
            .each { name, value -> buildParams += string(name: name, value: value) }

    return buildParams
}

def buildConfiguration(javaToBuild, variant, configuration, releaseTag) {

    String buildTag = "build"

    if (configuration.os == "windows" && variant == "openj9") {
        buildTag = "buildj9"
    } else if (configuration.arch == "s390x" && variant == "openj9") {
        buildTag = "(buildj9||build)&&openj9"
    }

    def additionalNodeLabels
    if (configuration.containsKey("additionalNodeLabels")) {
        // hack as jenkins sandbox wont allow instanceof
        if ("java.util.LinkedHashMap" == configuration.additionalNodeLabels.getClass().getName()) {
            additionalNodeLabels = configuration.additionalNodeLabels.get(variant)
        } else {
            additionalNodeLabels = configuration.additionalNodeLabels
        }

        additionalNodeLabels = "${additionalNodeLabels}&&${buildTag}"
    } else {
        additionalNodeLabels = buildTag
    }

    def buildParams = [
            JAVA_TO_BUILD: javaToBuild,
            NODE_LABEL   : "${additionalNodeLabels}&&${configuration.os}&&${configuration.arch}",
            VARIANT      : variant,
            ARCHITECTURE : configuration.arch,
            TARGET_OS    : configuration.os
    ]

    if (configuration.containsKey('bootJDK')) buildParams.put("JDK_BOOT_VERSION", configuration.bootJDK)
    if (configuration.containsKey('configureArgs')) buildParams.put("CONFIGURE_ARGS", configuration.configureArgs)
    if (configuration.containsKey('buildArgs')) buildParams.put("BUILD_ARGS", configuration.buildArgs)
    if (configuration.containsKey('additionalFileNameTag')) buildParams.put("ADDITIONAL_FILE_NAME_TAG", configuration.additionalFileNameTag)

    if (releaseTag != null && releaseTag.length() > 0) {
        buildParams.put("TAG", releaseTag)
    }

    return [
            javaVersion: javaToBuild,
            arch       : configuration.arch,
            os         : configuration.os,
            variant    : variant,
            parameters : buildParams,
            test       : configuration.test,
    ]
}

def getJobConfigurations(javaToBuild, buildConfigurations, String osTarget, String releaseTag) {
    def jobConfigurations = [:]

    new JsonSlurper()
            .parseText(osTarget)
            .each { target ->
        if (buildConfigurations.containsKey(target.key)) {
            def configuration = buildConfigurations.get(target.key)
            target.value.each { variant ->
                GString name = "${configuration.os}-${configuration.arch}-${variant}"
                if (configuration.containsKey('additionalFileNameTag')) {
                    name += "-${configuration.additionalFileNameTag}"
                }
                jobConfigurations[name] = buildConfiguration(javaToBuild, variant, configuration, releaseTag)
            }
        }
    }

    return jobConfigurations
}

static Integer getJavaVersionNumber(version) {
    // version should be something like "jdk8u"
    def matcher = (version =~ /(\d+)/)
    return Integer.parseInt(matcher[0][1])
}

static def determineTestJobName(config, testType) {

    def variant
    def number = getJavaVersionNumber(config.javaVersion)

    if (config.variant == "openj9") {
        variant = "j9"
    } else {
        variant = "hs"
    }

    def arch = config.arch
    if (arch == "x64") {
        arch = "x86-64"
    }

    def os = config.os
    if (os == "mac") {
        os = "macos"
    }

    return "openjdk${number}_${variant}_${testType}_${arch}_${os}"
}

static def determineReleaseRepoVersion(javaToBuild) {
    def number = getJavaVersionNumber(javaToBuild)

    return "jdk${number}"
}

def getJobName(displayName, config) {
    return "${config.javaVersion}-${displayName}"
}

def getJobFolder(config) {
    return "build-scripts/jobs/${config.javaVersion}"
}

def createJob(jobName, jobFolder, config) {

    def params = config.parameters.clone()
    params.put("JOB_NAME", jobName)
    params.put("JOB_FOLDER", jobFolder)

    create = jobDsl targets: "pipelines/build/createJobFromTemplate.groovy", ignoreExisting: true, additionalParameters: params

    return create
}

def doBuild(String javaToBuild, buildConfigurations, String osTarget, String enableTestsArg, String publishArg, String releaseTag) {

    if (releaseTag == null || releaseTag == "false") {
        releaseTag = ""
    }

    def jobConfigurations = getJobConfigurations(javaToBuild, buildConfigurations, osTarget, releaseTag)
    def jobs = [:]
    def buildJobs = [:]

    def enableTests = enableTestsArg == "true"
    def publish = publishArg == "true"


    echo "Java: ${javaToBuild}"
    echo "OS: ${osTarget}"
    echo "Enable tests: ${enableTests}"
    echo "Publish: ${publish}"
    echo "ReleaseTag: ${releaseTag}"


    jobConfigurations.each { configuration ->
        jobs[configuration.key] = {
            def job
            def config = configuration.value
            def jobTopName = getJobName(configuration.key, config)
            def jobFolder = getJobFolder(config)
            def downstreamJob = "${jobFolder}/${jobTopName}";

            catchError {
                stage(configuration.key) {
                    createJob(jobTopName, jobFolder, config);

                    job = build job: downstreamJob, propagate: false, parameters: toBuildParams(config.parameters)
                    buildJobs[configuration.key] = job
                }

                if (enableTests && config.test) {
                    if (job.getResult() == 'SUCCESS') {
                        stage("test ${configuration.key}") {
                            def testStages = [:]
                            config.test.each { testType ->
                                testStages["${configuration.key}-${testType}"] = {
                                    stage("test ${configuration.key} ${testType}") {
                                        def jobName = determineTestJobName(config, testType)
                                        catchError {
                                            build job: jobName,
                                                    propagate: false,
                                                    parameters: [string(name: 'UPSTREAM_JOB_NUMBER', value: "${job.getNumber()}"),
                                                                 string(name: 'UPSTREAM_JOB_NAME', value: downstreamJob)]
                                        }
                                    }
                                }
                            }
                            parallel testStages
                        }
                    }
                }

                node('master') {
                    def downstreamJobName = downstreamJob
                    def jobWithReleaseArtifact = job

                    if (config.os == "windows" || config.os == "mac") {
                        stage("sign ${configuration.key}") {
                            filter = ""
                            certificate = ""

                            if (config.os == "windows") {
                                filter = "**/OpenJDK*_windows_*.zip"
                                certificate = "C:\\Users\\jenkins\\windows.p12"

                            } else if (config.os == "mac") {
                                filter = "**/OpenJDK*_mac_*.tar.gz"
                                certificate = "\"Developer ID Application: London Jamocha Community CIC\""
                            }

                            signJob = build job: "build-scripts/release/sign_build",
                                    propagate: false,
                                    parameters: [string(name: 'UPSTREAM_JOB_NUMBER', value: "${job.getNumber()}"),
                                                 string(name: 'UPSTREAM_JOB_NAME', value: downstreamJob),
                                                 string(name: 'OPERATING_SYSTEM', value: "${config.os}"),
                                                 string(name: 'FILTER', value: "${filter}"),
                                                 string(name: 'CERTIFICATE', value: "${certificate}"),
                                                 [$class: 'LabelParameterValue', name: 'NODE_LABEL', label: "${config.os}&&build"],
                                    ]
                            downstreamJobName = "build-scripts/release/sign_build"
                            jobWithReleaseArtifact = signJob
                        }
                    }


                    stage("archive ${configuration.key}") {
                        if (jobWithReleaseArtifact.getResult() == 'SUCCESS') {
                            currentBuild.result = 'SUCCESS'
                            sh "rm target/${config.os}/${config.arch}/${config.variant}/* || true"

                            copyArtifacts(
                                    projectName: downstreamJobName,
                                    selector: specific("${jobWithReleaseArtifact.getNumber()}"),
                                    filter: 'workspace/target/*',
                                    fingerprintArtifacts: true,
                                    target: "target/${config.os}/${config.arch}/${config.variant}/",
                                    flatten: true)


                            sh 'for file in $(ls target/*/*/*/*.tar.gz target/*/*/*/*.zip); do sha256sum "$file" > $file.sha256.txt ; done'
                            archiveArtifacts artifacts: "target/${config.os}/${config.arch}/${config.variant}/*"
                        }

                    }
                }
            }
        }
    }

    parallel jobs

    if (publish) {
        def release = false
        def tag = javaToBuild
        if (releaseTag != null && releaseTag.length() > 0) {
            release = true
            tag = releaseTag
        }

        node("master") {
            stage("publish") {
                build job: 'build-scripts/release/refactor_openjdk_release_tool',
                        parameters: [string(name: 'RELEASE', value: "${release}"),
                                     string(name: 'TAG', value: tag),
                                     string(name: 'UPSTREAM_JOB_NAME', value: env.JOB_NAME),
                                     string(name: 'UPSTREAM_JOB_NUMBER', value: "${currentBuild.getNumber()}"),
                                     string(name: 'VERSION', value: determineReleaseRepoVersion(javaToBuild))]
            }
        }
    }
}

return this