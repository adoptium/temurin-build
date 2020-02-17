@Library('local-lib@master')
import common.IndividualBuildConfig
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
* This file is a job that regenerates all of the build configurations in pipelines/build/openjdk*_pipeline.groovy to ensure that race
* conditions are avoided for concurrent builds. THIS IS A WIP TEST, IT WILL ALMOST CERTAINLY DIE IN JENKINS
*
* This:
* 1) Is called from regeneration_pipeline.groovy
* 2) Attempts to create downstream job dsl's using for each job configuration
*/

class Regeneration implements Serializable {
  String javaVersion
  Map<String, Map<String, ?>> buildConfigurations
  def scmVars
  def currentBuild
  def context
  def env

  /*
  * Get some basic configure args. Used when creating the IndividualBuildConfig
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

  /**
  * Builds up a node param string that defines what nodes are eligible to run the given job. Only used here as a placeholder for the BuildConfig
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
  * Create IndividualBuildConfig for jobDsl. Most of the config is not filled out since we're not actually building the downstream jobs
  * @param platformConfig
  * @param variant
  * @param javaToBuild
  */ 
  IndividualBuildConfig buildConfiguration(Map<String, ?> platformConfig, String variant, String javaToBuild) {
    try {
      def additionalNodeLabels = formAdditionalBuildNodeLabels(platformConfig, variant)

      return new IndividualBuildConfig( // final build config
        JAVA_TO_BUILD: javaToBuild,
        ARCHITECTURE: platformConfig.arch as String,
        TARGET_OS: platformConfig.os as String,
        VARIANT: variant,
        TEST_LIST: [],
        SCM_REF: "",
        BUILD_ARGS: "",
        NODE_LABEL: "${additionalNodeLabels}&&${platformConfig.os}&&${platformConfig.arch}",
        CONFIGURE_ARGS: getConfigureArgs(platformConfig, variant),
        OVERRIDE_FILE_NAME_VERSION: "",
        ADDITIONAL_FILE_NAME_TAG: "",
        JDK_BOOT_VERSION: platformConfig.bootJDK as String,
        RELEASE: false,
        PUBLISH_NAME: "",
        ADOPT_BUILD_NUMBER: "",
        ENABLE_TESTS: false,
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

    params.put("GIT_URI", "https://github.com/AdoptOpenJDK/openjdk-build.git")
    params.put("GIT_BRANCH", "master") 

    params.put("BUILD_CONFIG", config.toJson())

    def create = context.jobDsl targets: "pipelines/build/common/create_job_from_template.groovy", ignoreExisting: false, additionalParameters: params

    return create
  }

  /**
  * Queries the Jenkins API. Used to get the pipeline and downstream job details.
  * @param query
  */
  def queryJenkinsAPI(String query) {
    try {
      def parser = new JsonSlurper()
      def get = new URL(query).openConnection()
      def response = parser.parseText(get.getInputStream().getText())
      return response

    } catch (Exception e) {
      // Failed to connect to jenkins api or a parsing error occured
      context.println "[ERROR] Failure on jenkins api connection or parsing.\nError: ${e}"
      currentBuild.result = "FAILURE"
    } 
  }

  /**
  * Main function. Ran from regeneration_pipeline.groovy, this will be what jenkins will run first. 
  */ 
  @SuppressWarnings("unused")
  def regenerate() {
    def JobHelper = context.library(identifier: 'openjdk-jenkins-helper@master').JobHelper

    /*
    * Stage: Check that the pipeline isn't in inprogress or queued up. Once clear, run the regeneration job
    */
    context.stage("Check for running pipelines") {
      // Get all pipelines
      def getPipelines = queryJenkinsAPI("https://ci.adoptopenjdk.net/job/build-scripts/api/json?tree=jobs[name]&pretty=true&depth1")

      // Parse api response to only extract the pipeline jobnames
      getPipelines.jobs.name.each{ pipeline -> 
        if (pipeline.contains("pipeline") && pipeline.contains(javaVersion)) {
          Integer sleepTime = 900
          Boolean inProgress = true

          while (inProgress) {
            // Check if pipeline is in progress using api
            context.println "[INFO] Checking if ${pipeline} is running..." //e.g. openjdk8-pipeline

            def pipelineInProgress = queryJenkinsAPI("https://ci.adoptopenjdk.net/job/build-scripts/job/${pipeline}/lastBuild/api/json?pretty=true&depth1")
            inProgress = pipelineInProgress.building as Boolean

            if (inProgress) {
              context.println "[INFO] ${pipeline} is running. Sleeping for ${sleepTime} seconds while waiting for ${pipeline} to complete..."
              context.sleep sleepTime
            }

          }
          
          context.println "[SUCCESS] ${pipeline} is idle. Running regeneration job..."
        }

      }

    } // end stage

    /*
    * Stage: Regenerate all of the job configurations by job type (i.e. jdk8u-linux-x64-hotspot
    * jdk8u-linux-x64-openj9, etc.)
    */
    context.stage("Regenerate pipeline jobs") {

      // Get downstream job folder and platforms
      Map<String,List> downstreamJobs = [:]

      context.println "[INFO] Pulling downstream folders and jobs from API..."

      // i.e. jdk11u, jdk8u, etc.
      def folders = queryJenkinsAPI("https://ci.adoptopenjdk.net/job/build-scripts/job/jobs/api/json?tree=jobs[name]&pretty=true&depth=1")

      folders.jobs.name.each { folder -> 
        if ((folder == "jdk" && javaVersion == "jdk15") || folder.contains(javaVersion)) {
          def jobs = [] // clean out array each time to avoid duplication

          // i.e. jdk8u-linux-x64-hotspot, jdk8u-mac-x64-openj9, etc.
          def platforms = queryJenkinsAPI("https://ci.adoptopenjdk.net/job/build-scripts/job/jobs/job/${folder}/api/json?tree=jobs[name]&pretty=true&depth=1")

          platforms.jobs.name.each { job -> 
            jobs.add(job)
          }

          downstreamJobs.put(folder, jobs)
        }

      }

      // Output for user verification
      context.println "[INFO] Jobs to be regenerated (they should only be $javaVersion jobs!):"
      downstreamJobs.each { folder, jobs -> context.println "${folder}: ${jobs}\n" }

      // Regenerate each job, running through map a job at a time
      downstreamJobs.each { folder ->
        context.println "[INFO] Regenerating Folder: $folder.key" 

        for (def job in downstreamJobs.get(folder.key)) {

          // Parse the downstream jobs to create keys that match up with the buildConfigurations in the pipeline file
          context.println "[INFO] Parsing ${job}..."
          def buildConfigurationKey

          // Split job down to version, platform, arch and variant to construct buildConfigurationKey
          // i.e. jdk8u(javaToBuild)-linux(os)-x64(arch)-openj9(variant)
          List configs = job.split("-")

          def javaToBuild = folder.key
          def os = configs[1]

          // Account for freebsd builds (not currently in the config files, remove this if this changes)
          // i.e. jdk11u-freebsd-x64-hotspot
          if (os == "freebsd") {
            context.println "[WARNING] freebsd does not currently have a configuration in the pipeline files. Skipping regeneration (remove this statement in https://github.com/AdoptOpenJDK/openjdk-build if this changes)..."
            continue
          }
          
          def variant // has to be declared early for loop perm reasons 

          switch(configs[2]) {
            case "x86":
              // Account for x86-32 builds
              // i.e. jdk8u-windows-x86-32-hotspot
              def arch = "${configs[2]}-${configs[3]}"
              variant = configs[4]
              context.println "Version: ${javaToBuild}\nPlatform: ${os}\nArchitecture: ${arch}\nVariant: ${variant}"

              buildConfigurationKey = "x${configs[3]}${os.capitalize()}" // x32Windows is the target key

              break
            default:
              def arch = configs[2]
              variant = configs[3]

              if (configs[4] != null) {
                // Account for large heap builds
                // i.e. jdk8u-linux-ppc64le-openj9-linuxXL
                def lrgHeap = configs[4]
                context.println "Version: ${javaToBuild}\nPlatform: ${os}\nArchitecture: ${arch}\nVariant: ${variant}\nAdditional Tag: ${lrgHeap}"

                buildConfigurationKey = "${arch}${os.capitalize()}XL" // ppc64leLinuxXL is a target key
              } else if (configs[2] == "arm") {
                // Account for arm32 builds
                // i.e. jdk8u-linux-arm-hotspot
                context.println "Version: ${javaToBuild}\nPlatform: ${os}\nArchitecture: ${arch}32\nVariant: ${variant}"

                buildConfigurationKey = "${arch}32${os.capitalize()}" // arm32Linux is a target key
              } else {
                // All other builds
                context.println "Version: ${javaToBuild}\nPlatform: ${os}\nArchitecture: ${arch}\nVariant: ${variant}"

                buildConfigurationKey = "${arch}${os.capitalize()}"
              }

              break
          }

          // Build job configuration from buildConfigurationKey
          context.println "[INFO] ${buildConfigurationKey} is regenerating..."

          Map<String, IndividualBuildConfig> jobConfigurations = [:]
          String name = null

          // Construct configuration for downstream job
          Boolean keyFound = false
          buildConfigurations.keySet().each { key ->  
            if (key == buildConfigurationKey) {
              //For build type, generate a configuration
              context.println "[INFO] FOUND MATCH! Configuration Key: ${key} and buildConfigurationKey: ${buildConfigurationKey}"
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
            context.println "[WARNING] buildConfigurationKey: ${buildConfigurationKey} not recognised. Valid configuration keys for folder: ${folder.key} are ${buildConfigurations.keySet()}.\n[WARNING] ${buildConfigurationKey} WILL NOT BE REGENERATED!"
            currentBuild.result = "UNSTABLE"
          } else {
            // Make job
            if (jobConfigurations.get(name) != null) {
              IndividualBuildConfig config = jobConfigurations.get(name)

              // jdk8u-linux-x64-hotspot
              def jobTopName = "${javaToBuild}-${name}"
              def jobFolder = "build-scripts/jobs/${javaToBuild}"

              // i.e jdk8u/jobs/jdk8u-linux-x64-hotspot
              def downstreamJobName = "${jobFolder}/${jobTopName}"
              context.println "[INFO] build name: ${downstreamJobName}"

              // Job dsl
              createJob(jobTopName, jobFolder, config)

              // Job regenerated correctly
              context.println "[SUCCESS] Regenerated configuration for job $downstreamJobName\n"
            }
            else {
              // Unexpected error when building or getting the configuration
              context.println "[ERROR] IndividualBuildConfig is malformed for key: ${buildConfigurationKey}."
              currentBuild.result = "FAILURE"
            }
          }

        } // end job for loop

        context.println "[SUCCESS] ${folder.key} folder regenerated!\n"
      } // end folder foreach loop

    } // end stage

  } // end regenerate()

}

return {
  String javaVersion,
  Map<String, Map<String, ?>> buildConfigurations,
  def scmVars,
  def currentBuild,
  def context,
  def env -> 

      return new Regeneration(
              javaVersion: javaVersion,
              buildConfigurations: buildConfigurations,
              scmVars: scmVars,
              currentBuild: currentBuild,
              context: context,
              env: env
      )

}