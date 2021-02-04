import java.nio.file.NoSuchFileException
import java.util.regex.Matcher
import groovy.json.JsonSlurper
import groovy.json.JsonOutput

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

String javaVersion = "jdk9"
String ADOPT_DEFAULTS_FILE_URL = "https://raw.githubusercontent.com/AdoptOpenJDK/openjdk-build/master/pipelines/defaults.json"
String DEFAULTS_FILE_URL = (params.DEFAULTS_URL) ?: ADOPT_DEFAULTS_FILE_URL

node ("master") {
  // Retrieve Adopt Defaults
  def getAdopt = new URL(ADOPT_DEFAULTS_FILE_URL).openConnection()
  Map<String, ?> ADOPT_DEFAULTS_JSON = new JsonSlurper().parseText(getAdopt.getInputStream().getText()) as Map
  if (!ADOPT_DEFAULTS_JSON || !Map.class.isInstance(ADOPT_DEFAULTS_JSON)) {
    throw new Exception("[ERROR] No ADOPT_DEFAULTS_JSON found at ${ADOPT_DEFAULTS_FILE_URL} or it is not a valid JSON object. Please ensure this path is correct and leads to a JSON or Map object file. NOTE: Since this adopt's defaults and unlikely to change location, this is likely a network or GitHub issue.")
  }

  // Retrieve User Defaults
  def getUser = new URL(DEFAULTS_FILE_URL).openConnection()
  Map<String, ?> DEFAULTS_JSON = new JsonSlurper().parseText(getUser.getInputStream().getText()) as Map
  if (!DEFAULTS_JSON || !Map.class.isInstance(DEFAULTS_JSON)) {
    throw new Exception("[ERROR] No DEFAULTS_JSON found at ${DEFAULTS_FILE_URL}. Please ensure this path is correct and it leads to a JSON or Map object file.")
  }

  try {
    // Load git url and branch and gitBranch. These determine where we will be pulling configs from.
    def repoUri = (params.REPOSITORY_URL) ?: DEFAULTS_JSON["repository"]["url"]
    def repoBranch = (params.REPOSITORY_BRANCH) ?: DEFAULTS_JSON["repository"]["branch"]

    // Load credentials to be used in checking out. This is in case we are checking out a URL that is not Adopts and they don't have their ssh key on the machine.
    def checkoutCreds = (params.CHECKOUT_CREDENTIALS) ?: ""
    def remoteConfigs = new JsonSlurper().parseText('{ "url": "" }') as Map
    remoteConfigs.url = repoUri

    if (checkoutCreds != "") {
      // This currently does not work with user credentials due to https://issues.jenkins.io/browse/JENKINS-60349
      remoteConfigs.credentials = "${checkoutCreds}"
    } else {
      println "[WARNING] CHECKOUT_CREDENTIALS not specified! Checkout to $repoUri may fail if you do not have your ssh key on this machine."
    }

    /*
    Changes dir to Adopt's repo. Use closures as functions aren't accepted inside node blocks
    */
    def checkoutAdopt = { ->
      checkout([$class: 'GitSCM',
        branches: [ [ name: ADOPT_DEFAULTS_JSON["repository"]["branch"] ] ],
        userRemoteConfigs: [ [ url: ADOPT_DEFAULTS_JSON["repository"]["url"] ] ]
      ])
    }

    /*
    Changes dir to the user's repo. Use closures as functions aren't accepted inside node blocks
    */
    def checkoutUser = { ->
      checkout([$class: 'GitSCM',
        branches: [ [ name: repoBranch ] ],
        userRemoteConfigs: [ remoteConfigs ]
      ])
    }

    checkoutUser()

    // Import adopt class library. This contains groovy classes, used for carrying across metadata between jobs.
    def libraryPath = (params.LIBRARY_PATH) ?: DEFAULTS_JSON['importLibraryScript']
    try {
      load "${WORKSPACE}/${libraryPath}"
    } catch (NoSuchFileException e) {
      println "[WARNING] ${libraryPath} does not exist in your repository. Attempting to pull Adopt's library script instead."
      checkoutAdopt()
      libraryPath = ADOPT_DEFAULTS_JSON['importLibraryScript']
      load "${WORKSPACE}/${libraryPath}"
      checkoutUser()
    }

    // Load buildConfigurations from config file. This is what the nightlies & releases use to setup their downstream jobs
    def buildConfigurations = null
    def buildConfigPath = (params.BUILD_CONFIG_PATH) ? "${WORKSPACE}/${BUILD_CONFIG_PATH}" : "${WORKSPACE}/${DEFAULTS_JSON['configDirectories']['build']}"

    try {
      buildConfigurations = load "${buildConfigPath}/${javaVersion}_pipeline_config.groovy"
    } catch (NoSuchFileException e) {
      try {
        println "[WARNING] ${buildConfigPath}/${javaVersion}_pipeline_config.groovy does not exist, chances are we want a U version..."

        buildConfigurations = load "${buildConfigPath}/${javaVersion}u_pipeline_config.groovy"
        javaVersion += "u"
      } catch (NoSuchFileException e2) {
        println "[WARNING] U version does not exist. Likelihood is we are generating from a repository that isn't Adopt's. Pulling Adopt's build config in..."

        checkoutAdopt()
        try {
          buildConfigurations = load "${WORKSPACE}/${ADOPT_DEFAULTS_JSON['configDirectories']['build']}/${javaVersion}_pipeline_config.groovy"
        } catch (NoSuchFileException e3) {
          buildConfigurations = load "${WORKSPACE}/${ADOPT_DEFAULTS_JSON['configDirectories']['build']}/${javaVersion}u_pipeline_config.groovy"
          javaVersion += "u"
        }
        checkoutUser()
      }
    }

    if (buildConfigurations == null) {
      throw new Exception("[ERROR] Could not find buildConfigurations for ${javaVersion}")
    }

    // Load targetConfigurations from config file. This is what is being run in the nightlies
    def targetConfigPath = (params.TARGET_CONFIG_PATH) ? "${WORKSPACE}/${TARGET_CONFIG_PATH}/${javaVersion}.groovy" : "${WORKSPACE}/${DEFAULTS_JSON['configDirectories']['nightly']}/${javaVersion}.groovy"

    try {
      load targetConfigPath
    } catch (NoSuchFileException e) {
      println "[WARNING] ${targetConfigPath} does not exist, chances are we are generating from a repository that isn't Adopt's. Pulling Adopt's nightly config in..."
      checkoutAdopt()
      load "${WORKSPACE}/${ADOPT_DEFAULTS_JSON['configDirectories']['nightly']}"
      checkoutUser()
    }

    if (targetConfigurations == null) {
      throw new Exception("[ERROR] Could not find targetConfigurations for ${javaVersion}")
    }

    // Pull in other parametrised values (or use defaults if they're not defined)
    def jobRoot = (params.JOB_ROOT) ?: DEFAULTS_JSON["jenkinsDetails"]["rootDirectory"]
    def jenkinsBuildRoot = (params.JENKINS_BUILD_ROOT) ?: "${DEFAULTS_JSON['jenkinsDetails']["rootUrl"]}/job/${jobRoot}/"

    def jobTemplatePath = (params.JOB_TEMPLATE_PATH) ?: DEFAULTS_JSON["templateDirectories"]["downstream"]
    if (!fileExists(jobTemplatePath)) {
      println "[WARNING] ${jobTemplatePath} does not exist in your chosen repository. Updating it to use Adopt's instead"
      checkoutAdopt()
      jobTemplatePath = ADOPT_DEFAULTS_JSON['templateDirectories']['downstream']
      println "[SUCCESS] The path is now ${jobTemplatePath} relative to ${ADOPT_DEFAULTS_JSON['repository']['url']}"
      checkoutUser()
    }

    def scriptPath = (params.SCRIPT_PATH) ?: DEFAULTS_JSON["scriptDirectories"]["downstream"]
    if (!fileExists(scriptPath)) {
      println "[WARNING] ${scriptPath} does not exist in your chosen repository. Updating it to use Adopt's instead"
      checkoutAdopt()
      scriptPath = ADOPT_DEFAULTS_JSON['scriptDirectories']['downstream']
      println "[SUCCESS] The path is now ${scriptPath} relative to ${ADOPT_DEFAULTS_JSON['repository']['url']}"
      checkoutUser()
    }

    def baseFilePath = (params.BASE_FILE_PATH) ?: DEFAULTS_JSON["baseFileDirectories"]["downstream"]
    if (!fileExists(baseFilePath)) {
      println "[WARNING] ${baseFilePath} does not exist in your chosen repository. Updating it to use Adopt's instead"
      checkoutAdopt()
      baseFilePath = ADOPT_DEFAULTS_JSON['baseFileDirectories']['downstream']
      println "[SUCCESS] The path is now ${baseFilePath} relative to ${ADOPT_DEFAULTS_JSON['repository']['url']}"
      checkoutUser()
    }

    def excludes = (params.EXCLUDES_LIST) ?: ""
    def jenkinsCreds = (params.JENKINS_AUTH) ?: ""
    Integer sleepTime = (params.SLEEP_TIME) != "" ? Integer.parseInteger(SLEEP_TIME) : 900

    println "[INFO] Running regeneration script with the following configuration:"
    println "VERSION: $javaVersion"
    println "REPOSITORY URL: $repoUri"
    println "REPOSITORY BRANCH: $repoBranch"
    println "BUILD CONFIGURATIONS: ${JsonOutput.prettyPrint(JsonOutput.toJson(buildConfigurations))}"
    println "JOBS TO GENERATE: ${JsonOutput.prettyPrint(JsonOutput.toJson(targetConfigurations))}"
    println "JOB ROOT: $jobRoot"
    println "JENKINS ROOT: $jenkinsBuildRoot"
    println "JOB TEMPLATE PATH: $jobTemplatePath"
    println "SCRIPT PATH: $scriptPath"
    println "BASE FILE PATH: $baseFilePath"
    println "LIBRARY PATH: $libraryPath"
    println "EXCLUDES LIST: $excludes"
    println "SLEEP_TIME: $sleepTime"
    if (jenkinsCreds == "") { println "[WARNING] No Jenkins API Credentials have been provided! If your server does not have anonymous read enabled, you may encounter 403 api request error codes." }

    // Load regen script and execute base file
    Closure regenerationScript
    def regenScriptPath = (params.REGEN_SCRIPT_PATH) ?: DEFAULTS_JSON['scriptDirectories']['regeneration']
    try {
      regenerationScript = load "${WORKSPACE}/${regenScriptPath}"
    } catch (NoSuchFileException e) {
      println "[WARNING] ${regenScriptPath} does not exist in your chosen repository. Using adopt's script path instead"
      checkoutAdopt()
      regenerationScript = load "${WORKSPACE}/${ADOPT_DEFAULTS_JSON['scriptDirectories']['regeneration']}"
      checkoutUser()
    }

    if (jenkinsCreds != "") {
      withCredentials([usernamePassword(
          credentialsId: '${JENKINS_AUTH}',
          usernameVariable: 'jenkinsUsername',
          passwordVariable: 'jenkinsToken'
      )]) {
        String jenkinsCredentials = "$jenkinsUsername:$jenkinsToken"
        regenerationScript(
          javaVersion,
          buildConfigurations,
          targetConfigurations,
          DEFAULTS_JSON,
          excludes,
          sleepTime,
          currentBuild,
          this,
          jobRoot,
          remoteConfigs,
          repoBranch,
          jobTemplatePath,
          libraryPath,
          baseFilePath,
          scriptPath,
          jenkinsBuildRoot,
          jenkinsCredentials,
          checkoutCreds
        ).regenerate()
      }
    } else {
      regenerationScript(
        javaVersion,
        buildConfigurations,
        targetConfigurations,
        DEFAULTS_JSON,
        excludes,
        sleepTime,
        currentBuild,
        this,
        jobRoot,
        remoteConfigs,
        repoBranch,
        jobTemplatePath,
        libraryPath,
        baseFilePath,
        scriptPath,
        jenkinsBuildRoot,
        jenkinsCreds,
        checkoutCreds
      ).regenerate()
    }

    println "[SUCCESS] All done!"

  } finally {
    // Always clean up, even on failure (doesn't delete the generated jobs)
    println "[INFO] Cleaning up..."
    cleanWs deleteDirs: true
  }

}
