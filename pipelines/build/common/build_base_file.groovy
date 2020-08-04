@Library('local-lib@master')
import common.IndividualBuildConfig
import groovy.json.*

import java.util.regex.Matcher

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
 * Represents parameters that get past to each individual build
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
//@CompileStatic(extensions = "JenkinsTypeCheckHelperExtension")
class Builder implements Serializable {
    String javaToBuild
    String adoptBuildNumber
    String overrideFileNameVersion
    String additionalBuildArgs
    String additionalConfigureArgs
    Map<String, List<String>> targetConfigurations
    Map<String, Map<String, ?>> buildConfigurations
    Map<String, List<String>> dockerExcludes
    String scmReference
    String publishName

    boolean release
    boolean publish
    boolean enableTests
    boolean enableInstallers
    boolean cleanWorkspaceBeforeBuild
    boolean propagateFailures

    def env
    def scmVars
    def context
    def currentBuild


    IndividualBuildConfig buildConfiguration(Map<String, ?> platformConfig, String variant) {

        def additionalNodeLabels = formAdditionalBuildNodeLabels(platformConfig, variant)

        def dockerImage = getDockerImage(platformConfig, variant)

        def dockerFile = getDockerFile(platformConfig, variant)

        def buildArgs = getBuildArgs(platformConfig, variant)

        if (additionalBuildArgs) {
            buildArgs += " " + additionalBuildArgs
        }

        def testList = getTestList(platformConfig)

        // Always clean on mac due to https://github.com/AdoptOpenJDK/openjdk-build/issues/1980
        def cleanWorkspace = cleanWorkspaceBeforeBuild
        if (platformConfig.os == "mac") {
            cleanWorkspace = true
        }

        return new IndividualBuildConfig(
                JAVA_TO_BUILD: javaToBuild,
                ARCHITECTURE: platformConfig.arch as String,
                TARGET_OS: platformConfig.os as String,
                VARIANT: variant,
                TEST_LIST: testList,
                SCM_REF: scmReference,
                BUILD_ARGS: buildArgs,
                NODE_LABEL: "${additionalNodeLabels}&&${platformConfig.os}&&${platformConfig.arch}",
                CODEBUILD: platformConfig.codebuild as Boolean,
                DOCKER_IMAGE: dockerImage,
                DOCKER_FILE: dockerFile,
                CONFIGURE_ARGS: getConfigureArgs(platformConfig, additionalConfigureArgs, variant),
                OVERRIDE_FILE_NAME_VERSION: overrideFileNameVersion,
                ADDITIONAL_FILE_NAME_TAG: platformConfig.additionalFileNameTag as String,
                JDK_BOOT_VERSION: platformConfig.bootJDK as String,
                RELEASE: release,
                PUBLISH_NAME: publishName,
                ADOPT_BUILD_NUMBER: adoptBuildNumber,
                ENABLE_TESTS: enableTests,
                ENABLE_INSTALLERS: enableInstallers,
                CLEAN_WORKSPACE: cleanWorkspace
        )
    }

    static def isMap(possibleMap) {
        return Map.class.isInstance(possibleMap)
    }


    String getBuildArgs(Map<String, ?> configuration, variant) {
        if (configuration.containsKey('buildArgs')) {
            if (isMap(configuration.buildArgs)) {
                Map<String, ?> buildArgs = configuration.buildArgs as Map<String, ?>
                if (buildArgs.containsKey(variant)) {
                    return buildArgs.get(variant)
                }
            } else {
                context.error("Incorrect buildArgs type")
            }
        }

        return ""
    }

    List<String> getTestList(Map<String, ?> configuration) {
        if (configuration.containsKey("test")) {
            def testJobType = release ? "release" : "nightly"
            if (isMap(configuration.test)) {
                return (configuration.test as Map).get(testJobType) as List<String>
            } else {
                return configuration.test as List<String>
            }
        }
        return []
    }

