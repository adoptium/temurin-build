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

  import groovy.json.JsonSlurper

  // Get the duration in minutes for the given job stage 
  def getJobStageDuration(Long since, String statsFile, String jobName, String findStage) {
        def MILLIS_IN_MINUTE = 60000
        def workflow = null
        try {
          workflow = sh(returnStdout: true, script: "wget -q -O - ${params.JENKINS_URL}/${jobName}/lastSuccessfulBuild/wfapi/describe")
        } catch(Exception e) {
          workflow = null
        }
        if (workflow) {
          def json = new JsonSlurper().parseText(workflow)
          json.stages.each { stage ->
            if (stage.name.equalsIgnoreCase(findStage)) {
              def startTime = stage.startTimeMillis
              // Did the job stage start after since?
              if (startTime > since) {
                def duration = stage.durationMillis/MILLIS_IN_MINUTE
                duration = duration.intValue()
                println("  ==> Job: ${jobName} Stage: ${stage.name} durationMinutes: ${duration}")
                sh("echo \'${jobName}:${duration}\' >> ${statsFile}")
              }
            }
          }
        }
  }

  // Iterate over all the jobs and get the duration stats
  def getJobs(Long since, String statsFile, String findStage, String folder, Object listJobs) {
    listJobs.each { job ->
      if (job.jobs && job.jobs.size() > 0) {
        if (folder == null || folder.equals("")) {
          getJobs(since, statsFile, findStage, "job/${job.name}", job.jobs)
        } else {
          getJobs(since, statsFile, findStage, "${folder}/job/${job.name}", job.jobs)
        }
      } else {
        def jobName="${folder}/job/${job.name}"
        if (folder == null || folder.equals("")) {
          jobName="job/${job.name}"
        }

        getJobStageDuration(since, statsFile, jobName, findStage)
      }
    }
  }

node ("master") {
  def jenkinsUrl = "${params.JENKINS_URL}"
  def findStage = "${params.STAGE}"
  def periodDays = params.PERIOD_DAYS as Long
  def statsFile = "stage.stats"

  stage("getStageStats") {
    sh("rm -f ${statsFile}")

    try {
      // Work out since time
      def now = System.currentTimeMillis()
      def since = now - (periodDays * 24 * 3600 * 1000) 

      // Get all jobs list to a sub-folder depth of 10
      def jobs = sh(returnStdout: true, script: "wget -q -O - ${jenkinsUrl}/api/json?tree=jobs[name,jobs[name,jobs[name,jobs[name,jobs[name,jobs[name,jobs[name,jobs[name,jobs[name,jobs[name]]]]]]]]]]")
      def jobs_json = new JsonSlurper().parseText(jobs)
      // Get stage stats for all jobs
      getJobs(since, statsFile, findStage, "", jobs_json.jobs)

      // Sort and output 100 longest duration
      echo("*********************************")
      echo("Analyzing successful jobs over the last ${periodDays} days")
      echo("Top 100 longest ${findStage} Stage durations in minutes:")
      echo("*********************************")
      sh("cat ${statsFile} | sort -t: -k2,2n | tail -100")
    } finally {
      // Cleanup
      sh("rm -f ${statsFile}")
    }
  }

}

