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
import groovy.json.JsonOutput
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


/*
    Extracts the named regex element `groupName` from the `matched` regex matcher and adds it to `map.name`
    If it is not present add `0`
 */

def addOr0(map, name, matched, groupName) {
    def number = matched.group(groupName)
    if (number) {
        map.put(name, number as Integer)
    } else {
        map.put(name, 0)
    }
    return map
}

def matchPre223(version) {
    final pre223regex = "jdk(?<version>(?<major>[0-8]+)(u(?<update>[0-9]+))?(-b(?<build>[0-9]+))(_(?<opt>[-a-zA-Z0-9\\.]+))?)"
    final matched = version =~ /${pre223regex}/

    if (matched.matches()) {
        def result = [:]
        result = addOr0(result, 'major', matched, 'major')
        result.put('minor', 0)
        result = addOr0(result, 'security', matched, 'update')
        result = addOr0(result, 'build', matched, 'build')
        if (matched.group('opt') != null) result.put('opt', matched.group('opt'))
        result.put('version', matched.group('version'))

        return result
    } else {
        return null
    }
}

def match223(version) {
    //Regexes based on those in http://openjdk.java.net/jeps/223
    // Technically the standard supports an arbitrary number of numbers, we will support 3 for now
    final vnumRegex = "(?<major>[0-9]+)(\\.(?<minor>[0-9]+))?(\\.(?<security>[0-9]+))?"
    final pre = "(?<pre>[a-zA-Z0-9]+)"
    final build = "(?<build>[0-9]+)"
    final opt = "(?<opt>[-a-zA-Z0-9\\.]+)"

    final version223Regexs = [
            "(?:jdk\\-)(?<version>${vnumRegex}(\\-${pre})?\\+${build}(\\-${opt})?)",
            "(?:jdk\\-)(?<version>${vnumRegex}\\-${pre}(\\-${opt})?)",
            "(?:jdk\\-)(?<version>${vnumRegex}(\\+\\-${opt})?)"
    ]

    return version223Regexs
            .findResult({ regex ->
        final matched223 = version =~ /${regex}/
        if (matched223.matches()) {
            def result = [:]
            result = addOr0(result, 'major', matched223, 'major')
            result = addOr0(result, 'minor', matched223, 'minor')
            result = addOr0(result, 'security', matched223, 'security')
            if (matched223.group('pre') != null) result.put('pre', matched223.group('pre'))
            result = addOr0(result, 'build', matched223, 'build')
            if (matched223.group('opt') != null) result.put('opt', matched223.group('opt'))
            result.put('version', matched223.group('version'))

            return result
        } else {
            return null
        }
    })
}

private void formSemver(data, config) {
    def semver = data.major + "." + data.minor + "." + data.security

    if (data.pre) {
        semver += "-" + data.pre
    }

    def joiner = new java.util.StringJoiner('.')
    joiner.add(data.build ?: "0")
    joiner.add(config.adoptBuildNumber ?: "0")
    semver += "+" + joiner.toString()
    return semver
}

def formVersionData(config) {

    def data = [:]

    if (config.adoptBuildNumber) {
        data.put('adopt_build_number', config.adoptBuildNumber)
    }

    if (config.parameters.TAG != null) {
        def pre223 = matchPre223(config.parameters.TAG)
        if (pre223 != null) {
            data = pre223
        } else {
            data = match223(config.parameters.TAG)
        }
    }

    data.put('semver', formSemver(data, config))


    return data
}


def determineTestJobName(config, testType) {

    def variant

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

    def jobName = "openjdk${number}_${variant}_${testType}_${arch}_${os}"

    if (config.parameters.containsKey('ADDITIONAL_FILE_NAME_TAG')) {
        jobName += "_${config.parameters.ADDITIONAL_FILE_NAME_TAG}"
    }
    return "${jobName}"
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
                                                 string(name: 'UPSTREAM_JOB_NAME', value: "${env.JOB_NAME}"),
                                                 string(name: 'RELEASE_TAG', value: "${TAG}")]
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


