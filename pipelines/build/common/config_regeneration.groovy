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
    context.stage("Check") {
        // Download jenkins helper
        def JobHelper = context.library(identifier: 'openjdk-jenkins-helper@master').JobHelper

        // Get all pipelines
        def directory = new File("${WORKSPACE}/pipelines/build")
        def path = directory.listFiles({d, f-> f ==~ /.*.groovy/} as FilenameFilter).sort()

        path.each { pipeline -> 
            def match = path =~ /[^\/][a-z]+[0-9]+_[a-z]+/
            def pipeline = match[0].tr('_', '-') // Match pipeline job name

            // Query jobIsRunning jenkins helper 
            def inprogress = true

            while (inprogress) {
                echo "Checking if ${pipeline} is running..."
                if (JobHelper.jobIsRunning(pipeline as String)) {
                    echo "${pipeline} is running. Sleeping..."
                    sleep(900) // sleep for 15mins
                }
                else {
                    inprogress = false                    
                }
            }
        }
        // No pipelines running or queued up
        echo "No piplines running or scheduled. Running regeneration job..."
    }

    context.stage("Regenerate") {

    }

    context.stage("Publish") {

    }
}