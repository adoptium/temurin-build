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

node ("master") {
  def jenkinsUrl = "${params.JENKINS_URL}"
  def trssUrl    = "${params.TRSS_URL}"

  def buildFailures = 0
  def testStats = []

  // Get the number of "Failing Builds"
  stage("getBuildFailures") {
    def builds = sh(returnStdout: true, script: "wget -q -O - ${jenkinsUrl}/view/Failing%20Builds/api/json")
    def json = new JsonSlurper().parseText(builds)
    buildFailures = json.jobs.size()
  }

  // Get the last Nightly test job & case stats
  stage("getTestStats") {
    // Get top level builds names
    def trssBuildNames = sh(returnStdout: true, script: "wget -q -O - ${trssUrl}/api/getTopLevelBuildNames?type=Test")
    def buildNamesJson = new JsonSlurper().parseText(trssBuildNames)
    buildNamesJson.each { build ->
      // Is it a build Pipeline?
      if (build._id.buildName.contains("-pipeline")) {
        echo "Pipeline ${build._id.buildName}"
        def pipelineName = build._id.buildName
        def pipelineUrl
        def testJobSuccess = 0
        def testJobUnstable = 0
        def testJobFailure = 0
        def testCasePassed = 0
        def testCaseFailed = 0
        def testCaseDisabled = 0
        def testJobNumber = 0

        // Get all pipeline builds started by "timer", as those are Nightlies
        def pipeline = sh(returnStdout: true, script: "wget -q -O - ${trssUrl}/api/getBuildHistory?buildName=${pipelineName}\\&startBy=timer")
        def pipelineJson = new JsonSlurper().parseText(pipeline)
        if (pipelineJson.size() > 0) {
          // First in list is last Nightly job
          def pipeline_id = pipelineJson[0]._id
          pipelineUrl = pipelineJson[0].buildUrl 

          // Get all child Test jobs for this pipeline job
          def pipelineTestJobs = sh(returnStdout: true, script: "wget -q -O - ${trssUrl}/api/getAllChildBuilds?parentId=${pipeline_id}\\&buildNameRegex=^Test_.*")
          def pipelineTestJobsJson = new JsonSlurper().parseText(pipelineTestJobs)
          if (pipelineTestJobsJson.size() > 0) {
            testJobNumber = pipelineTestJobsJson.size()
            pipelineTestJobsJson.each { testJob ->
              if (testJob.buildResult.equals("SUCCESS")) {
                testJobSuccess += 1
              } else if (testJob.buildResult.equals("UNSTABLE")) {
                testJobUnstable += 1
              } else {
                testJobFailure += 1
              }
              if (testJob.testSummary != null) {
                testCasePassed += testJob.testSummary.passed
                testCaseFailed += testJob.testSummary.failed
                testCaseDisabled += testJob.testSummary.disabled
              }
            }
          }
        }

        def testResult = [name: pipelineName, url: pipelineUrl,
                          testJobSuccess:   testJobSuccess,
                          testJobUnstable:  testJobUnstable,
                          testJobFailure:   testJobFailure,
                          testCasePassed:   testCasePassed,
                          testCaseFailed:   testCaseFailed,
                          testCaseDisabled: testCaseDisabled,
                          testJobNumber:    testJobNumber]
        testStats.add(testResult)
      }
    }
  }

  // Print the results
  stage("printResults") {
    echo "==================================================================================="
    echo "Build Failures = ${buildFailures}"
    echo "==================================================================================="
    testStats.each { pipeline ->
      echo "Pipeline : ${pipeline.name} : ${pipeline.url}"
      echo "  => Number of Test jobs = ${pipeline.testJobNumber}" 
      echo "  => Test job SUCCESS    = ${pipeline.testJobSuccess}"
      echo "  => Test job UNSTABLE   = ${pipeline.testJobUnstable}"
      echo "  => Test job FAILURE    = ${pipeline.testJobFailure}"
      echo "  => Test case Passed    = ${pipeline.testCasePassed}"
      echo "  => Test case Failed    = ${pipeline.testCaseFailed}"
      echo "  => Test case Disabled  = ${pipeline.testCaseDisabled}"
      echo "==================================================================================="
    }
  }
}

