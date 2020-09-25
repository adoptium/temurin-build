node('master') {
  def retiredVersions = [9, 10, 12, 13, 14]

  (8..30).each({javaVersion -> 

    if (retiredVersions.contains(javaVersion)) {
      println "[INFO] $javaVersion is a retired version that isn't built anymore. Skipping generation..."
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
    checkout([$class: 'GitSCM', userRemoteConfigs: [[url: config.GIT_URL]]])
    
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
        config.triggerSchedule = target.triggerSchedule
      } catch (Exception ex) {
        config.triggerSchedule = "@daily";
      }
    }

    println "[INFO] JDK${javaVersion}: triggerSchedule = ${config.triggerSchedule}"

    def create = jobDsl targets: "pipelines/jobs/pipeline_job_template.groovy", ignoreExisting: false, additionalParameters: config
    target.disableJob = false
  })
}
