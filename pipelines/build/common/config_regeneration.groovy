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
  def scmVars
  def currentBuild
  def context
  def env

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

    // DEBUG
    context.echo "[DEBUG] platformConfig.os = ${platformConfig.x64Linux.os}. platformConfig.arch = ${platformConfig.x64Linux.arch}"

    //def buildArgs = getBuildArgs(platformConfig, variant)
    def buildArgs = ""

    // if (additionalBuildArgs) {
    //     buildArgs += " " + additionalBuildArgs
    // }

    def testList = []

    return new IndividualBuildConfig( // final build config
      JAVA_TO_BUILD: "jdkxxu",
      ARCHITECTURE: platformConfig.x64Linux.arch as String,
      TARGET_OS: platformConfig.x64Linux.os as String,
      VARIANT: variant,
      TEST_LIST: testList,
      SCM_REF: "",
      BUILD_ARGS: buildArgs,
      NODE_LABEL: "${additionalNodeLabels}&&${platformConfig.x64Linux.os}&&${platformConfig.x64Linux.arch}",
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
  * Main function. Ran from regeneration_pipeline.groovy, this will be what the jenkins regeneration job will run. 
  */ 
  @SuppressWarnings("unused")
  def regenerate() {
    // Test downstream job creation.
    Map<String, ?> platformConfig = [
      x64Linux  : [
        os                  : 'linux',
        arch                : 'x64',
        additionalNodeLabels: 'centos6',
        test                : [
          nightly: ['sanity.openjdk', 'sanity.system', 'extended.system', 'sanity.perf', 'sanity.external'],
          release: ['sanity.openjdk', 'sanity.system', 'extended.system', 'sanity.perf', 'sanity.external', 'special.functional']
        ],
        configureArgs : '--disable-ccache',
      ],
    ]

    Map<String, IndividualBuildConfig> jobConfigurations = [:]

    jobConfigurations["linux-x64-hotspot"] = buildConfiguration(platformConfig, "hotspot")

    //Map<String, ?> params = platformConfig.toMap().clone() as Map
    Map<String, ?> params = platformConfig.toMap().clone() as Map

    def jdkVersion = "openjdkxx-pipeline" // Based off the openjdk11_pipeline.groovy build config

    params.put("JOB_NAME", "jdkxxu-linux-x64-hotspot")
    params.put("JOB_FOLDER", "jdkxxu/jobs/")

    params.put("GIT_URI", "https://github.com/AdoptOpenJDK/openjdk-build.git")
    params.put("GIT_BRANCH", "new_build_scripts") 

    context.jobDsl targets: "pipelines/build/common/create_job_from_template.groovy", ignoreExisting: false, additionalParameters: params

    context.println "jobDsl created! create variable (jobDsl) is ${create}\nAttempting to build. Will likely fail since openjdkxx does not exist..."
    context.println "Cleaning..."
    context.cleanWs()

    context.build job: "jdkxxu/jobs/jdkxxu-linux-x64-hotspot", propagate: false, parameters: config.toBuildParams()

    context.println "All done! Cleaning workspace..."
    context.cleanWs()
  }

}

return {
  def scmVars,
  def currentBuild,
  def context,
  def env -> 

      return new Regeneration(
              scmVars: scmVars,
              currentBuild: currentBuild,
              context: context,
              env: env
      )

}