    def dockerOverride(Map<String, ?> configuration, String variant) {
        Boolean overrideDocker = false
        if (dockerExcludes == {}) {
            return overrideDocker 
        }

        String stringArch = configuration.arch as String
        String stringOs = configuration.os as String
        String estimatedKey = stringArch + stringOs.capitalize()

        if (configuration.containsKey("additionalFileNameTag")) {
            estimatedKey = estimatedKey + "XL"
        }

        if (dockerExcludes.containsKey(estimatedKey)) {

            if (dockerExcludes[estimatedKey].contains(variant)) {
                overrideDocker = true
            }

        }

        return overrideDocker
    }

    def getDockerImage(Map<String, ?> configuration, String variant) {
        def dockerImageValue = ""

        if (configuration.containsKey("dockerImage") && !dockerOverride(configuration, variant)) {
            if (isMap(configuration.dockerImage)) {
                dockerImageValue = (configuration.dockerImage as Map<String, ?>).get(variant)
            } else {
                dockerImageValue = configuration.dockerImage
            }
        }

        return dockerImageValue
    }

    def getDockerFile(Map<String, ?> configuration, String variant) {
        def dockerFileValue = ""

        if (configuration.containsKey("dockerFile") && !dockerOverride(configuration, variant)) {
            if (isMap(configuration.dockerFile)) {
                dockerFileValue = (configuration.dockerFile as Map<String, ?>).get(variant)
            } else {
                dockerFileValue = configuration.dockerFile
            }
        }

        return dockerFileValue
    }

    /**
     * Builds up a node param string that defines what nodes are eligible to run the given job
     * @param configuration
     * @param variant
     * @return
     */
    def formAdditionalBuildNodeLabels(Map<String, ?> configuration, String variant) {
        def buildTag = "build"

        if (configuration.os == "windows" && variant == "openj9") {
            buildTag = "buildj9"
        } else if (configuration.arch == "s390x" && variant == "openj9") {
            buildTag = "(buildj9||build)&&openj9"
        }

        def labels = "${buildTag}"

        if (configuration.containsKey("additionalNodeLabels")) {
            def additionalNodeLabels

            if (isMap(configuration.additionalNodeLabels)) {
                additionalNodeLabels = (configuration.additionalNodeLabels as Map<String, ?>).get(variant)
            } else {
                additionalNodeLabels = configuration.additionalNodeLabels
            }

            if (additionalNodeLabels != null) {
                labels = "${additionalNodeLabels}&&${labels}"
            }
        }

        return labels
    }

    static String getConfigureArgs(Map<String, ?> configuration, String additionalConfigureArgs, String variant) {
        def configureArgs = ""

        if (configuration.containsKey('configureArgs')) {
            def configConfigureArgs
            if (isMap(configuration.configureArgs)) {
                configConfigureArgs = (configuration.configureArgs as Map<String, ?>).get(variant)
            } else {
                configConfigureArgs = configuration.configureArgs
            }

            if (configConfigureArgs != null) {
                configureArgs += configConfigureArgs
            }
        }

        if (additionalConfigureArgs) {
            configureArgs += " " + additionalConfigureArgs
        }

        return configureArgs
    }

    Map<String, IndividualBuildConfig> getJobConfigurations() {
        Map<String, IndividualBuildConfig> jobConfigurations = [:]

        //Parse config passed to jenkins job
        targetConfigurations
                .each { target ->

                    //For each requested build type, generate a configuration
                    if (buildConfigurations.containsKey(target.key)) {
                        def platformConfig = buildConfigurations.get(target.key) as Map<String, ?>

                        target.value.each { variant ->
                            String name = "${platformConfig.os}-${platformConfig.arch}-${variant}"

                            if (platformConfig.containsKey('additionalFileNameTag')) {
                                name += "-${platformConfig.additionalFileNameTag}"
                            }

                            jobConfigurations[name] = buildConfiguration(platformConfig, variant)
                        }
                    }
                }

        return jobConfigurations
    }

