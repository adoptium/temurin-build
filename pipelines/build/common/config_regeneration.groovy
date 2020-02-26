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
* 2) Attempts to create a new downstream job using a default configuration and will try to build it (which should fail as jdkxx does not exist)
*/

class Regeneration implements Serializable {
  String javaToBuild
  def scmVars
  def currentBuild
  def context
  def env
  Map<String, Map<String, ?>> buildConfigurations

  /*
  * Get some basic configure args. Used when creating the IndividualBuildConfig
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

  /*
  * Create IndividualBuildConfig for jobDsl 
  */ 
  IndividualBuildConfig buildConfiguration(Map<String, ?> platformConfig, String variant) {
    //def additionalNodeLabels = formAdditionalBuildNodeLabels(platformConfig, variant)
    //def additionalNodeLabels = "centos6&&build"
    def additionalNodeLabels = "centos6&&build"

    //def buildArgs = getBuildArgs(platformConfig, variant)
    def buildArgs = ""

    // if (additionalBuildArgs) {
    //     buildArgs += " " + additionalBuildArgs
    // }

    def testList = []

    return new IndividualBuildConfig( // final build config
      JAVA_TO_BUILD: javaToBuild,
      ARCHITECTURE: platformConfig.arch as String,
      TARGET_OS: platformConfig.os as String,
      VARIANT: variant,
      TEST_LIST: testList,
      SCM_REF: "",
      BUILD_ARGS: buildArgs,
      NODE_LABEL: "${additionalNodeLabels}&&${platformConfig.os}&&${platformConfig.arch}", //centos6&&build&&linux&&x64
      CONFIGURE_ARGS: getConfigureArgs(platformConfig, variant),
      OVERRIDE_FILE_NAME_VERSION: "",
      ADDITIONAL_FILE_NAME_TAG: "",
      JDK_BOOT_VERSION: platformConfig.bootJDK as String,
      RELEASE: false,
      PUBLISH_NAME: "",
      ADOPT_BUILD_NUMBER: "",
      ENABLE_TESTS: false,
      CLEAN_WORKSPACE: false
    )
  }

  /**
  * Checks if the property is a map
  */
  static def isMap(possibleMap) {
    return Map.class.isInstance(possibleMap)
  }

  // Generate a job from template at `create_job_from_template.groovy`
  def createJob(jobName, jobFolder, IndividualBuildConfig config) {
    Map<String, ?> params = config.toMap().clone() as Map
    params.put("JOB_NAME", jobName)
    params.put("JOB_FOLDER", jobFolder)

    params.put("GIT_URI", "https://github.com/AdoptOpenJDK/openjdk-build.git")
    //params.put("GIT_BRANCH", "new_build_scripts") 
    params.put("GIT_BRANCH", "master") 

    params.put("BUILD_CONFIG", config.toJson())

    def create = context.jobDsl targets: "pipelines/build/common/create_job_from_template.groovy", ignoreExisting: false, additionalParameters: params

    return create
  }

  def getJobFolder() {
    // THIS DEFAULTS TO MY TEST JOB NAME
    //def parentDir = currentBuild.fullProjectName.substring(0, currentBuild.fullProjectName.lastIndexOf("/"))
    //return parentDir + "/jobs/" + javaToBuild

    //return "build-scripts/jobs/${javaToBuild}" //i.e. build-scripts/jobs/jdkxx
    return "build-scripts/jobs/jdkxx" //i.e. build-scripts/jobs/jdkxx
  }

  /**
  * Main function. Ran from regeneration_pipeline.groovy, this will be what the jenkins regeneration job will run. 
  */ 
  @SuppressWarnings("unused")
  def regenerate() {
    // Make job configuration
    Map<String, IndividualBuildConfig> jobConfigurations = [:]

    if (buildConfigurations.containsKey("x64Linux")) {
      def platformConfig = buildConfigurations.get("x64Linux") as Map<String, ?>
      def variant = "hotspot"

      String name = "${platformConfig.os}-${platformConfig.arch}-${variant}"

      if (platformConfig.containsKey('additionalFileNameTag')) {
        name += "-${platformConfig.additionalFileNameTag}"
      }

      jobConfigurations[name] = buildConfiguration(platformConfig, variant)
    }

    // Run through configurations
    def jobs = [:]

    jobConfigurations.each { configuration ->
      jobs[configuration.key] = {
        IndividualBuildConfig config = configuration.value

        // jdkxx-linux-x64-hotspot
        def jobTopName = "${javaToBuild}-${configuration.key}"
        def jobFolder = getJobFolder()

        // i.e jdkxx/jobs/jdkxx-linux-x64-hotspot
        def downstreamJobName = "${jobFolder}/${jobTopName}"

        context.echo "build name " + downstreamJobName

        // Job dsl
        createJob(jobTopName, jobFolder, config)

        context.echo "Created job " + downstreamJobName

        // Start build
        def downstreamJob = context.build job: downstreamJobName, propagate: false, parameters: config.toBuildParams()
      }
    }

    context.parallel jobs

    context.println "All done!"
    context.cleanWs()
  }

}

return {
  String javaToBuild,
  Map<String, Map<String, ?>> buildConfigurations,
  def scmVars,
  def currentBuild,
  def context,
  def env -> 

      return new Regeneration(
              javaToBuild: javaToBuild,
              buildConfigurations: buildConfigurations,
              scmVars: scmVars,
              currentBuild: currentBuild,
              context: context,
              env: env
      )

}