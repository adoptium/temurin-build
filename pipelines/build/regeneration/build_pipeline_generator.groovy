import java.nio.file.NoSuchFileException

node('master') {
  def retiredVersions = [9, 10, 12, 13, 14]
  def generatedPipelines = []

  // Load gitUri and gitBranch. These determine where we will be pulling configs from.
  def repoUri = "$REPOSITORY_URL" != "" ? REPOSITORY_URL : "https://github.com/AdoptOpenJDK/openjdk-build.git"
  def repoBranch = "$REPOSITORY_BRANCH" != "" ? REPOSITORY_BRANCH : "master"
  
  // Load jobRoot. This is where the openjdkxx-pipeline jobs will be created.
  def jobRoot = "$JOB_ROOT" != "" ? JOB_ROOT : "build-scripts"

  // Load scriptFolderPath. This is the folder where the openjdkxx-pipeline.groovy code is located compared to the repository root. These are the top level pipeline jobs.
  def scriptFolderPath = "$SCRIPT_FOLDER_PATH" != "" ? SCRIPT_FOLDER_PATH : "pipelines/build"

  // Load nightlyFolderPath. This is the folder where the jdkxx.groovy code is located compared to the repository root. These define what the default set of nightlies will be.
  def nightlyFolderPath = "$NIGHTLY_FOLDER_PATH" != "" ? NIGHTLY_FOLDER_PATH : "pipelines/jobs/configurations"

  // Load jobTemplatePath. This is where the pipeline_job_template.groovy code is located compared to the repository root. This actually sets up the pipeline job using the parameters above.
  def jobTemplatePath = "$JOB_TEMPLATE_PATH" != "" ? JOB_TEMPLATE_PATH : "pipelines/jobs/pipeline_job_template.groovy"

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
      println "[INFO] $javaVersion is a retired version that isn't built anymore. Skipping generation..."
      return
    }

    def config = [
      TEST                : false,
      GIT_URL             : repoUri,
      BRANCH              : repoBranch,
      BUILD_FOLDER        : jobRoot,
      JOB_NAME            : "openjdk${javaVersion}-pipeline",
      SCRIPT              : "${scriptFolderPath}/openjdk${javaVersion}_pipeline.groovy",
      disableJob          : false,
      triggerSchedule     : ""
    ];

    checkout(
      [
        $class: 'GitSCM',
        branches: [[name: config.BRANCH ]],
        userRemoteConfigs: [[ url: config.GIT_URL ]]
      ]
    )
    
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
    
    config.targetConfigurations = target.targetConfigurations

    // hack as jenkins groovy does not seem to allow us to check if disableJob exists
    try {
      config.disableJob = target.disableJob;
    } catch (Exception ex) {
      config.disableJob = false;
    }
    
    println "[INFO] JDK${javaVersion}: disableJob = ${config.disableJob}"

    // Load ENABLE_PIPELINE_SCHEDULE. This determines whether the jobs should run automatically or not.
    if (Boolean.parseBoolean(ENABLE_PIPELINE_SCHEDULE) == true) {
      try {
        config.triggerSchedule = target.triggerSchedule
      } catch (Exception ex) {
        config.triggerSchedule = "@daily";
      }
    }

    println "[INFO] JDK${javaVersion}: triggerSchedule = ${config.triggerSchedule}"

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
