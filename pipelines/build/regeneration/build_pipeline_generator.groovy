node('master') {
  def retiredVersions = [9, 10, 12, 13, 14]

  (8..30).each({javaVersion -> 

    if (retiredVersions.contains(javaVersion)) {
      println "[INFO] $javaVersion is a retired version that isn't currently built. Skipping generation..."
      return
    }
    
    def config = [
      TEST                : false,
      GIT_URL             : "https://github.com/AdoptOpenJDK/openjdk-build.git",
      BRANCH              : "master",
      BUILD_FOLDER        : "build-scripts",
      JOB_NAME            : "openjdk${javaVersion}-pipeline",
      SCRIPT              : "pipelines/build/openjdk${javaVersion}_pipeline.groovy",
      disableJob          : false,
      triggerSchedule     : ""
    ];
    checkout([$class: 'GitSCM', branches: [[name: config.BRANCH]], userRemoteConfigs: [[url: config.GIT_URL]]])
    
    def target;
    try {
      target = load "${WORKSPACE}/pipelines/jobs/configurations/jdk${javaVersion}u.groovy"
    } catch(Exception e) {
      try {
        target = load "${WORKSPACE}/pipelines/jobs/configurations/jdk${javaVersion}.groovy"
      } catch(Exception e2) {
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

    if (Boolean.parseBoolean(enablePipelineSchedule) == true) {
      try {
        config.triggerSchedule = target.triggerSchedule_nightly
      } catch (Exception ex) {
        config.triggerSchedule = "@daily";
      }
    }

    println "[INFO] JDK${javaVersion}: nightly triggerSchedule = ${config.triggerSchedule}"

    // Create nightly pipeline
    def create = jobDsl targets: "pipelines/jobs/pipeline_job_template.groovy", ignoreExisting: false, additionalParameters: config
 
    // Create weekly release pipeline
    config.JOB_NAME = "weekly-openjdk${javaVersion}-pipeline"
    config.SCRIPT   = "pipelines/build/common/weekly_release_pipeline.groovy"
    config.PIPELINE = "openjdk${javaVersion}-pipeline"

    if (Boolean.parseBoolean(enablePipelineSchedule) == true) {
      try {
        config.triggerSchedule = target.triggerSchedule_weekly
      } catch (Exception ex) {
        config.triggerSchedule = "@weekly";
      }
    }
    println "[INFO] JDK${javaVersion}: weekly triggerSchedule = ${config.triggerSchedule}"
    def create_weekly = jobDsl targets: "pipelines/jobs/weekly_release_pipeline_job_template.groovy", ignoreExisting: false, additionalParameters: config

    target.disableJob = false
  })
}
