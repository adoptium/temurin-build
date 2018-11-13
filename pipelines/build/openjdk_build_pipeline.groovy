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

@Library('openjdk-jenkins-helper@master')
import JobHelper
@Library('openjdk-jenkins-helper@master')
import JobHelper
import NodeHelper
import groovy.json.JsonSlurper

/**
 * This file is a template for running a build for a given configuration
 * A configuration is for example jdk10u-mac-x64-hotspot.
 *
 * This file is referenced by the pipeline template create_job_from_template.groovy
 *
 * A pipeline looks like:
 *  1. Check out and build JDK by calling build-farm/make-adopt-build-farm.sh
 *  2. Archive artifacts created by build
 *  3. Run all tests defined in the configuration
 *  4. Sign artifacts if needed and re-archive
 *
 */

def getJavaVersionNumber(version) {
    // version should be something like "jdk8u"
    def matcher = (version =~ /(\d+)/)
    return Integer.parseInt(matcher[0][1])
}

def determineTestJobName(config, testType) {

    def variant
    def number = getJavaVersionNumber(config.javaVersion)

    if (config.variant == "openj9") {
        variant = "j9"
    } else {
        variant = "hs"
    }

    def arch = config.arch
    if (arch == "x64") {
        arch = "x86-64"
    }

    def os = config.os
    if (os == "mac") {
        os = "macos"
    }

    return "openjdk${number}_${variant}_${testType}_${arch}_${os}"
}

def runTests(config) {
    def testStages = [:]

    config.test.each { testType ->
        // For each requested test, i.e 'openjdktest', 'systemtest', 'perftest', 'externaltest', call test job
        try {
            println "Running test: ${testType}}"
            testStages["${testType}"] = {
                stage("${testType}") {

                    // example jobName: openjdk10_hs_externaltest_x86-64_linux
                    def jobName = determineTestJobName(config, testType)

                    if (JobHelper.jobIsRunnable(jobName)) {
                        catchError {
                            build job: jobName,
                                    propagate: false,
                                    parameters: [string(name: 'UPSTREAM_JOB_NUMBER', value: "${env.BUILD_NUMBER}"),
                                                 string(name: 'UPSTREAM_JOB_NAME', value: "${env.JOB_NAME}")]
                        }
                    } else {
                        println "Requested test job that does not exist or is disabled: ${jobName}"
                    }
                }
            }
        } catch (Exception e) {
            println "Failed execute test: ${e.getLocalizedMessage()}"
        }
    }
    return testStages
}

def sign(config) {
    // Sign and archive jobs if needed
    if (config.os == "windows" || config.os == "mac") {
        node('master') {
            stage("sign") {
                def filter = ""
                def certificate = ""

                if (config.os == "windows") {
                    filter = "**/OpenJDK*_windows_*.zip"
                    certificate = "C:\\Users\\jenkins\\windows.p12"

                } else if (config.os == "mac") {
                    filter = "**/OpenJDK*_mac_*.tar.gz"
                    certificate = "\"Developer ID Application: London Jamocha Community CIC\""
                }

                def signJob = build job: "build-scripts/release/sign_build",
                        propagate: true,
                        parameters: [string(name: 'UPSTREAM_JOB_NUMBER', value: "${env.BUILD_NUMBER}"),
                                     string(name: 'UPSTREAM_JOB_NAME', value: "${env.JOB_NAME}"),
                                     string(name: 'OPERATING_SYSTEM', value: "${config.os}"),
                                     string(name: 'FILTER', value: "${filter}"),
                                     string(name: 'CERTIFICATE', value: "${certificate}"),
                                     [$class: 'LabelParameterValue', name: 'NODE_LABEL', label: "${config.os}&&build"],
                        ]

                //Copy signed artifact back and rearchive
                sh "rm workspace/target/* || true"

                copyArtifacts(
                        projectName: "build-scripts/release/sign_build",
                        selector: specific("${signJob.getNumber()}"),
                        filter: 'workspace/target/*',
                        fingerprintArtifacts: true,
                        target: "workspace/target/",
                        flatten: true)

                sh 'for file in $(ls workspace/target/*.tar.gz workspace/target/*.zip); do sha256sum "$file" > $file.sha256.txt ; done'
                archiveArtifacts artifacts: "workspace/target/*"
            }
        }
    }
}

try {
    def config = new JsonSlurper().parseText("${TEST_CONFIG}")
    println "Executing tests: ${config}"
    println "Build num: ${env.BUILD_NUMBER}"

    def enableTests = ENABLE_TESTS == "true"

    stage("build") {
        if (NodeHelper.nodeIsOnline(NODE_LABEL)) {
            node(NODE_LABEL) {
                if (config.cleanWorkspaceBeforeBuild) {
                    cleanWs notFailBuild: true
                }

                checkout scm
                try {
                    sh "./build-farm/make-adopt-build-farm.sh"
                    archiveArtifacts artifacts: "workspace/target/*"
                } finally {
                    if (config.os == "aix") {
                        cleanWs notFailBuild: true
                    }
                }
            }
        } else {
            error("No node of this type exists: ${NODE_LABEL}")
            return
        }
    }

    if (enableTests && config.test != false) {
        try {
            testStages = runTests(config)
            parallel testStages
        } catch (Exception e) {
            println "Failed test: ${e}"
        }
    }

    // Sign and archive jobs if needed
    sign(config)

} catch (Exception e) {
    currentBuild.result = 'FAILURE'
    println "Execution error: " + e.getMessage()
}

