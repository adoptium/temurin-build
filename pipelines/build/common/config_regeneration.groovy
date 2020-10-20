@Library('local-lib@master')
import common.IndividualBuildConfig
import groovy.json.JsonSlurper
import java.util.Base64
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
This file is a job that regenerates all of the build configurations in pipelines/build/jobs/configurations/jdk*_pipeline_config.groovy. This ensures that race conditions are not encountered when running concurrent pipeline builds.

1) Its called from jdk<version>_regeneration_pipeline.groovy
2) Attempts to create downstream job dsl's for each pipeline job configuration
*/
class Regeneration implements Serializable {
    private final String javaVersion
    private final Map<String, Map<String, ?>> buildConfigurations
    private final Map<String, ?> targetConfigurations
    private final Map<String, ?> excludedBuilds
    private final def currentBuild
    private final def context

    private final def jobRootDir
    private final def gitUri
    private final def gitBranch

    private final def jenkinsBuildRoot
    private final def jenkinsUsername
    private final def jenkinsToken

    private String javaToBuild
    private final List<String> defaultTestList = ['sanity.openjdk', 'sanity.system', 'extended.system', 'sanity.perf', 'sanity.external']

    private final String excludedConst = "EXCLUDED"

    public Regeneration(
        String javaVersion,
        Map<String, Map<String, ?>> buildConfigurations,
        Map<String, ?> targetConfigurations,
        Map<String, ?> excludedBuilds,
        currentBuild,
        context,
        String jobRootDir,
        String gitUri,
        String gitBranch,
        String jenkinsBuildRoot,
        String jenkinsUsername,
        String jenkinsToken
    ) {
        this.javaVersion = javaVersion
        this.buildConfigurations = buildConfigurations
        this.targetConfigurations = targetConfigurations
        this.excludedBuilds = excludedBuilds
        this.currentBuild = currentBuild
        this.context = context
        this.jobRootDir = jobRootDir
        this.gitUri = gitUri
        this.gitBranch = gitBranch
        this.jenkinsBuildRoot = jenkinsBuildRoot
        this.jenkinsUsername = jenkinsUsername
        this.jenkinsToken = jenkinsToken
    }

    /*
    * Get configure args from jdk*_pipeline_config.groovy. Used when creating the IndividualBuildConfig.
    * @param configuration
    * @param variant
    */
    static String getConfigureArgs(Map<String, ?> configuration, String variant) {
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
        return configureArgs
    }

