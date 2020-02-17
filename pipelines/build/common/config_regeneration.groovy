@Library('local-lib@master')
import common.IndividualBuildConfig
import groovy.json.*

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

/**
* This file is a job that regenerates all of the build configurations in pipelines/build/openjdk*_pipeline.groovy to ensure that race
* conditions are avoided for concurrent builds.
*
* This:
* 1) Is triggered by a githook from openjdk-build whenever there is a push to the master branch
* 2) Checks if there are any pipelines in progress. If so, this job will run once they have finished and will force other pipelines to  * await for its completion before executing
* 3) Regenerates the all the job configurations to so they are all matched and in sync with each other. This will avoid one job
* configuration overwritting another.
*/

node ("master") {
    context.stage("Check") {
        // Download jenkins helper
        def JobHelper = context.library(identifier: 'openjdk-jenkins-helper@master').JobHelper

        // Get all pipelines (use jenkins api)
        def parser = new JsonSlurper()
        def pipelines = []

        try {
            def get = new URL("https://ci.adoptopenjdk.net/job/build-scripts/api/json?tree=jobs[name]&pretty=true&depth1").openConnection()
            def rc = get.getResponseCode()
            def response = parser.parseText(get.getInputStream().getText())

            // Parse api response
            response.jobs.name.each{ job -> 
                if (job.contains("pipeline")) {
                    pipelines.add(job)
                }
            }

        } catch (Exception e) {
            // Failed to connect to jenkins api or a parsing error occured
            println "Failure on jenkins api connection or parsing. API response code: ${rc}\nError: ${e.getLocalizedMessage()}"
            currentBuild.result = 'FAILURE'
        } 
        finally {
            // Query jobIsRunning jenkins helper for each pipeline
            pipelines.each { pipeline ->
                def inprogress = true

                while (inprogress) {
                    println "Checking if ${pipeline} is running..."
                    if (JobHelper.jobIsRunning(pipeline as String)) {
                        println "${pipeline} is running. Sleeping..."
                        sleep(900) // sleep for 15mins
                    }
                    else {
                        inprogress = false                    
                    }
                }
            }
            // No pipelines running or queued up
            println "No piplines running or scheduled. Running regeneration job..."
        }
    }

    context.stage("Regenerate") {
        // Download openjdk-build
        def Build = context.library(identifier: 'openjdk-build@master').Build

        // Get all pipelines (use jenkins api)
        def parser = new JsonSlurper()
        def pipelines = []

        try {
            def get = new URL("https://ci.adoptopenjdk.net/job/build-scripts/api/json?tree=jobs[name]&pretty=true&depth1").openConnection()
            def rc = get.getResponseCode()
            def response = parser.parseText(get.getInputStream().getText())

            // Parse api response
            response.jobs.name.each{ job -> 
                if (job.contains("pipeline")) {
                    pipelines.add(job)
                }
            }

        } catch (Exception e) {
            // Failed to connect to jenkins api or a parsing error occured
            println "Failure on jenkins api connection or parsing. API response code: ${rc}\nError: ${e.getLocalizedMessage()}"
            currentBuild.result = 'FAILURE'
        } 

        pipelines.each { pipeline -> 
            // Generate a job from template at `create_job_from_template.groovy`
            def createJob(jobName, jobFolder, IndividualBuildConfig config) {
                Map<String, ?> params = config.toMap().clone() as Map
                params.put("JOB_NAME", jobName)
                params.put("JOB_FOLDER", jobFolder)

                params.put("GIT_URI", scmVars["GIT_URL"])
                if (scmVars["GIT_BRANCH"] != "detached") {
                    params.put("GIT_BRANCH", scmVars["GIT_BRANCH"])
                } else {
                    params.put("GIT_BRANCH", scmVars["GIT_COMMIT"])
                }

                params.put("BUILD_CONFIG", config.toJson())

                def create = context.jobDsl targets: "pipelines/build/common/create_job_from_template.groovy", ignoreExisting: false, additionalParameters: params

                return create
            }
        }
    }

    context.stage("Publish") {

    }
}