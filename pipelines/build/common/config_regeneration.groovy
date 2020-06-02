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
* This file is a job that regenerates all of the build configurations in pipelines/build/jobs/configurations/jdk*_pipeline_config.groovy. This
* ensures that race conditions are not encountered when running concurrent pipeline builds.
*
* This:
* 1) Is called from regeneration_pipeline.groovy
* 2) Attempts to create downstream job dsl's for each pipeline job configuration
*/
class Regeneration implements Serializable {
  private final String javaVersion
  private final Map<String, Map<String, ?>> buildConfigurations
  private final def currentBuild
  private final def context

  private final def jobRootDir
  private final def gitUri
  private final def gitBranch

  private final def jenkinsBuildRoot

  private def javaToBuild
  private def variant

  public Regeneration(String javaVersion, Map<String, Map<String, ?>> buildConfigurations, currentBuild, context,
                      String jobRootDir, String gitUri, String gitBranch, String jenkinsBuildRoot) {
    this.javaVersion = javaVersion
    this.buildConfigurations = buildConfigurations
    this.currentBuild = currentBuild
    this.context = context
    this.jobRootDir = jobRootDir
    this.gitUri = gitUri
    this.gitBranch = gitBranch
    this.jenkinsBuildRoot = jenkinsBuildRoot
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

  /**
  * Builds up a node param string that defines what nodes are eligible to run the given job. Only used here as a placeholder.
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
  * Get the list of tests from jdk*_pipeline_config.groovy. Used when creating the IndividualBuildConfig. Used as a placeholder since we're not
  * actually running the tests here.
  * @param configuration
  * @param variant
  */
  List<String> getTestList(Map<String, ?> configuration) {
    if (configuration.containsKey("test")) {
        if (isMap(configuration.test)) {
            return (configuration.test as Map).get("nightly") as List<String> // no need to check for release
        } else {
            return configuration.test as List<String>
        }
    }
    return []
  }

  /*
  * Create IndividualBuildConfig for jobDsl. Used as a placeholder since we're not
  * actually building here.
  * @param platformConfig
  * @param variant
  * @param javaToBuild
  */
  IndividualBuildConfig buildConfiguration(Map<String, ?> platformConfig, String variant, String javaToBuild) {
    try {
      def additionalNodeLabels = formAdditionalBuildNodeLabels(platformConfig, variant)

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
        CONFIGURE_ARGS: getConfigureArgs(platformConfig, variant),
        OVERRIDE_FILE_NAME_VERSION: "",
        ADDITIONAL_FILE_NAME_TAG: platformConfig.additionalFileNameTag as String,
        JDK_BOOT_VERSION: platformConfig.bootJDK as String,
        RELEASE: false,
        PUBLISH_NAME: "",
        ADOPT_BUILD_NUMBER: "",
        ENABLE_TESTS: true,
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
  * Parse downstream jobs to create keys that match up with the buildConfigurations in the config file
  * @param folderName
  * @param downstreamJob
  */
  def parseJob (String folderName, String downstreamJob) {

    // Split downstreamJob down to version, platform, arch and variant to construct buildConfigurationKey
    // i.e. jdk8u(javaToBuild)-linux(os)-x64(arch)-openj9(variant)
    def configKey = null
    List configs = downstreamJob.split("-")

    // Account for freebsd builds (not currently in the config files, remove this if that changes)
    // i.e. jdk11u-freebsd-x64-hotspot
    def os = configs[1]
    if (os == "freebsd") {
      context.println "[WARNING] freebsd does not currently have a configuration in the pipeline files. Skipping regeneration (remove this statement in https://github.com/AdoptOpenJDK/openjdk-build if this changes)..."
      return "freebsd"
    }

    switch(configs[2]) {
      case "x86":
        // Account for x86-32 builds
        // i.e. jdk8u-windows-x86-32-hotspot
        def arch = "${configs[2]}-${configs[3]}"
        variant = configs[4]
        context.println "Version: ${folderName}\nPlatform: ${os}\nArchitecture: ${arch}\nVariant: ${variant}"

        configKey = "x${configs[3]}${os.capitalize()}" // x32Windows is the target key

        break
      default:
        def arch = configs[2]
        variant = configs[3]

        if (configs[4] != null) {
          // Account for large heap builds
          // i.e. jdk8u-linux-ppc64le-openj9-linuxXL
          def lrgHeap = configs[4]
          context.println "Version: ${folderName}\nPlatform: ${os}\nArchitecture: ${arch}\nVariant: ${variant}\nAdditional Tag: ${lrgHeap}"

          configKey = "${arch}${os.capitalize()}XL" // ppc64leLinuxXL is a target key
        } else if (configs[2] == "arm") {
          // Account for arm32 builds
          // i.e. jdk8u-linux-arm-hotspot
          context.println "Version: ${folderName}\nPlatform: ${os}\nArchitecture: ${arch}32\nVariant: ${variant}"

          configKey = "${arch}32${os.capitalize()}" // arm32Linux is a target key
        } else {
          // All other builds
          context.println "Version: ${folderName}\nPlatform: ${os}\nArchitecture: ${arch}\nVariant: ${variant}"

          configKey = "${arch}${os.capitalize()}"
        }

        break
    }

    return configKey
  }

  /**
  * Make downstream job
  * @param jobConfig
  * @param jobName
  */
  def makeJob (def jobConfig, def jobName) {
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
  * Main function. Ran from regeneration_pipeline.groovy, this will be what jenkins will run first.
  */
  @SuppressWarnings("unused")
  def regenerate() {

    /*
    * Stage: Check that the pipeline isn't in inprogress or queued up. Once clear, run the regeneration job
    */
    context.stage("Check $javaVersion pipeline status") {

      // Get all pipelines
      def getPipelines = queryJenkinsAPI("${jenkinsBuildRoot}/api/json?tree=jobs[name]&pretty=true&depth1")

      // Parse api response to only extract the relevant pipeline
      getPipelines.jobs.name.each{ pipeline ->
        if (pipeline.contains("pipeline") && pipeline.contains(javaVersion)) {
          Integer sleepTime = 900
          Boolean inProgress = true

          while (inProgress) {
            // Check if pipeline is in progress using api
            context.println "[INFO] Checking if ${pipeline} is running..." //i.e. openjdk8-pipeline

            def pipelineInProgress = queryJenkinsAPI("${jenkinsBuildRoot}/job/${pipeline}/lastBuild/api/json?pretty=true&depth1")
            inProgress = pipelineInProgress.building as Boolean

            if (inProgress) {
              // Sleep for a bit, then check again...
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
    context.stage("Regenerate $javaVersion pipeline jobs") {

      // Get downstream job folder and platforms
      Map<String,List> downstreamJobs = [:]

      // i.e. jdk11u, jdk8u, etc.
      context.println "[INFO] Pulling downstream folders and jobs from API..."
      def folders = queryJenkinsAPI("${jenkinsBuildRoot}/job/jobs/api/json?tree=jobs[name]&pretty=true&depth=1")

      folders.jobs.name.each { folder ->
        if ((folder == "jdk" && javaVersion == "jdk15") || folder.contains(javaVersion)) {
          def jobs = [] // clean out array each time to avoid duplication

          // i.e. jdk8u-linux-x64-hotspot, jdk8u-mac-x64-openj9, etc.
          def platforms = queryJenkinsAPI("${jenkinsBuildRoot}/job/jobs/job/${folder}/api/json?tree=jobs[name]&pretty=true&depth=1")

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

          // Parse downstream jobs to create keys that match up with the buildConfigurations in the config file
          context.println "[INFO] Parsing ${job}..."
          javaToBuild = folder.key

          def buildConfigurationKey = parseJob(javaToBuild, job)

          if (buildConfigurationKey == "freebsd") { continue }

          context.println "[INFO] ${buildConfigurationKey} is regenerating..."

          // Construct configuration for downstream job
          Map<String, IndividualBuildConfig> jobConfigurations = [:]
          String name = null
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
            context.println "[WARNING] buildConfigurationKey: ${buildConfigurationKey} not recognised. Valid configuration keys for folder: ${folder.key} are ${buildConfigurations.keySet()}.\n[WARNING] ${buildConfigurationKey} WILL NOT BE REGENERATED! Setting build result to UNSTABLE..."
            currentBuild.result = "UNSTABLE"
          } else {
            // Make job
            if (jobConfigurations.get(name) != null) {
              makeJob(jobConfigurations, name)
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
  def currentBuild,
  def context,
  String jobRootDir,
  String gitUri,
  String gitBranch,
  String jenkinsBuildRoot
    ->
    if (jobRootDir == null) jobRootDir = "build-scripts";
    if (gitUri == null) gitUri = "https://github.com/AdoptOpenJDK/openjdk-build.git";
    if (gitBranch == null) gitBranch = "master";
    if (jenkinsBuildRoot == null) jenkinsBuildRoot = "https://ci.adoptopenjdk.net/job/build-scripts/";

    return new Regeneration(javaVersion, buildConfigurations, currentBuild, context, jobRootDir, gitUri, gitBranch, jenkinsBuildRoot)
}