def buildInstaller(config) {
    if (config.os == "mac") {
        node('master') {
            stage("installer") {

                def versionData = formVersionData(config)


                def filter = "**/OpenJDK*_mac_*.tar.gz"
                def certificate = "\"Developer ID Application: London Jamocha Community CIC\""

                def installerJob = build job: "build-scripts/release/create_installer_mac",
                        propagate: true,
                        parameters: [string(name: 'UPSTREAM_JOB_NUMBER', value: "${env.BUILD_NUMBER}"),
                                     string(name: 'UPSTREAM_JOB_NAME', value: "${env.JOB_NAME}"),
                                     string(name: 'FILTER', value: "${filter}"),
                                     string(name: 'FULL_VERSION', value: "${versionData.semver}"),
                                     string(name: 'MAJOR_VERSION', value: "${versionData.major}"),
                                     string(name: 'CERTIFICATE', value: "${certificate}"),
                                     [$class: 'LabelParameterValue', name: 'NODE_LABEL', label: "${config.os}&&build"],
                        ]

                copyArtifacts(
                        projectName: "build-scripts/release/create_installer_mac",
                        selector: specific("${installerJob.getNumber()}"),
                        filter: 'workspace/target/*',
                        fingerprintArtifacts: true,
                        target: "workspace/target/",
                        flatten: true)

                sh 'for file in $(ls workspace/target/*.tar.gz workspace/target/*.pkg); do sha256sum "$file" > $file.sha256.txt ; done'
                archiveArtifacts artifacts: "workspace/target/*"
            }
        }
    }
}

def listArchives() {
    return sh(
            script: """find workspace/target/ | egrep '.tar.gz|.zip'""",
            returnStdout: true,
            returnStatus: false
    )
            .trim()
            .split('\n')
}

def writeMetadata(config, filesCreated) {

    def buildMetadata = [
            WARNING     : "THIS METADATA FILE IS STILL IN ALPHA DO NOT USE ME",
            os          : config.os,
            arch        : config.arch,
            variant     : config.variant,
            version     : config.javaVersion,
            tag         : config.parameters.TAG,
            version_data: formVersionData(config)
    ]

    def type = "jdk";
    if (file.contains("-jre")) {
        type = "jre";
    }

    /*
    example data:
    {
        "WARNING": "THIS METADATA FILE IS STILL IN ALPHA DO NOT USE ME",
        "os": "linux",
        "arch": "x64",
        "variant": "hotspot",
        "version": "jdk8u",
        "tag": "jdk8u202-b08",
        "version_data": {
            "adopt_build_number": 2,
            "major": 8,
            "minor": 0,
            "security": 202,
            "build": 8,
            "version": "8u202-b08",
            "semver": "8.0.202+8.2"
        },
        "binary_type": "jdk"
    }
    */
    node("master") {
        filesCreated.each({ file ->

            data = buildMetadata.clone()
            data.put("binary_type", type)

            writeFile file: "${file}.json", text: JsonOutput.prettyPrint(JsonOutput.toJson(data))
        })
        archiveArtifacts artifacts: "workspace/target/**/*.json"
    }
}

try {
    def config = new JsonSlurper().parseText("${TEST_CONFIG}")
    println "Executing tests: ${config}"
    println "Build num: ${env.BUILD_NUMBER}"

    def filesCreated = [];

    def enableTests = Boolean.valueOf(ENABLE_TESTS)
    def cleanWorkspace = Boolean.valueOf(CLEAN_WORKSPACE)

    stage("queue") {
        if (NodeHelper.nodeIsOnline(NODE_LABEL)) {
            node(NODE_LABEL) {
                stage("build") {
                    if (cleanWorkspace) {
                        cleanWs notFailBuild: true
                    }

                    checkout scm
                    try {
                        sh "./build-farm/make-adopt-build-farm.sh"
                        archiveArtifacts artifacts: "workspace/target/*"
                        filesCreated = listArchives()
                    } finally {
                        if (config.os == "aix") {
                            cleanWs notFailBuild: true
                        }
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

    writeMetadata(config, filesCreated)

    // Sign and archive jobs if needed
    sign(config)

    //buildInstaller if needed
    buildInstaller(config)
} catch (Exception e) {
    currentBuild.result = 'FAILURE'
    println "Execution error: " + e.getMessage()
}

