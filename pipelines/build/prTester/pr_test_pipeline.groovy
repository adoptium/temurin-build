import groovy.json.JsonSlurper

import static groovy.json.JsonOutput.prettyPrint
import static groovy.json.JsonOutput.toJson

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

class PullRequestTestPipeline implements Serializable {

    def context
    def env
    def currentBuild

    String branch
    String gitRepo
    Map<String, ?> testConfigurations
    List<Integer> javaVersions

    def runTests() {

        def jobs = [:]

        javaVersions.each({ javaVersion ->
            def target = context.load "pipelines/jobs/configurations/jdk${javaVersion}u.groovy"

            def config = [
                    PR_BUILDER          : true,
                    GIT_URL             : gitRepo,
                    BRANCH              : "${branch}",
                    BUILD_FOLDER        : "build-scripts-pr-tester/build-test",
                    JOB_NAME            : "openjdk${javaVersion}",
                    SCRIPT              : "pipelines/build/openjdk${javaVersion}_pipeline.groovy",
                    targetConfigurations: target.targetConfigurations,
                    propagateFailures   : true
            ]

            jobs["Test building Java ${javaVersion}"] = {
                context.catchError {
                    context.stage("Test building Java ${javaVersion}") {
                        context.jobDsl targets: "pipelines/jobs/pipeline_job_template.groovy", ignoreExisting: false, additionalParameters: config
                        context.build job: "${config.BUILD_FOLDER}/openjdk${javaVersion}",
                                propagate: true,
                                parameters: [
                                        [$class: 'StringParameterValue', name: 'targetConfigurations', value: prettyPrint(toJson(testConfigurations))],
                                        context.string(name: 'releaseType', value: "Nightly Without Publish")
                                ]
                    }
                }
            }
        })
        context.parallel jobs
    }
}

Map<String, ?> defaultTestConfigurations = [
        "x64Linux": [
                "hotspot"
        ]
]

List<Integer> defaultJavaVersions = [8, 11, 14, 15]

defaultGitRepo = "https://github.com/AdoptOpenJDK/openjdk-build"

return {
    String branch,
    def currentBuild,
    def context,
    def env,
    String testConfigurations = null,
    String versions = null,
    String gitRepo = defaultGitRepo
        ->

        Map<String, ?> testConfig = defaultTestConfigurations
        List<Integer> javaVersions = defaultJavaVersions

        if (gitRepo == null) {
            gitRepo = defaultGitRepo
        }

        if (testConfigurations != null) {
            testConfig = new JsonSlurper().parseText(testConfigurations) as Map
        }

        if (versions != null) {
            javaVersions = new JsonSlurper().parseText(versions) as List<Integer>
        }

        return new PullRequestTestPipeline(
                gitRepo: gitRepo,
                branch: branch,
                testConfigurations: testConfig,
                javaVersions: javaVersions,

                context: context,
                env: env,
                currentBuild: currentBuild)
}