    Integer getJavaVersionNumber() {
        // version should be something like "jdk8u" or "jdk" for HEAD
        Matcher matcher = javaToBuild =~ /.*?(?<version>\d+).*?/
        if (matcher.matches()) {
            return Integer.parseInt(matcher.group('version'))
        } else if ("jdk".equalsIgnoreCase(javaToBuild.trim())) {
            // Query the Adopt api to get the "tip_version"
            def JobHelper = context.library(identifier: 'openjdk-jenkins-helper@master').JobHelper
            context.println "Querying Adopt Api for the JDK-Head number (tip_version)..."

            def response = JobHelper.getAvailableReleases(context)
            int headVersion = (int) response.getAt("tip_version")
            context.println "Found Java Version Number: ${headVersion}"
            return headVersion
        } else {
            context.error("Failed to read java version '${javaToBuild}'")
            throw new Exception()
        }
    }


    def determineReleaseToolRepoVersion() {
        def number = getJavaVersionNumber()

        return "jdk${number}"
    }

    def getJobName(displayName) {
        return "${javaToBuild}-${displayName}"
    }

    def getJobFolder() {
        def parentDir = currentBuild.fullProjectName.substring(0, currentBuild.fullProjectName.lastIndexOf("/"))
        return parentDir + "/jobs/" + javaToBuild
    }

    def checkConfigIsSane(Map<String, IndividualBuildConfig> jobConfigurations) {

        if (release) {

            // Doing a release
            def variants = jobConfigurations
                    .values()
                    .collect({ it.VARIANT })
                    .unique()

            if (variants.size() > 1) {
                context.error('Trying to release multiple variants at the same time, this is unusual')
                return false
            }
        }

        return true
    }

    // Call job to push artifacts to github
    def publishBinary() {
        if (release) {
            // make sure to skip on release
            context.println("Not publishing release")
            return
        }

        def timestamp = new Date().format("yyyy-MM-dd-HH-mm", TimeZone.getTimeZone("UTC"))
        def tag = "${javaToBuild}-${timestamp}"

        if (publishName) {
            tag = publishName
        }

        context.stage("publish") {
            context.build job: 'build-scripts/release/refactor_openjdk_release_tool',
                    parameters: [
                        ['$class': 'BooleanParameterValue', name: 'RELEASE', value: release],
                        context.string(name: 'TAG', value: tag),
                        context.string(name: 'TIMESTAMP', value: timestamp),
                        context.string(name: 'UPSTREAM_JOB_NAME', value: env.JOB_NAME),
                        context.string(name: 'UPSTREAM_JOB_NUMBER', value: "${currentBuild.getNumber()}"),
                        context.string(name: 'VERSION', value: determineReleaseToolRepoVersion())
                    ]
        }
    }

