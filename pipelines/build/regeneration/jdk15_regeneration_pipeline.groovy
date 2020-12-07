import java.nio.file.NoSuchFileException
import java.util.regex.Matcher
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

String javaVersion = "jdk15"
//TODO: Change me
String DEFAULTS_FILE_URL = "https://raw.githubusercontent.com/M-Davies/openjdk-build/parameterised_everything/pipelines/build/defaults.json"

node ("master") {
  // Retrieve Defaults
  def get = new URL(DEFAULTS_FILE_URL).openConnection()
  Map<String, ?> DEFAULTS_JSON = new JsonSlurper().parseText(get.getInputStream().getText()) as Map
  if (!DEFAULTS_JSON) {
    throw new Exception("[ERROR] No DEFAULTS_JSON found at ${DEFAULTS_FILE_URL}. Please ensure this path is correct and it leads to a JSON or Map object file.")
  }

  try {
    // Checkout needed so we can load the library
    checkout scm
    load "${WORKSPACE}/${DEFAULTS_JSON['importLibraryScript']}"

    // Load gitUri and gitBranch. These determine where we will be pulling configs from.
    def repoUri = (params.REPOSITORY_URL) ?: DEFAULTS_JSON["repository"]["url"]
    def repoBranch = (params.REPOSITORY_BRANCH) ?: DEFAULTS_JSON["repository"]["branch"]

    // Checkout into the branch and url place
    checkout(
      [
        $class: 'GitSCM',
        branches: [[name: repoBranch ]],
        userRemoteConfigs: [[ url: repoUri ]]
      ]
    )

    // Load buildConfigurations from config file. This is what the nightlies & releases use to setup their downstream jobs
    def buildConfigurations = null
    String DEFAULT_BUILD_PATH = "${DEFAULTS_JSON['configDirectories']['build']}/${javaVersion}_pipeline_config.groovy"
    def buildConfigPath = (params.BUILD_CONFIG_PATH) ? "${WORKSPACE}/${BUILD_CONFIG_PATH}" : "${WORKSPACE}/${DEFAULT_BUILD_PATH}"

    // Use default config path if param is empty
    if (buildConfigPath == "${WORKSPACE}/${DEFAULT_BUILD_PATH}") {

      try {
        buildConfigurations = load buildConfigPath
      } catch (NoSuchFileException e) {
        javaVersion += "u"
        println "[WARNING] ${buildConfigPath} does not exist, chances are we want a ${javaVersion} version.\n[WARNING] Trying ${WORKSPACE}/pipelines/jobs/configurations/${javaVersion}_pipeline_config.groovy"

        buildConfigurations = load "${WORKSPACE}/pipelines/jobs/configurations/${javaVersion}_pipeline_config.groovy"
      }

    } else {

      buildConfigurations = load buildConfigPath

      // Since we can't check if the file is jdkxxu file or not, some regex is needed here in lieu of the try-catch above
      Matcher matcher = "$buildConfigPath" =~ /.*?(?<version>\d+u).*?/
      if (matcher.matches()) {
        javaVersion += "u"
      }

    }

    if (buildConfigurations == null) {
      throw new Exception("[ERROR] Could not find buildConfigurations for ${javaVersion}")
    }

    // Load targetConfigurations from config file. This is what is being run in the nightlies
    String DEFAULT_TARGET_PATH = "${DEFAULTS_JSON['configDirectories']['nightly']}/${javaVersion}.groovy"
    def targetConfigPath = (params.TARGET_CONFIG_PATH) ? "${WORKSPACE}/${TARGET_CONFIG_PATH}" : "${WORKSPACE}/${DEFAULT_TARGET_PATH}"
    load targetConfigPath

    if (targetConfigurations == null) {
      throw new Exception("[ERROR] Could not find targetConfigurations for ${javaVersion}")
    }

    // Pull in other parametrised values (or use defaults if they're not defined)
    def jobRoot = (params.JOB_ROOT) ?: DEFAULTS_JSON["jenkinsDetails"]["rootDirectory"]
    def jenkinsBuildRoot = (params.JENKINS_BUILD_ROOT) ?: "${DEFAULTS_JSON['jenkinsDetails']["rootUrl"]}/job/${jobRoot}/"
    def jobTemplatePath = (params.JOB_TEMPLATE_PATH) ?: DEFAULTS_JSON["jobTemplateDirectories"]["downstream"]
    def scriptPath = (params.SCRIPT_PATH) ?: DEFAULTS_JSON["scriptDirectories"]["downstream"]
    def excludes = (params.EXCLUDES_LIST) ?: ""

    println "[INFO] Running regeneration script with the following configuration:"
    println "VERSION: $javaVersion"
    println "REPOSITORY URL: $repoUri"
    println "REPOSITORY BRANCH: $repoBranch"
    println "BUILD CONFIGURATIONS: $buildConfigurations"
    println "JOBS TO GENERATE: $targetConfigurations"
    println "JOB ROOT: $jobRoot"
    println "JENKINS ROOT: $jenkinsBuildRoot"
    println "JOB TEMPLATE PATH: $jobTemplatePath"
    println "SCRIPT PATH: $scriptPath"
    println "EXCLUDES LIST: $excludes"

    Closure regenerationScript = load "${WORKSPACE}/${DEFAULTS_JSON['scriptDirectories']['regeneration']}"

    // Pass in credentials if they exist
    if (JENKINS_AUTH != "") {

      // Single quotes here are not a mistake, jenkins actually checks that it's single quoted and that the id starts/ends with '${}'
      withCredentials([
        usernamePassword(
          credentialsId: '${JENKINS_AUTH}',
          usernameVariable: 'jenkinsUsername',
          passwordVariable: 'jenkinsToken'
        )
      ]) {
        regenerationScript(
          javaVersion,
          buildConfigurations,
          targetConfigurations,
          DEFAULTS_JSON,
          excludes,
          currentBuild,
          this,
          jobRoot,
          repoUri,
          repoBranch,
          jobTemplatePath,
          scriptPath,
          jenkinsBuildRoot,
          jenkinsUsername,
          jenkinsToken
        ).regenerate()
      }

    } else {

      println "[WARNING] No Jenkins API Credentials have been provided! If your server does not have anonymous read enabled, you may encounter 403 api request error codes."
      regenerationScript(
        javaVersion,
        buildConfigurations,
        targetConfigurations,
        DEFAULTS_JSON,
        excludes,
        currentBuild,
        this,
        jobRoot,
        repoUri,
        repoBranch,
        jobTemplatePath,
        scriptPath,
        jenkinsBuildRoot,
        null,
        null
      ).regenerate()

    }

    println "[SUCCESS] All done!"

  } finally {
    // Always clean up, even on failure (doesn't delete the dsls)
    println "[INFO] Cleaning up..."
    cleanWs deleteDirs: true
  }

}
