import java.nio.file.NoSuchFileException
import groovy.json.JsonSlurper
import groovy.json.JsonOutput

node('master') {
  try {
    // Pull in Adopt defaults
    String ADOPT_DEFAULTS_FILE_URL = "https://raw.githubusercontent.com/AdoptOpenJDK/openjdk-build/master/pipelines/defaults.json"
    def getAdopt = new URL(ADOPT_DEFAULTS_FILE_URL).openConnection()
    Map<String, ?> ADOPT_DEFAULTS_JSON = new JsonSlurper().parseText(getAdopt.getInputStream().getText()) as Map
    if (!ADOPT_DEFAULTS_JSON || !Map.class.isInstance(ADOPT_DEFAULTS_JSON)) {
      throw new Exception("[ERROR] No ADOPT_DEFAULTS_JSON found at ${ADOPT_DEFAULTS_FILE_URL} or it is not a valid JSON object. Please ensure this path is correct and leads to a JSON or Map object file. NOTE: Since this adopt's defaults and unlikely to change location, this is likely a network or GitHub issue.")
    }

    // Pull in User defaults
    String DEFAULTS_FILE_URL = (params.DEFAULTS_URL) ?: ADOPT_DEFAULTS_FILE_URL
    def getUser = new URL(DEFAULTS_FILE_URL).openConnection()
    Map<String, ?> DEFAULTS_JSON = new JsonSlurper().parseText(getUser.getInputStream().getText()) as Map
    if (!DEFAULTS_JSON || !Map.class.isInstance(DEFAULTS_JSON)) {
      throw new Exception("[ERROR] No DEFAULTS_JSON found at ${DEFAULTS_FILE_URL} or it is not a valid JSON object. Please ensure this path is correct and leads to a JSON or Map object file.")
    }

    Map remoteConfigs = [:]
    def repoBranch = null

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

    timestamps {
      def retiredVersions = [9, 10, 12, 13, 14, 15]
      def generatedPipelines = []

      // Load git url and branch and gitBranch. These determine where we will be pulling user configs from.
      def repoUri = (params.REPOSITORY_URL) ?: DEFAULTS_JSON["repository"]["url"]
      repoBranch = (params.REPOSITORY_BRANCH) ?: DEFAULTS_JSON["repository"]["branch"]

      // Load credentials to be used in checking out. This is in case we are checking out a URL that is not Adopts and they don't have their ssh key on the machine.
      def checkoutCreds = (params.CHECKOUT_CREDENTIALS) ?: ""
      remoteConfigs = [ url: repoUri ]
      if (checkoutCreds != "") {
        // NOTE: This currently does not work with user credentials due to https://issues.jenkins.io/browse/JENKINS-60349
        remoteConfigs.put("credentials", "${checkoutCreds}")
      } else {
        println "[WARNING] CHECKOUT_CREDENTIALS not specified! Checkout to $repoUri may fail if you do not have your ssh key on this machine."
      }

      // Checkout into user repository
      checkoutUser()

      // Load the adopt class library so we can use their classes here. If we don't find an import library script in the user's repo, we checkout to openjdk-build and use the one that's present there. Finally, we check back out to the user repo.
      def libraryPath = (params.LIBRARY_PATH) ?: DEFAULTS_JSON['importLibraryScript']
      try {
        load "${WORKSPACE}/${libraryPath}"
      } catch (NoSuchFileException e) {
        println "[WARNING] ${libraryPath} does not exist in your repository. Attempting to pull Adopt's library script instead."

        checkoutAdopt()
        load "${WORKSPACE}/${ADOPT_DEFAULTS_JSON['importLibraryScript']}"
        checkoutUser()
      }

      // Load jobRoot. This is where the openjdkxx-pipeline jobs will be created.
      def jobRoot = (params.JOB_ROOT) ?: DEFAULTS_JSON["jenkinsDetails"]["rootDirectory"]

      // Load scriptFolderPath. This is the folder where the openjdkxx-pipeline.groovy code is located compared to the repository root. These are the top level pipeline jobs.
      def scriptFolderPath = (params.SCRIPT_FOLDER_PATH) ?: DEFAULTS_JSON["scriptDirectories"]["upstream"]

      if (!fileExists(scriptFolderPath)) {
        println "[WARNING] ${scriptFolderPath} does not exist in your chosen repository. Updating it to use Adopt's instead"
        checkoutAdopt()
        scriptFolderPath = ADOPT_DEFAULTS_JSON['scriptDirectories']['upstream']
        println "[SUCCESS] The path is now ${scriptFolderPath} relative to ${ADOPT_DEFAULTS_JSON['repository']['url']}"
        checkoutUser()
      }

      // Load nightlyFolderPath. This is the folder where the jdkxx.groovy code is located compared to the repository root. These define what the default set of nightlies will be.
      def nightlyFolderPath = (params.NIGHTLY_FOLDER_PATH) ?: DEFAULTS_JSON["configDirectories"]["nightly"]

      if (!fileExists(nightlyFolderPath)) {
        println "[WARNING] ${nightlyFolderPath} does not exist in your chosen repository. Updating it to use Adopt's instead"
        checkoutAdopt()
        nightlyFolderPath = ADOPT_DEFAULTS_JSON['configDirectories']['nightly']
        println "[SUCCESS] The path is now ${nightlyFolderPath} relative to ${ADOPT_DEFAULTS_JSON['repository']['url']}"
        checkoutUser()
      }

      // Load jobTemplatePath. This is where the pipeline_job_template.groovy code is located compared to the repository root. This actually sets up the pipeline job using the parameters above.
      def jobTemplatePath = (params.JOB_TEMPLATE_PATH) ?: DEFAULTS_JSON['templateDirectories']['upstream']

      if (!fileExists(jobTemplatePath)) {
        println "[WARNING] ${jobTemplatePath} does not exist in your chosen repository. Updating it to use Adopt's instead"
        checkoutAdopt()
        jobTemplatePath = ADOPT_DEFAULTS_JSON['templateDirectories']['upstream']
        println "[SUCCESS] The path is now ${jobTemplatePath} relative to ${ADOPT_DEFAULTS_JSON['repository']['url']}"
        checkoutUser()
      }

      // Load enablePipelineSchedule. This determines whether we will be generating the pipelines with a schedule (defined in jdkxx.groovy) or not.
      Boolean enablePipelineSchedule = false
      if (params.ENABLE_PIPELINE_SCHEDULE) {
        enablePipelineSchedule = true
      }

      // Load useAdoptShellScripts. This determines whether we will checkout to adopt's repository before running make-adopt-build-farm.sh or if we use the user's bash scripts.
      Boolean useAdoptShellScripts = false
      if (params.USE_ADOPT_SHELL_SCRIPTS) {
        useAdoptShellScripts = true
      }

      println "[INFO] Running generator script with the following configuration:"
      println "REPOSITORY_URL = $repoUri"
      println "REPOSITORY_BRANCH = $repoBranch"
      println "JOB_ROOT = $jobRoot"
      println "SCRIPT_FOLDER_PATH = $scriptFolderPath"
      println "NIGHTLY_FOLDER_PATH = $nightlyFolderPath"
      println "JOB_TEMPLATE_PATH = $jobTemplatePath"
      println "ENABLE_PIPELINE_SCHEDULE = $enablePipelineSchedule"
      println "USE_ADOPT_SHELL_SCRIPTS = $useAdoptShellScripts"

      // Collect available JDK versions to check for generation (tip_version + 1 just in case it is out of date on a release day)
      def JobHelper = library(identifier: 'openjdk-jenkins-helper@master').JobHelper
      println "Querying Adopt Api for the JDK-Head number (tip_version)..."

      def response = JobHelper.getAvailableReleases(this)
      int headVersion = (int) response.getAt("tip_version")

      (8..headVersion+1).each({javaVersion ->

        if (retiredVersions.contains(javaVersion)) {
          println "[INFO] $javaVersion is a retired version that isn't currently built. Skipping generation..."
          return
        }

        def config = [
          TEST                : false,
          GIT_URL             : repoUri,
          BRANCH              : repoBranch,
          BUILD_FOLDER        : jobRoot,
          CHECKOUT_CREDENTIALS: checkoutCreds,
          JOB_NAME            : "openjdk${javaVersion}-pipeline",
          SCRIPT              : "${scriptFolderPath}/openjdk${javaVersion}_pipeline.groovy",
          disableJob          : false,
          pipelineSchedule    : "0 0 31 2 0", // 31st Feb, so will never run,
          adoptScripts        : false
        ];

        def target;
        try {
          target = load "${WORKSPACE}/${nightlyFolderPath}/jdk${javaVersion}.groovy"
        } catch(NoSuchFileException e) {
          try {
            println "[WARNING] jdk${javaVersion}.groovy does not exist, chances are we want a jdk${javaVersion}u.groovy file. Trying ${WORKSPACE}/${nightlyFolderPath}/jdk${javaVersion}u.groovy"
            target = load "${WORKSPACE}/${nightlyFolderPath}/jdk${javaVersion}u.groovy"
          } catch(NoSuchFileException e2) {
            println "[WARNING] jdk${javaVersion}u.groovy does not exist, chances are we are generating from a repository that isn't Adopt's. Pulling Adopt's nightlies in..."

            checkoutAdopt()
            try {
              target = load "${WORKSPACE}/${ADOPT_DEFAULTS_JSON['configDirectories']['nightly']}/jdk${javaVersion}.groovy"
            } catch (NoSuchFileException e3) {
              try {
                target = load "${WORKSPACE}/${ADOPT_DEFAULTS_JSON['configDirectories']['nightly']}/jdk${javaVersion}u.groovy"
              } catch (NoSuchFileException e4) {
                println "[WARNING] No config found for JDK${javaVersion} in the User's or Adopt's repository. Skipping generation..."
                return
              }
            }
            checkoutUser()

          }
        }

        config.put("targetConfigurations", target.targetConfigurations)

        // hack as jenkins groovy does not seem to allow us to check if disableJob exists
        try {
          config.put("disableJob", target.disableJob)
        } catch (Exception ex) {
          config.put("disableJob", false)
        }

        if (enablePipelineSchedule.toBoolean()) {
          config.put("pipelineSchedule", target.triggerSchedule_nightly)
        }

        if (useAdoptShellScripts.toBoolean()) {
          config.put("adoptScripts", true)
        }

        println "[INFO] JDK${javaVersion}: nightly pipelineSchedule = ${config.pipelineSchedule}"

        config.put("defaultsJson", DEFAULTS_JSON)
        config.put("adoptDefaultsJson", ADOPT_DEFAULTS_JSON)

        println "[INFO] FINAL CONFIG FOR NIGHTLY $javaVersion"
        println JsonOutput.prettyPrint(JsonOutput.toJson(config))

        // Create the nightly job, using adopt's template if the user's one fails
        try {
          jobDsl targets: jobTemplatePath, ignoreExisting: false, additionalParameters: config
        } catch (Exception e) {
          println "[WARNING] Something went wrong when creating the job dsl. It may be because we are trying to pull the template inside a user repository. Using Adopt's template instead...\n${e}"
          checkoutAdopt()
          jobDsl targets: ADOPT_DEFAULTS_JSON['templateDirectories']['upstream'], ignoreExisting: false, additionalParameters: config
          checkoutUser()
        }

        target.disableJob = false

        generatedPipelines.add(config["JOB_NAME"])

        // Create weekly release pipeline
        config.JOB_NAME = "weekly-openjdk${javaVersion}-pipeline"
        config.SCRIPT = (params.WEEKLY_SCRIPT_PATH) ?: DEFAULTS_JSON['scriptDirectories']['weekly']
        if (!fileExists(config.SCRIPT)) {
          println "[WARNING] ${config.SCRIPT} does not exist in your chosen repository. Updating it to use Adopt's instead"
          checkoutAdopt()
          config.SCRIPT = ADOPT_DEFAULTS_JSON['scriptDirectories']['weekly']
          println "[SUCCESS] The path is now ${config.SCRIPT} relative to ${ADOPT_DEFAULTS_JSON['repository']['url']}"
          checkoutUser()
        }
        config.PIPELINE = "openjdk${javaVersion}-pipeline"
        config.weekly_release_scmReferences = target.weekly_release_scmReferences

        // Load weeklyTemplatePath. This is where the weekly_release_pipeline_job_template.groovy code is located compared to the repository root. This actually sets up the weekly pipeline job using the parameters above.
        def weeklyTemplatePath = (params.WEEKLY_TEMPLATE_PATH) ?: DEFAULTS_JSON['templateDirectories']['weekly']

        if (enablePipelineSchedule.toBoolean()) {
          config.put("pipelineSchedule", target.triggerSchedule_weekly)
        }

        println "[INFO] CREATING JDK${javaVersion} WEEKLY RELEASE PIPELINE WITH NEW CONFIG VALUES:"
        println "JOB_NAME = ${config.JOB_NAME}"
        println "SCRIPT = ${config.SCRIPT}"
        println "PIPELINE = ${config.PIPELINE}"
        println "weekly_release_scmReferences = ${config.weekly_release_scmReferences}"

        try {
          jobDsl targets: weeklyTemplatePath, ignoreExisting: false, additionalParameters: config
        } catch (Exception e) {
          println "[WARNING] Something went wrong when creating the weekly job dsl. It may be because we are trying to pull the template inside a user repository. Using Adopt's template instead...\n${e}"
          checkoutAdopt()
          jobDsl targets: ADOPT_DEFAULTS_JSON['templateDirectories']['weeklyTemplatePath'], ignoreExisting: false, additionalParameters: config
          checkoutUser()
        }

        target.disableJob = false

        generatedPipelines.add(config["JOB_NAME"])
      })

      // Fail if nothing was generated
      if (generatedPipelines == []) {
        throw new Exception("[ERROR] NO PIPELINES WERE GENERATED!")
      } else {
        println "[SUCCESS] THE FOLLOWING PIPELINES WERE GENERATED IN THE $JOB_ROOT FOLDER"
        println generatedPipelines
      }

    }
  } finally {
    // Always clean up, even on failure (doesn't delete the created jobs)
    println "[INFO] Cleaning up..."
    cleanWs deleteDirs: true
  }
}