    @SuppressWarnings("unused")
    def doBuild() {

        Map<String, IndividualBuildConfig> jobConfigurations = getJobConfigurations()

        if (!checkConfigIsSane(jobConfigurations)) {
            return
        }

        if (release) {
            currentBuild.setKeepLog(true)
            if (publishName) {
                currentBuild.setDisplayName(publishName)
            }
        }

        def jobs = [:]

        context.echo "Java: ${javaToBuild}"
        context.echo "OS: ${targetConfigurations}"
        context.echo "Enable tests: ${enableTests}"
        context.echo "Enable Installers: ${enableInstallers}"
        context.echo "Publish: ${publish}"
        context.echo "Release: ${release}"
        context.echo "Tag/Branch name: ${scmReference}"

          jobConfigurations.each { configuration ->
              jobs[configuration.key] = {
                IndividualBuildConfig config = configuration.value

                // jdk11u-linux-x64-hotspot
                def jobTopName = getJobName(configuration.key)
                def jobFolder = getJobFolder()

                // i.e jdk10u/job/jdk11u-linux-x64-hotspot
                def downstreamJobName = "${jobFolder}/${jobTopName}"
                context.echo "build name " + downstreamJobName

                context.catchError {
                    // Execute build job for configuration i.e jdk11u/job/jdk11u-linux-x64-hotspot
                    context.stage(configuration.key) {
                      context.echo "Created job " + downstreamJobName
                      
                      // execute build
                      def downstreamJob = context.build job: downstreamJobName, propagate: false, parameters: config.toBuildParams()

                      if (downstreamJob.getResult() == 'SUCCESS') {
                          // copy artifacts from build
                          context.node("master") {
                              context.catchError {

                                  //Remove the previous artifacts
                                  context.sh "rm target/${config.TARGET_OS}/${config.ARCHITECTURE}/${config.VARIANT}/* || true"

                                  context.copyArtifacts(
                                          projectName: downstreamJobName,
                                          selector: context.specific("${downstreamJob.getNumber()}"),
                                          filter: 'workspace/target/*',
                                          fingerprintArtifacts: true,
                                          target: "target/${config.TARGET_OS}/${config.ARCHITECTURE}/${config.VARIANT}/",
                                          flatten: true)

                                  // Checksum
                                  context.sh 'for file in $(ls target/*/*/*/*.tar.gz target/*/*/*/*.zip); do sha256sum "$file" > $file.sha256.txt ; done'

                                  // Archive in Jenkins
                                  context.archiveArtifacts artifacts: "target/${config.TARGET_OS}/${config.ARCHITECTURE}/${config.VARIANT}/*"
                              }
                          }
                      } else if (propagateFailures) {
                          context.error("Build failed due to downstream failure of ${downstreamJobName}")
                          currentBuild.result = "FAILURE"
                      }

                    }
                }
              }
          }
          context.parallel jobs

          // publish to github if needed
          // Dont publish release automatically
          if (publish && !release) {
              //During testing just remove the publish
              publishBinary()
          } else if (publish && release) {
              context.println "NOT PUBLISHING RELEASE AUTOMATICALLY"
          }

    }

}

return {
    String javaToBuild,
    Map<String, Map<String, ?>> buildConfigurations,
    String targetConfigurations,
    String dockerExcludes,
    String enableTests,
    String enableInstallers,
    String releaseType,
    String scmReference,
    String overridePublishName,
    String additionalConfigureArgs,
    def scmVars,
    String additionalBuildArgs,
    String overrideFileNameVersion,
    String cleanWorkspaceBeforeBuild,
    String adoptBuildNumber,
    String propagateFailures,
    def currentBuild,
    def context,
    def env ->

        boolean release = false
        if (releaseType == 'Release') {
            release = true
        }

        boolean publish = false
        if (releaseType == 'Nightly') {
            publish = true
        }

        String publishName = '' // This is set to a timestamp later on if undefined
        if (overridePublishName) {
            publishName = overridePublishName
        } else if (release) {
            // Default to scmReference, remove any trailing "_adopt" from the tag if present
            if (scmReference) {
                publishName = scmReference.minus("_adopt")
            }
        }

        def buildsExcludeDocker = [:]
        if (dockerExcludes != "" && dockerExcludes != null) {
            buildsExcludeDocker = new JsonSlurper().parseText(dockerExcludes) as Map
        }

        return new Builder(
            javaToBuild: javaToBuild,
            buildConfigurations: buildConfigurations,
            targetConfigurations: new JsonSlurper().parseText(targetConfigurations) as Map,
            dockerExcludes: buildsExcludeDocker,
            enableTests: Boolean.parseBoolean(enableTests),
            enableInstallers: Boolean.parseBoolean(enableInstallers),
            publish: publish,
            release: release,
            scmReference: scmReference,
            publishName: publishName,
            additionalConfigureArgs: additionalConfigureArgs,
            scmVars: scmVars,
            additionalBuildArgs: additionalBuildArgs,
            overrideFileNameVersion: overrideFileNameVersion,
            cleanWorkspaceBeforeBuild: Boolean.parseBoolean(cleanWorkspaceBeforeBuild),
            adoptBuildNumber: adoptBuildNumber,
            propagateFailures: Boolean.parseBoolean(propagateFailures),
            currentBuild: currentBuild,
            context: context,
            env: env
        )

}
