@Library('local-lib@master')
import common.IndividualBuildConfig
import groovy.json.JsonSlurper

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
    final def context

    /**
     * Queries the Jenkins API for the pipeline names
     * @return pipelines
     */
    def queryJenkinsAPI() {
        try {
            def parser = new JsonSlurper()

            def get = new URL("https://ci.adoptopenjdk.net/job/build-scripts/api/json?tree=jobs[name]&pretty=true&depth1").openConnection()
            def rc = get.getResponseCode()
            def response = parser.parseText(get.getInputStream().getText())
            
            def pipelines = []

            // Parse api response to only extract the pipeline jobnames
            response.jobs.name.each{ job -> 
                if (job.contains("pipeline")) {
                    pipelines.add(job) //e.g. openjdk8-pipeline
                }
            }
            return pipelines;

        } catch (Exception e) {
            // Failed to connect to jenkins api or a parsing error occured
            throw new RuntimeException("Failure on jenkins api connection or parsing. API response code: ${rc}\nError: ${e.getLocalizedMessage()}")
        } 
    }

    context.stage("Check") {
        // Download jenkins helper
        def JobHelper = context.library(identifier: 'openjdk-jenkins-helper@master').JobHelper

        // Get all pipelines (use jenkins api)
        def pipelines = queryJenkinsAPI()
        
        // Query jobIsRunning jenkins helper for each pipeline
        def sleepTime = 900

        println "[INFO] Job regeneration cannot run if there are pipelines in progress or queued\nPipelines:"
        pipelines.each { pipeline -> 
            println pipeline
        }

        pipelines.each { pipeline ->
            def inProgress = true
               
            while (inProgress) {
                println "Checking if ${pipeline} is running or queued..."
                if (JobHelper.jobIsRunning(pipeline as String)) {
                    println "${pipeline} is running. Sleeping for ${sleepTime} while awaiting ${pipeline} to complete..."
                    sleep(sleepTime)
                }
                else {
                    println "${pipeline} has no jobs queued and is currently idle"
                    inProgress = false                    
                }
            }
        }
        // No pipelines running or queued up
        println "No piplines running or scheduled. Running regeneration job..."
    } // end Check stage...

    context.stage("Regenerate") {
        // Download openjdk-build
        def Build = context.library(identifier: 'openjdk-build@master').Build

        /**
        * Returns version number from the jobname or pipeline
        * @param name
        */
        def getVersionNumber(name){
            def regex = name =~ /[0-9]+[0-9]?/
            return regex[0]
        }

        /**
        * Returns a list of the job names of downstream builds
        * @param jobName
        * @return
        */
        def getJobNames(jobName) { 
            // Get all buildConfigurations from file
            // i.e. openjdk11_pipeline.groovy
            Closure openjdkPipeline = load "${WORKSPACE}/pipelines/build/${jobName.tr('-', '_')}.groovy"
            def buildConfigs = openjdkPipeline.buildConfigurations

            // Extract OS, Arch and variant? for each config
            def configs = []

            buildConfigs.each { target ->
                def platformConfig = buildConfigs.get(target.key) as Map<String, ?>

                target.value.each { variant ->
                    configs.add("${platformConfig.os}-${platformConfig.arch}-${variant}") // TODO: Figure out how to specify the variant
                }   
            return configs 
        }

        /**
        * Returns the full path of the job folder. Utilises the JobHelper.
        * @return
        */
        def getJobFolder(jobName) {
            def JobHelper = context.library(identifier: 'openjdk-jenkins-helper@master').JobHelper

            // Parse the full path
            def path = JobHelper.getJobFolder(jobName as String).substring(0, job.fullProjectName.lastIndexOf("/"))
            return path + "/jobs/"
        }

        // Get all pipelines (use jenkins api)
        def pipelines = queryJenkinsAPI()

        // Generate a job from template at `create_job_from_template.groovy`
        pipelines.each { pipeline -> 
            // Get pipeline version number
            // i.e. jdk11u
            def version = "jdk${getVersionNumber(pipeline)}u"

            // Get pipeline configurations
            // i.e. linux-x64-hotspot
            def pipelineConfigs = getJobNames(pipeline as String)

            pipelineConfigs.each { config -> 
                // Get job name
                // i.e. jdk11u-linux-x64-hotspot
                def jobTopName = "${version}-${config}"

                // Get job folder
                // i.e jdk11u/jobs/
                def jobFolder = getJobFolder(pipeline as String)

                context.library(identifier: 'openjdk-build@master').Build // TODO: Check if this is needed (swapping back from the jenkins helper)

                // Final job name
                // i.e jdk11u/jobs/jdk11u-linux-x64-hotspot
                def downstreamJobName = "${jobFolder}/${version}-${jobTopName}"

                Closure configureBuild = load "${WORKSPACE}/pipelines/build/common/build_base_file.groovy"
                configureBuild().createJob(jobTopName, jobFolder, config) // TODO: Need to figure out how to pass in the config
            }

            /** CURRENT CREATEJOB FUNCTION IN OPENJDK-BUILD
            def createJob(pipeline, jobFolder, IndividualBuildConfig config) {
            Map<String, ?> params = config.toMap().clone() as Map
            params.put("JOB_NAME", pipeline)
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
            */
        }

    } // end Regenerate stage...

    context.stage("Publish") {

    } // end Publish stage...
}