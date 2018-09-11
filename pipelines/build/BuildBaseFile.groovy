import groovy.json.JsonOutput
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

/**
 * This file starts a high level job, it is called from openjdk8_pipeline.groovy, openjdk9_pipeline.groovy, openjdk10_pipeline.groovy.
 *
 * This:
 *
 * 1. Generate job for each configuration based on  createJobFromTemplate.groovy
 * 2. Execute job
 * 3. Push generated artifacts to github
 */

def toBuildParams(enableTests, params) {

    List buildParams = []

    buildParams += [$class: 'LabelParameterValue', name: 'NODE_LABEL', label: params.get("NODE_LABEL")]
    buildParams += string(name: "ENABLE_TESTS", value: "${enableTests}")

    params
            .findAll { it.key != 'NODE_LABEL' }
            .each { name, value -> buildParams += string(name: name, value: value) }

    return buildParams
}

static def buildConfiguration(javaToBuild, variant, configuration, releaseTag) {

    String buildTag = "build"

    if (configuration.os == "windows" && variant == "openj9") {
        buildTag = "buildj9"
    } else if (configuration.arch == "s390x" && variant == "openj9") {
        buildTag = "(buildj9||build)&&openj9"
    }

    def additionalNodeLabels = null
    if (configuration.containsKey("additionalNodeLabels")) {
        // hack as jenkins sandbox wont allow instanceof
        if ("java.util.LinkedHashMap" == configuration.additionalNodeLabels.getClass().getName()) {
            additionalNodeLabels = configuration.additionalNodeLabels.get(variant)
        } else {
            additionalNodeLabels = configuration.additionalNodeLabels
        }

    }

    if (additionalNodeLabels != null) {
        additionalNodeLabels = "${additionalNodeLabels}&&${buildTag}"
    } else {
        additionalNodeLabels = "${buildTag}"
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

def getJobConfigurations(javaVersionToBuild, availableConfigurations, String targetConfigurations, String releaseTag) {
    def jobConfigurations = [:]

    //Parse config passed to jenkins job
    new JsonSlurper()
            .parseText(targetConfigurations)
            .each { target ->

        //For each requested build type, generate a configuration
        if (availableConfigurations.containsKey(target.key)) {
            def configuration = availableConfigurations.get(target.key)
            target.value.each { variant ->
                GString name = "${configuration.os}-${configuration.arch}-${variant}"
                if (configuration.containsKey('additionalFileNameTag')) {
                    name += "-${configuration.additionalFileNameTag}"
                }
                jobConfigurations[name] = buildConfiguration(javaVersionToBuild, variant, configuration, releaseTag)
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


static def determineReleaseRepoVersion(javaToBuild) {
    def number = getJavaVersionNumber(javaToBuild)

    return "jdk${number}"
}

static def getJobName(displayName, config) {
    return "${config.javaVersion}-${displayName}"
}

static def getJobFolder(config) {
    return "build-scripts/jobs/${config.javaVersion}"
}

// Generate a job from template at `createJobFromTemplate.groovy`
def createJob(jobName, jobFolder, config, enableTests) {

    def params = config.parameters.clone()
    params.put("JOB_NAME", jobName)
    params.put("JOB_FOLDER", jobFolder)
    params.put("TEST_CONFIG", JsonOutput.prettyPrint(JsonOutput.toJson(config)))

    create = jobDsl targets: "pipelines/build/createJobFromTemplate.groovy", ignoreExisting: false, additionalParameters: params

    return create
}

// Call job to push artifacts to github
def publishRelease(javaToBuild, releaseTag) {
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

def doBuild(String javaVersionToBuild, availableConfigurations, String targetConfigurations, String enableTestsArg, String publishArg, String releaseTag) {

    if (releaseTag == null || releaseTag == "false") {
        releaseTag = ""
    }

    def jobConfigurations = getJobConfigurations(javaVersionToBuild, availableConfigurations, targetConfigurations, releaseTag)
    def jobs = [:]

    def enableTests = enableTestsArg == "true"
    def publish = publishArg == "true"


    echo "Java: ${javaVersionToBuild}"
    echo "OS: ${targetConfigurations}"
    echo "Enable tests: ${enableTests}"
    echo "Publish: ${publish}"
    echo "ReleaseTag: ${releaseTag}"


    jobConfigurations.each { configuration ->
        jobs[configuration.key] = {
            def config = configuration.value

            // jdk10u-linux-x64-hotspot
            def jobTopName = getJobName(configuration.key, config)
            def jobFolder = getJobFolder(config)

            // i.e jdk10u/job/jdk10u-linux-x64-hotspot
            def downstreamJobName = "${jobFolder}/${jobTopName}"

            catchError {
                // Execute build job for configuration i.e jdk10u/job/jdk10u-linux-x64-hotspot
                stage(configuration.key) {
                    // generate job
                    createJob(jobTopName, jobFolder, config, enableTests)

                    // execute build
                    def downstreamJob = build job: downstreamJobName, propagate: false, parameters: toBuildParams(enableTests, config.parameters)

                    if (downstreamJob.getResult() == 'SUCCESS') {
                        // copy artifacts from build
                        node("master") {
                            catchError {
                                sh "rm target/${config.os}/${config.arch}/${config.variant}/* || true"

                                copyArtifacts(
                                        projectName: downstreamJobName,
                                        selector: specific("${downstreamJob.getNumber()}"),
                                        filter: 'workspace/target/*',
                                        fingerprintArtifacts: true,
                                        target: "target/${config.os}/${config.arch}/${config.variant}/",
                                        flatten: true)

                                // Checksum
                                sh 'for file in $(ls target/*/*/*/*.tar.gz target/*/*/*/*.zip); do sha256sum "$file" > $file.sha256.txt ; done'

                                // Archive in Jenkins
                                archiveArtifacts artifacts: "target/${config.os}/${config.arch}/${config.variant}/*"
                            }
                        }
                    }
                }
            }
        }
    }

    parallel jobs

    // publish to github if needed
    if (publish) {
        publishRelease(javaVersionToBuild, releaseTag)
    }
}

return this