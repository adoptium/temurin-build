import java.nio.file.NoSuchFileException

node('master') {
  timestamps {

    def retiredVersions = [9, 10, 12, 13, 14]
    def generatedPipelines = []

    // Load gitUri and gitBranch. These determine where we will be pulling configs from.
    def repoUri = (params.REPOSITORY_URL) ?: "https://github.com/AdoptOpenJDK/openjdk-build.git"
    def repoBranch = (params.REPOSITORY_BRANCH) ?: "master"
    
    // Load jobRoot. This is where the openjdkxx-pipeline jobs will be created.
    def jobRoot = (params.JOB_ROOT) ?: "build-scripts"

    // Load scriptFolderPath. This is the folder where the openjdkxx-pipeline.groovy code is located compared to the repository root. These are the top level pipeline jobs.
    def scriptFolderPath = (params.SCRIPT_FOLDER_PATH) ?: "pipelines/build"

    // Load nightlyFolderPath. This is the folder where the jdkxx.groovy code is located compared to the repository root. These define what the default set of nightlies will be.
    def nightlyFolderPath = (params.NIGHTLY_FOLDER_PATH) ?: "pipelines/jobs/configurations"

    // Load jobTemplatePath. This is where the pipeline_job_template.groovy code is located compared to the repository root. This actually sets up the pipeline job using the parameters above.
    def jobTemplatePath = (params.JOB_TEMPLATE_PATH) ?: "pipelines/jobs/pipeline_job_template.groovy"

    // Load enablePipelineSchedule. This determines whether we will be generating the pipelines with a schedule (defined in jdkxx.groovy) or not
    def enablePipelineSchedule = true
    if (Boolean.parseBoolean(Upgraded) == false) {
      enablePipelineSchedule = false
    }

    // Load credentials to be used in checking out. This is in case we are checking out a URL that is not Adopts and they don't have their ssh key on the machine
    def checkoutCreds = (params.SSH_CREDENTIALS) ?: ""

    println "[INFO] Running generator script with the following configuration:"
    println "REPOSITORY_URL = $repoUri"
    println "REPOSITORY_BRANCH = $repoBranch"
    println "JOB_ROOT = $jobRoot"
    println "SCRIPT_FOLDER_PATH = $scriptFolderPath"
    println "NIGHTLY_FOLDER_PATH = $nightlyFolderPath"
    println "JOB_TEMPLATE_PATH = $jobTemplatePath"
    println "ENABLE_PIPELINE_SCHEDULE = $ENABLE_PIPELINE_SCHEDULE"

    // Setup configs for checking out the specified repository
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
          config.put("triggerSchedule", target.triggerSchedule)
        } catch (Exception ex) {
          config.put("triggerSchedule", "@daily")
        }
      }

      println "[INFO] JDK${javaVersion}: triggerSchedule = ${config.triggerSchedule}"

      println "[INFO] FINAL CONFIG FOR $javaVersion"
      println config

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