    def getDockerImage(Map<String, ?> configuration, String variant) {
        def dockerImageValue = ""
        if (configuration.containsKey("dockerImage")) {
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
        if (configuration.containsKey("dockerFile")) {
            if (isMap(configuration.dockerFile)) {
                dockerFileValue = (configuration.dockerFile as Map<String, ?>).get(variant)
            } else {
                dockerFileValue = configuration.dockerFile
            }
        }
        return dockerFileValue
    }

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

    /**
    * Builds up a node param string that defines what nodes are eligible to run the given job. Used as a placeholder since the pipelines overwrite this.
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

    /*
    * Get build args from jdk*_pipeline_config.groovy. Used when creating the IndividualBuildConfig.
    * @param configuration
    * @param variant
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
    * Get the list of tests from jdk*_pipeline_config.groovy. Used when creating the IndividualBuildConfig. Used as a placeholder since the pipelines overwrite this.
    * @param configuration
    */
    List<String> getTestList(Map<String, ?> configuration) {
        List<String> testList = []
        if (configuration.containsKey("test") && configuration.get("test")) {
            if (isMap(configuration.test)) {
                testList = (configuration.test as Map).get("nightly") as List<String> // no need to check for release
            }
            testList = defaultTestList
        }
        testList.unique()
        return testList
    }

    /*
    * Checks if the platform/arch/variant is in the EXCLUDES_LIST Parameter.
    * @param configuration
    * @param variant
    */
    def overridePlatform(Map<String, ?> configuration, String variant) {
        Boolean overridePlatform = false
        if (excludedBuilds == [:]) {
            return overridePlatform 
        }

        String stringArch = configuration.arch as String
        String stringOs = configuration.os as String
        String estimatedKey = stringArch + stringOs.capitalize()

        if (configuration.containsKey("additionalFileNameTag")) {
            estimatedKey = estimatedKey + "XL"
        }

        if (excludedBuilds.containsKey(estimatedKey)) {

            if (excludedBuilds[estimatedKey].contains(variant)) {
                overridePlatform = true
            }

        }

        return overridePlatform
    }

    /*
    * Create IndividualBuildConfig for jobDsl. Used as a placeholder since the pipelines overwrite this.
    * @param platformConfig
    * @param variant
    * @param javaToBuild
    */
    IndividualBuildConfig buildConfiguration(Map<String, ?> platformConfig, String variant, String javaToBuild) {
        try {

            // Check if it's in the excludes list
            if (overridePlatform(platformConfig, variant)) {
                context.println "[INFO] Excluding $platformConfig.os: $variant from $javaToBuild regeneration due to it being in the EXCLUDES_LIST..."
                return excludedConst
            }

            def additionalNodeLabels = formAdditionalBuildNodeLabels(platformConfig, variant)

            def dockerImage = getDockerImage(platformConfig, variant)

            def dockerFile = getDockerFile(platformConfig, variant)

            def dockerNode = getDockerNode(platformConfig, variant)

            def buildArgs = getBuildArgs(platformConfig, variant)

            def testList = getTestList(platformConfig)

            return new IndividualBuildConfig( // final build config
                JAVA_TO_BUILD: javaToBuild,
                ARCHITECTURE: platformConfig.arch as String,
                TARGET_OS: platformConfig.os as String,
                VARIANT: variant,
                TEST_LIST: testList,
                SCM_REF: "",
                BUILD_ARGS: buildArgs,
                NODE_LABEL: "${additionalNodeLabels}&&${platformConfig.os}&&${platformConfig.arch}",
                CODEBUILD: platformConfig.codebuild as Boolean,
                DOCKER_IMAGE: dockerImage,
                DOCKER_FILE: dockerFile,
                DOCKER_NODE: dockerNode,
                CONFIGURE_ARGS: getConfigureArgs(platformConfig, variant),
                OVERRIDE_FILE_NAME_VERSION: "",
                ADDITIONAL_FILE_NAME_TAG: platformConfig.additionalFileNameTag as String,
                JDK_BOOT_VERSION: platformConfig.bootJDK as String,
                RELEASE: false,
                PUBLISH_NAME: "",
                ADOPT_BUILD_NUMBER: "",
                ENABLE_TESTS: true,
                ENABLE_INSTALLERS: true,
                CLEAN_WORKSPACE: true
            )
        } catch (Exception e) {
            // Catch invalid configurations
            context.println "[ERROR] Failed to create IndividualBuildConfig for platformConfig: ${platformConfig}.\nError: ${e}"
            currentBuild.result = "FAILURE"
        }
    }

    /**
    * Checks if the parameter is a map
    * @param possibleMap
    */
    static def isMap(possibleMap) {
        return Map.class.isInstance(possibleMap)
    }

    /**
    * Generates a job from template at `create_job_from_template.groovy`. This is what creates the job dsl and "regenerates" the job.
    * @param jobName
    * @param jobFolder
    * @param config
    */
    def createJob(jobName, jobFolder, IndividualBuildConfig config) {
        Map<String, ?> params = config.toMap().clone() as Map
        params.put("JOB_NAME", jobName)
        params.put("JOB_FOLDER", jobFolder)

        params.put("GIT_URI", gitUri)
        params.put("GIT_BRANCH", gitBranch)

        params.put("BUILD_CONFIG", config.toJson())

        def create = context.jobDsl targets: "pipelines/build/common/create_job_from_template.groovy", ignoreExisting: false, additionalParameters: params

        return create
    }

    /**
    * Make downstream job from config and name
    * @param jobConfig
    * @param jobName
    */
    def makeJob(def jobConfig, def jobName) {
        IndividualBuildConfig config = jobConfig.get(jobName)

        // jdk8u-linux-x64-hotspot
        def jobTopName = "${javaToBuild}-${jobName}"
        def jobFolder = "${jobRootDir}/jobs/${javaToBuild}"

        // i.e jdk8u/jobs/jdk8u-linux-x64-hotspot
        def downstreamJobName = "${jobFolder}/${jobTopName}"
        context.println "[INFO] build name: ${downstreamJobName}"

        // Job dsl
        createJob(jobTopName, jobFolder, config)

        // Job regenerated correctly
        context.println "[SUCCESS] Regenerated configuration for job $downstreamJobName\n"
    }

    /**
    * Queries an API. Used to get the pipeline details
    * @param query
    */
    def queryAPI(String query) {
        try {
            def parser = new JsonSlurper()
            def get = new URL(query).openConnection()

            String jenkinsAuth = ""
            if (jenkinsUsername != "") {
                jenkinsAuth = "Basic " + new String(Base64.getEncoder().encode("$jenkinsUsername:$jenkinsToken".getBytes()))
            }
            get.setRequestProperty ("Authorization", jenkinsAuth)

            def response = parser.parseText(get.getInputStream().getText())
            return response
        } catch (Exception e) {
            // Failed to connect to jenkins api or a parsing error occured
            context.println "[ERROR] Failure on jenkins api connection or parsing.\nError: ${e}"
            currentBuild.result = "FAILURE"
        }
    }

    /**
    * Main function. Ran from jdkxx_regeneration_pipeline.groovy, this will be what jenkins will run first.
    */
    @SuppressWarnings("unused")
    def regenerate() {
        context.timestamps {
            def versionNumbers = javaVersion =~ /\d+/

            /*
            * Stage: Check that the pipeline isn't in inprogress or queued up. Once clear, run the regeneration job
            */
            context.stage("Check $javaVersion pipeline status") {

                // Get all pipelines
                def getPipelines = queryAPI("${jenkinsBuildRoot}/api/json?tree=jobs[name]&pretty=true&depth1")

                // Parse api response to only extract the relevant pipeline
                getPipelines.jobs.name.each{ pipeline ->
                    if (pipeline.contains("pipeline") && pipeline.contains(versionNumbers[0])) {
                        // TODO: Paramaterise this
                        Integer sleepTime = 900
                        
                        Boolean inProgress = true
                        while (inProgress) {
                            // Check if pipeline is in progress using api
                            context.println "[INFO] Checking if ${pipeline} is running..." //i.e. openjdk8-pipeline

                            def pipelineInProgress = queryAPI("${jenkinsBuildRoot}/job/${pipeline}/lastBuild/api/json?pretty=true&depth1")

                            // If query fails, check to see if the pipeline has been run before
                            if (pipelineInProgress == null) {
                                def getPipelineBuilds = queryAPI("${jenkinsBuildRoot}/job/${pipeline}/api/json?pretty=true&depth1")

                                if (getPipelineBuilds.builds == []) {
                                    context.println "[SUCCESS] ${pipeline} has not been run before. Running regeneration job..."
                                    inProgress = false
                                }

                            } else {
                                inProgress = pipelineInProgress.building as Boolean
                            }

                            if (inProgress) {
                                // Sleep for a bit, then check again...
                                context.println "[INFO] ${pipeline} is running. Sleeping for ${sleepTime} seconds while waiting for ${pipeline} to complete..."

                                context.sleep(time: sleepTime, unit: "SECONDS")
                            }

                        }

                        context.println "[SUCCESS] ${pipeline} is idle. Running regeneration job..."
                    }

                }

            } // end check stage

            /*
            * Stage: Regenerate all of the job configurations by job type (i.e. jdk8u-linux-x64-hotspot
            * jdk8u-linux-x64-openj9, etc.)
            */
            context.stage("Regenerate $javaVersion pipeline jobs") {

                context.println "[INFO] Jobs to be regenerated (pulled from config file):"
                targetConfigurations.each { osarch, variants -> context.println "${osarch}: ${variants}\n" }

                // If we're building jdk head, update the javaToBuild
                context.println "[INFO] Querying adopt api to get the JDK-Head number"

                def JobHelper = context.library(identifier: 'openjdk-jenkins-helper@master').JobHelper
                Integer jdkHeadNum = Integer.valueOf(JobHelper.getAvailableReleases(context).tip_version)

                if (Integer.valueOf(versionNumbers[0]) == jdkHeadNum) {
                    javaToBuild = "jdk"
                    context.println "[INFO] This IS JDK-HEAD. javaToBuild is ${javaToBuild}."
                } else {
                    javaToBuild = "${javaVersion}"
                    context.println "[INFO] This IS NOT JDK-HEAD. javaToBuild is ${javaToBuild}..."
                }

                // Regenerate each os and arch
                targetConfigurations.keySet().each { osarch ->

                    context.println "[INFO] Regenerating: $osarch"

                        for (def variant in targetConfigurations.get(osarch)) {

                            context.println "[INFO] Regenerating variant $osarch: $variant..."

                            // Construct configuration for downstream job
                            Map<String, IndividualBuildConfig> jobConfigurations = [:]
                            String name = null
                            Boolean keyFound = false

                            // Using a foreach here as containsKey doesn't work for some reason
                            buildConfigurations.keySet().each { key ->
                                if (key == osarch) {

                                    //For build type, generate a configuration
                                    context.println "[INFO] FOUND MATCH! buildConfiguration key: ${key} and config file key: ${osarch}"
                                    keyFound = true

                                    def platformConfig = buildConfigurations.get(key) as Map<String, ?>

                                    name = "${platformConfig.os}-${platformConfig.arch}-${variant}"

                                    if (platformConfig.containsKey('additionalFileNameTag')) {
                                        name += "-${platformConfig.additionalFileNameTag}"
                                    }

                                    jobConfigurations[name] = buildConfiguration(platformConfig, variant, javaToBuild)
                                }
                            }

                            if (keyFound == false) {
                                context.println "[WARNING] Config file key: ${osarch} not recognised. Valid configuration keys for ${javaToBuild} are ${buildConfigurations.keySet()}.\n[WARNING] ${osarch} WILL NOT BE REGENERATED! Setting build result to UNSTABLE..."
                                currentBuild.result = "UNSTABLE"
                            } else {
                                // Skip variant job make if it's marked as excluded
                                if (jobConfigurations.get(name) == excludedConst) {
                                    continue
                                }
                                // Make job
                                else if (jobConfigurations.get(name) != null) {
                                    makeJob(jobConfigurations, name)
                                // Unexpected error when building or getting the configuration
                                } else {
                                    context.println "[ERROR] IndividualBuildConfig is malformed for key: ${osarch}."
                                    currentBuild.result = "FAILURE"
                                }
                            }

                        } // end variant for loop

                        context.println "[SUCCESS] ${osarch} completed!\n"

                } // end key foreach loop

            } // end stage
        } // end timestamps
    } // end regenerate()

}

return {
    String javaVersion,
    Map<String, Map<String, ?>> buildConfigurations,
    Map<String, ?> targetConfigurations,
    String excludes,
    def currentBuild,
    def context,
    String jobRootDir,
    String gitUri,
    String gitBranch,
    String jenkinsBuildRoot,
    String jenkinsUsername,
    String jenkinsToken
        ->
        if (jobRootDir == null) jobRootDir = "build-scripts";
        if (gitUri == null) gitUri = "https://github.com/AdoptOpenJDK/openjdk-build.git";
        if (gitBranch == null) gitBranch = "master";
        if (jenkinsBuildRoot == null) jenkinsBuildRoot = "https://ci.adoptopenjdk.net/job/build-scripts/";
        if (jenkinsUsername == null) jenkinsUsername = ""
        if (jenkinsToken == null) jenkinsToken = ""

        def excludedBuilds = [:]
        if (excludes != "" && excludes != null) {
            excludedBuilds = new JsonSlurper().parseText(excludes) as Map
        }
        
        return new Regeneration(
            javaVersion,
            buildConfigurations,
            targetConfigurations,
            excludedBuilds,
            currentBuild,
            context,
            jobRootDir,
            gitUri,
            gitBranch,
            jenkinsBuildRoot,
            jenkinsUsername,
            jenkinsToken
        )
}
