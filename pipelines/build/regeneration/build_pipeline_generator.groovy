import java.nio.file.NoSuchFileException
import groovy.json.JsonSlurper
import groovy.json.JsonOutput
//TODO: Change me
String DEFAULTS_FILE_URL = (params.DEFAULTS_URL) ?: "https://raw.githubusercontent.com/M-Davies/openjdk-build/parameterised_everything/pipelines/defaults.json"

node('master') {
  timestamps {
    // Retrieve Defaults
    def get = new URL(DEFAULTS_FILE_URL).openConnection()
    Map<String, ?> DEFAULTS_JSON = new JsonSlurper().parseText(get.getInputStream().getText()) as Map
    if (!DEFAULTS_JSON) {
      throw new Exception("[ERROR] No DEFAULTS_JSON found at ${DEFAULTS_FILE_URL}. Please ensure this path is correct and it leads to a JSON or Map object file.")
    }

    def retiredVersions = [9, 10, 12, 13, 14]
    def generatedPipelines = []

    // Load gitUri and gitBranch. These determine where we will be pulling configs from.
    def repoUri = (params.REPOSITORY_URL) ?: DEFAULTS_JSON["repository"]["url"]
    def repoBranch = (params.REPOSITORY_BRANCH) ?: DEFAULTS_JSON["repository"]["branch"]

    // Load credentials to be used in checking out. This is in case we are checking out a URL that is not Adopts and they don't have their ssh key on the machine.
    def checkoutCreds = (params.SSH_CREDENTIALS) ?: ""
    def remoteConfigs = [ url: repoUri ]
    if (checkoutCreds != "") {
      remoteConfigs.put("credentialsId", "${checkoutCreds}")
    } else {
      println "[WARNING] SSH_CREDENTIALS not specified! Checkout to $repoUri may fail if you do not have your ssh key on this machine."
    }

    // Checkout into repository
    checkout(
      [
        $class: 'GitSCM',
        branches: [ [ name: repoBranch ] ],
        userRemoteConfigs: [ remoteConfigs ]
      ]
    )

    // Load jobRoot. This is where the openjdkxx-pipeline jobs will be created.
    def jobRoot = (params.JOB_ROOT) ?: DEFAULTS_JSON["jenkinsDetails"]["rootDirectory"]

    // Load scriptFolderPath. This is the folder where the openjdkxx-pipeline.groovy code is located compared to the repository root. These are the top level pipeline jobs.
    def scriptFolderPath = (params.SCRIPT_FOLDER_PATH) ?: DEFAULTS_JSON["scriptDirectories"]["upstream"]

    // Load nightlyFolderPath. This is the folder where the jdkxx.groovy code is located compared to the repository root. These define what the default set of nightlies will be.
    def nightlyFolderPath = (params.NIGHTLY_FOLDER_PATH) ?: DEFAULTS_JSON["configDirectories"]["nightly"]

    // Load jobTemplatePath. This is where the pipeline_job_template.groovy code is located compared to the repository root. This actually sets up the pipeline job using the parameters above.
    def jobTemplatePath = (params.JOB_TEMPLATE_PATH) ?: DEFAULTS_JSON["jobTemplateDirectories"]["upstream"]

    // Load enablePipelineSchedule. This determines whether we will be generating the pipelines with a schedule (defined in jdkxx.groovy) or not.
    def enablePipelineSchedule = false
    if (params.ENABLE_PIPELINE_SCHEDULE) {
      enablePipelineSchedule = true
    }

    println "[INFO] Running generator script with the following configuration:"
    println "REPOSITORY_URL = $repoUri"
    println "REPOSITORY_BRANCH = $repoBranch"
    println "JOB_ROOT = $jobRoot"
    println "SCRIPT_FOLDER_PATH = $scriptFolderPath"
    println "NIGHTLY_FOLDER_PATH = $nightlyFolderPath"
    println "JOB_TEMPLATE_PATH = $jobTemplatePath"
    println "ENABLE_PIPELINE_SCHEDULE = $ENABLE_PIPELINE_SCHEDULE"

    (8..30).each({javaVersion ->

      if (retiredVersions.contains(javaVersion)) {
        println "[INFO] $javaVersion is a retired version that isn't currently built. Skipping generation..."
        return
      }

      def config = [
        TEST                : false,
        GIT_URL             : repoUri,
        BRANCH              : repoBranch,
        BUILD_FOLDER        : jobRoot,
        JOB_NAME            : "openjdk${javaVersion}-pipeline",
        SCRIPT              : "${scriptFolderPath}/openjdk${javaVersion}_pipeline.groovy",
        disableJob          : false
      ];

      def target;
      try {
        target = load "${WORKSPACE}/${nightlyFolderPath}/jdk${javaVersion}u.groovy"
      } catch(NoSuchFileException e) {
        try {
          target = load "${WORKSPACE}/${nightlyFolderPath}/jdk${javaVersion}.groovy"
        } catch(NoSuchFileException e2) {
          println "[WARNING] No config found for JDK${javaVersion}"
          return
        }
      }

      config.put("targetConfigurations", target.targetConfigurations)

      // hack as jenkins groovy does not seem to allow us to check if disableJob exists
      try {
        config.put("disableJob", target.disableJob)
      } catch (Exception ex) {
        config.put("disableJob", false)
      }

      println "[INFO] JDK${javaVersion}: disableJob = ${config.disableJob}"

      // Set job schedule
      if (enablePipelineSchedule == true) {
        try {
          config.put("pipelineSchedule", target.triggerSchedule)
        } catch (Exception ex) {
          config.put("pipelineSchedule", "@daily")
        }
      }

      println "[INFO] JDK${javaVersion}: pipelineSchedule = ${config.pipelineSchedule}"

      config.put("defaultsJson", DEFAULTS_JSON)

      println "[INFO] FINAL CONFIG FOR $javaVersion"
      println JsonOutput.prettyPrint(JsonOutput.toJson(config))

      def create = jobDsl targets: jobTemplatePath, ignoreExisting: false, additionalParameters: config

      target.disableJob = false

      generatedPipelines.add(javaVersion)
    })

    // Fail if nothing was generated
    if (generatedPipelines == []) {
      throw new Exception("[ERROR] NO PIPELINES WERE GENERATED!")
    } else {
      println "[SUCCESS] THE FOLLOWING PIPELINES WERE GENERATED IN THE $JOB_ROOT FOLDER"
      println generatedPipelines
    }

  }

}
