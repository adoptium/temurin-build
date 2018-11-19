import groovy.json.JsonOutput
import groovy.json.JsonSlurper

/*
Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

     https://www.apache.org/licenses/LICENSE-2.0

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
 * 1. Generate job for each configuration based on  create_job_from_template.groovy
 * 2. Execute job
 * 3. Push generated artifacts to github
 */

def toBuildParams(enableTests, cleanWorkspace, params) {

    List buildParams = []

    buildParams += [$class: 'LabelParameterValue', name: 'NODE_LABEL', label: params.get("NODE_LABEL")]
    buildParams += string(name: "ENABLE_TESTS", value: "${enableTests}")
    buildParams += string(name: "CLEAN_WORKSPACE", value: "${cleanWorkspace}")

    params
            .findAll { it.key != 'NODE_LABEL' }
            .each { name, value -> buildParams += string(name: name, value: value) }

    return buildParams
}

static
def buildConfiguration(javaToBuild, variant, configuration, releaseTag, branch, additionalConfigureArgs, additionalBuildArgs) {

    def additionalNodeLabels = formAdditionalNodeLabels(configuration, variant)

    def buildParams = [
            JAVA_TO_BUILD: javaToBuild,
            NODE_LABEL   : "${additionalNodeLabels}&&${configuration.os}&&${configuration.arch}",
            VARIANT      : variant,
            ARCHITECTURE : configuration.arch,
            TARGET_OS    : configuration.os
    ]

    if (configuration.containsKey('bootJDK')) buildParams.put("JDK_BOOT_VERSION", configuration.bootJDK)
    if (configuration.containsKey('additionalFileNameTag')) buildParams.put("ADDITIONAL_FILE_NAME_TAG", configuration.additionalFileNameTag)

    buildParams.putAll(getConfigureArgs(configuration, additionalConfigureArgs))

    def buildArgs = getBuildArgs(configuration, variant);

    if (additionalBuildArgs != null && additionalBuildArgs.length() > 0) {
        buildArgs += " " + additionalBuildArgs
    }
    buildParams.put("BUILD_ARGS", buildArgs)


    if (branch != null && branch.length() > 0) {
        buildParams.put("BRANCH", branch)
    }

    def isRelease = false
    if (releaseTag != null && releaseTag.length() > 0) {
        isRelease = true
        buildParams.put("TAG", releaseTag)
    }

    def testList = getTestList(configuration, isRelease)

    return [
            javaVersion: javaToBuild,
            arch       : configuration.arch,
            os         : configuration.os,
            variant    : variant,
            parameters : buildParams,
            test       : testList
    ]
}

static def isMap(possibleMap) {
    // hack as jenkins sandbox wont allow instanceof
    return "java.util.LinkedHashMap" == possibleMap.getClass().getName()
}


static def getBuildArgs(configuration, variant) {
    if (configuration.containsKey('buildArgs')) {
        if (isMap(configuration.buildArgs)) {
            if (configuration.buildArgs.containsKey(variant)) {
                return configuration.buildArgs.get(variant)
            }
        } else {
            return configuration.buildArgs
        }
    }

    return ""
}

static def getTestList(configuration, isRelease) {
    if (configuration.containsKey("test")) {
        def testJobType = isRelease ? "release" : "nightly"
        if (isMap(configuration.test)) {
            return configuration.test.get(testJobType)
        } else {
            return configuration.test
        }
    }
    return []
}

static def formAdditionalNodeLabels(configuration, variant) {
    def buildTag = "build"

    if (configuration.os == "windows" && variant == "openj9") {
        buildTag = "buildj9"
    } else if (configuration.arch == "s390x" && variant == "openj9") {
        buildTag = "(buildj9||build)&&openj9"
    }

    def labels = "${buildTag}"

    if (configuration.containsKey("additionalNodeLabels")) {
        def additionalNodeLabels = null

        if (isMap(configuration.additionalNodeLabels)) {
            additionalNodeLabels = configuration.additionalNodeLabels.get(variant)
        } else {
            additionalNodeLabels = configuration.additionalNodeLabels
        }
        labels = "${additionalNodeLabels}&&${labels}"
    }

    return labels
}

static def getConfigureArgs(configuration, additionalConfigureArgs) {
    def buildParams = [:]
    def configureArgs = "";

    if (configuration.containsKey('configureArgs')) configureArgs += configuration.configureArgs;
    if (additionalConfigureArgs != null && additionalConfigureArgs.length() > 0) {
        configureArgs += " " + additionalConfigureArgs
    }

    if (configureArgs.length() > 0) {
        buildParams.put("CONFIGURE_ARGS", configureArgs)
    }
    return buildParams
}

def getJobConfigurations(javaVersionToBuild, availableConfigurations, String targetConfigurations, String releaseTag, String branch, String additionalConfigureArgs, String additionalBuildArgs, String additionalFileNameTag) {
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

                if (additionalFileNameTag != null && additionalFileNameTag.length() > 0) {
                    if (configuration.containsKey('additionalFileNameTag')) {
                        configuration.additionalFileNameTag = "${configuration.additionalFileNameTag}-${additionalFileNameTag}"
                    } else {
                        configuration.additionalFileNameTag = "${additionalFileNameTag}"
                    }
                }

                jobConfigurations[name] = buildConfiguration(javaVersionToBuild, variant, configuration, releaseTag, branch, additionalConfigureArgs, additionalBuildArgs)
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

// Generate a job from template at `create_job_from_template.groovy`
def createJob(jobName, jobFolder, config, enableTests, scmVars) {

    def params = config.parameters.clone()
    params.put("JOB_NAME", jobName)
    params.put("JOB_FOLDER", jobFolder)
    params.put("TEST_CONFIG", JsonOutput.prettyPrint(JsonOutput.toJson(config)))

    params.put("GIT_URI", scmVars["GIT_URL"])
    params.put("GIT_BRANCH", scmVars["GIT_BRANCH"])

    create = jobDsl targets: "pipelines/build/create_job_from_template.groovy", ignoreExisting: false, additionalParameters: params

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

def doBuild(
        String javaVersionToBuild,
        availableConfigurations,
        String targetConfigurations,
        String enableTestsArg,
        String publishArg,
        String releaseTag,
        String branch,
        String additionalConfigureArgs,
        scmVars,
        String additionalBuildArgs,
        String additionalFileNameTag,
        String cleanWorkspaceBeforeBuild) {

    if (releaseTag == null || releaseTag == "false") {
        releaseTag = ""
    }

    def jobConfigurations = getJobConfigurations(javaVersionToBuild, availableConfigurations, targetConfigurations, releaseTag, branch, additionalConfigureArgs, additionalBuildArgs, additionalFileNameTag)
    def jobs = [:]

    def enableTests = enableTestsArg == "true"
    def publish = publishArg == "true"
    def cleanWorkspace = cleanWorkspaceBeforeBuild == "true"


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
                    createJob(jobTopName, jobFolder, config, enableTests, scmVars)

                    // execute build
                    def downstreamJob = build job: downstreamJobName, propagate: false, parameters: toBuildParams(enableTests, cleanWorkspace, config.parameters)

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
