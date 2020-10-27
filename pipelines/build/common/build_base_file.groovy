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
    String activeNodeTimeout
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

    final List<String> nightly = [
        'sanity.openjdk',
        'sanity.system',
        'extended.system',
        'sanity.perf',
        'sanity.external'
    ]
    
    // Temporarily remove weekly tests due to lack of machine capacity during release
    final List<String> weekly = []
    /*
    final List<String> weekly = [
        'extended.openjdk',
        'extended.perf',
        'extended.external',
        'special.openjdk',
        'special.functional',
        'special.system',
        'special.perf'
    ]
    */
    
    /*
    Returns an IndividualBuildConfig that is passed down to the downstream job.
    It uses several helper functions to pull in and parse the build configuration for the job.
    This overrides the default IndividualBuildConfig generated in config_regeneration.groovy.
    */
    IndividualBuildConfig buildConfiguration(Map<String, ?> platformConfig, String variant) {

        def additionalNodeLabels = formAdditionalBuildNodeLabels(platformConfig, variant)

        def dockerImage = getDockerImage(platformConfig, variant)

        def dockerFile = getDockerFile(platformConfig, variant)

        def dockerNode = getDockerNode(platformConfig, variant)

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
                ACTIVE_NODE_TIMEOUT: activeNodeTimeout,
                CODEBUILD: platformConfig.codebuild as Boolean,
                DOCKER_IMAGE: dockerImage,
                DOCKER_FILE: dockerFile,
                DOCKER_NODE: dockerNode,
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

    /*
    Returns true if possibleMap is a Map. False otherwise. 
    */
    static def isMap(possibleMap) {
        return Map.class.isInstance(possibleMap)
    }


    /*
    Retrieves the buildArgs attribute from the build configurations.
    These eventually get passed to ./makejdk-any-platform.sh and make images.
    */
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
    
    /*
    Get the list of tests to run from the build configurations.
    We run different test categories depending on if this build is a release or nightly. This function parses and applies this to the individual build config.
    */
    List<String> getTestList(Map<String, ?> configuration) {
        List<String> testList = []
        /* 
        * No test key or key value is test: false  --- test disabled
        * Key value is test: 'default' --- nightly build trigger 'nightly' test set, release build trigger 'nightly' + 'weekly' test sets
        * Key value is test: [customized map] specified nightly and weekly test lists
        */
        if (configuration.containsKey("test") && configuration.get("test")) {
            def testJobType = release ? "release" : "nightly"

            if (isMap(configuration.test)) {

                if ( testJobType == "nightly" ) {
                    testList = (configuration.test as Map).get("nightly") as List<String>
                } else {
                    testList = ((configuration.test as Map).get("nightly") as List<String>) + ((configuration.test as Map).get("weekly") as List<String>)
                }

            } else {
                
                // Default to the test sets declared if one isn't set in the build configuration
                if ( testJobType == "nightly" ) {
                    testList = nightly
                } else {
                    testList = nightly + weekly
                }

            }
        }

        testList.unique()
        return testList
    }

    /*
    Parses and applies the dockerExcludes parameter.
    Any platforms/variants that are declared in this parameter are marked as excluded from docker building via this function. Even if they have a docker image or file declared in the build configurations!
    */
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

    /*
    Retrieves the dockerImage attribute from the build configurations.
    This specifies the DockerHub org and image to pull or build in case we don't have one stored in this repository.
    If this isn't specified, the openjdk_build_pipeline.groovy will assume we are not building the jdk inside of a container.
    */
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

    /*
    Retrieves the dockerFile attribute from the build configurations.
    This specifies the path of the dockerFile relative to this repository.
    If a dockerFile is not specified, the openjdk_build_pipeline.groovy will attempt to pull one from DockerHub.
    */
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

    /*
    Retrieves the dockerNode attribute from the build configurations.
    This determines what the additional label will be if we are building the jdk in a docker container.
    Defaults to &&dockerBuild in openjdk_build_pipeline.groovy if it's not supplied in the build configuration.
    */
    def getDockerNode(Map<String, ?> configuration, String variant) {
        def dockerNodeValue = ""
        if (configuration.containsKey("dockerNode")) {
            if (isMap(configuration.dockerNode)) {
                dockerNodeValue = (configuration.dockerNode as Map<String, ?>).get(variant)
            } else {
                dockerNodeValue = configuration.dockerNode
            }
        }
        return dockerNodeValue
    }

    /*
    Constructs any necessary additional build labels from the build configurations.
    This builds up a node param string that defines what nodes are eligible to run the given job.
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

    /*
    Retrieves the configureArgs attribute from the build configurations.
    These eventually get passed to ./makejdk-any-platform.sh and bash configure.
    */
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

    /*
    Imports the build configurations for the target version based off its key and variant.
    E.g. { "x64Linux" : [ "hotspot", "openj9" ] }
    */
    Map<String, IndividualBuildConfig> getJobConfigurations() {
        Map<String, IndividualBuildConfig> jobConfigurations = [:]

        //Parse nightly config passed to jenkins job
        targetConfigurations
                .each { target ->

                    //For each requested build type, generate a configuration
                    if (buildConfigurations.containsKey(target.key)) {
                        def platformConfig = buildConfigurations.get(target.key) as Map<String, ?>

                        target.value.each { variant ->
                            // Construct a rough job name from the build config and variant
                            String name = "${platformConfig.os}-${platformConfig.arch}-${variant}"

                            if (platformConfig.containsKey('additionalFileNameTag')) {
                                name += "-${platformConfig.additionalFileNameTag}"
                            }

                            // Fill in the name's value with an IndividualBuildConfig
                            jobConfigurations[name] = buildConfiguration(platformConfig, variant)
                        }
                    }
                }

        return jobConfigurations
    }

    /*
    Returns the java version number for this pipeline (e.g. 8, 11, 15, 16)
    */
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


    /*
    Returns the release tool version string to use in the release job
    */
    def determineReleaseToolRepoVersion() {
        def number = getJavaVersionNumber()

        return "jdk${number}"
    }

    /*
    Returns the job name of the target downstream job
    */
    def getJobName(displayName) {
        return "${javaToBuild}-${displayName}"
    }

    /*
    Returns the jenkins folder of where it's assumed the downstream build jobs have been regenerated
    */
    def getJobFolder() {
        def parentDir = currentBuild.fullProjectName.substring(0, currentBuild.fullProjectName.lastIndexOf("/"))
        return parentDir + "/jobs/" + javaToBuild
    }

    /*
    Ensures that we don't release multiple variants at the same time
    */
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

    /* 
    Call job to push artifacts to github. Usually it's only executed on a nightly build
    */
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

    /*
    Main function. This is what is executed remotely via the openjdkxx-pipeline and pr tester jobs
    */
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

                // i.e jdk11u/job/jdk11u-linux-x64-hotspot
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
          // Don't publish release automatically
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
    String activeNodeTimeout,
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
            activeNodeTimeout: activeNodeTimeout,
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
