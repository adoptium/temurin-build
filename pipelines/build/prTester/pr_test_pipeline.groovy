import groovy.json.JsonSlurper
import java.nio.file.NoSuchFileException

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
    def currentBuild

    String branch
    String gitRepo
    Map<String, ?> testConfigurations
    Map<String, ?> DEFAULTS_JSON
    List<Integer> javaVersions

    String BUILD_FOLDER = "build-scripts-pr-tester/build-test"

    /*
    * Creates a configuration for the top level pipeline job
    */
    Map<String, ?> generateConfig(def javaVersion) {
        return [
                PR_BUILDER          : true,
                TEST                : false,
                GIT_URL             : gitRepo,
                BRANCH              : "${branch}",
                BUILD_FOLDER        : BUILD_FOLDER,
                JOB_NAME            : "openjdk${javaVersion}-pipeline",
                SCRIPT              : "${DEFAULTS_JSON['scriptDirectories']['upstream']}/openjdk${javaVersion}_pipeline.groovy",
                disableJob          : false,
                triggerSchedule     : "0 0 31 2 0",
                targetConfigurations: testConfigurations
        ]
    }

    /*
    * Generates the top level pipeline job
    */
    def generatePipelineJob(def javaVersion) {
        Map<String, ?> config = generateConfig(javaVersion)
        context.checkout([$class: 'GitSCM', userRemoteConfigs: [[url: config.GIT_URL]], branches: [[name: branch]]])

        context.println "JDK${javaVersion} disableJob = ${config.disableJob}"
        context.jobDsl targets: DEFAULTS_JSON["jobTemplateDirectories"]["upstream"], ignoreExisting: false, additionalParameters: config
    }

    /*
    * Main function, called from the pr tester in jenkins itself
    */
    def runTests() {

        def jobs = [:]
        Boolean pipelineFailed = false

        context.println "loading ${context.WORKSPACE}/${DEFAULTS_JSON['scriptDirectories']['regeneration']}"
        Closure regenerationScript = context.load "${context.WORKSPACE}/${DEFAULTS_JSON['scriptDirectories']['regeneration']}"

        javaVersions.each({ javaVersion ->
            // generate top level job
            generatePipelineJob(javaVersion)
            context.println "[INFO] Running regeneration script..."

            // Load platform specific build configs
            def buildConfigurations
            Boolean updateRepo = false
            context.println "loading ${context.WORKSPACE}/${DEFAULTS_JSON['configDirectories']['build']}/jdk${javaVersion}_pipeline_config.groovy"
            try {
                buildConfigurations = context.load "${context.WORKSPACE}/${DEFAULTS_JSON['configDirectories']['build']}/jdk${javaVersion}_pipeline_config.groovy"
            } catch (NoSuchFileException e) {
                context.println "[WARNING] ${context.WORKSPACE}/${DEFAULTS_JSON['configDirectories']['build']}/jdk${javaVersion}_pipeline_config.groovy does not exist. Trying jdk${javaVersion}u_pipeline_config.groovy..."
                buildConfigurations = context.load "${context.WORKSPACE}/${DEFAULTS_JSON['configDirectories']['build']}/jdk${javaVersion}u_pipeline_config.groovy"
                updateRepo = true
            }

            String actualJavaVersion = updateRepo ? "jdk${javaVersion}u" : "jdk${javaVersion}"
            def excludedBuilds = ""

            // Generate downstream pipeline jobs
            regenerationScript(
                actualJavaVersion,
                buildConfigurations,
                testConfigurations,
                DEFAULTS_JSON,
                excludedBuilds,
                currentBuild,
                context,
                "build-scripts-pr-tester/build-test",
                gitRepo,
                branch,
                null,
                null,
                "https://ci.adoptopenjdk.net/job/build-scripts-pr-tester/job/build-test",
                null,
                null
            ).regenerate()

            context.println "[SUCCESS] All done!"

            // Run tester against the host pr
            jobs["Test building Java ${javaVersion}"] = {
                context.stage("Test building Java ${javaVersion}") {
                    try {
                        context.build job: "${BUILD_FOLDER}/openjdk${javaVersion}-pipeline",
                            propagate: true,
                            parameters: [
                                context.string(name: 'releaseType', value: "Nightly Without Publish"),
                                context.string(name: 'activeNodeTimeout', value: "0")
                            ]
                    } catch (err) {
                        context.println "[ERROR] ${actualJavaVersion} PIPELINE FAILED\n$err"
                        pipelineFailed = true
                    }
                }
            }
        })

        context.parallel jobs

        // Only clean up the space if the tester passed
        if (!pipelineFailed) {
            context.println "[INFO] Cleaning up..."
            context.cleanWs notFailBuild: true
        } else {
            context.println "[ERROR] Pipelines failed. Setting build result to FAILURE..."
            currentBuild.result = 'FAILURE'
        }
    }

}

Map<String, ?> defaultTestConfigurations = [
    "x64Linux": [
        "hotspot",
        "openj9"
    ],
    "aarch64Linux": [
        "hotspot",
        "openj9"
    ],
    "x64Windows": [
        "hotspot"
    ],
    "x64Mac": [
        "hotspot"
    ]
]

List<Integer> defaultJavaVersions = [8, 11, 15, 16]

return {
    String branch,
    def currentBuild,
    def context,
    String gitRepo,
    Map<String, ?> DEFAULTS_JSON,
    String testConfigurations = null,
    String versions = null
        ->

        context.load DEFAULTS_JSON['importLibraryScript']

        Map<String, ?> testConfig = defaultTestConfigurations
        List<Integer> javaVersions = defaultJavaVersions
        Map<String, ?> defaultJson = DEFAULTS_JSON

        if (gitRepo == null) {
            gitRepo = DEFAULTS_JSON['repository']['url']
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
            DEFAULTS_JSON: defaultJson,
            javaVersions: javaVersions,

            context: context,
            currentBuild: currentBuild
        )
}
