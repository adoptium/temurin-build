import NodeHelper
@Library('openjdk-jenkins-helper@master')
import groovy.json.JsonOutput

import java.util.regex.Matcher

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

class VersionInfo {
    Integer major // 8
    Integer minor // 0
    Integer security // 181
    Integer build // 8
    String opt
    String version
    String pre
    Integer adopt_build_number = 1
    String semver

    VersionInfo() {
    }

    VersionInfo parse(String PUBLISH_NAME, String ADOPT_BUILD_NUMBER) {

        if (PUBLISH_NAME != null) {
            if (!matchPre223(PUBLISH_NAME)) {
                match223(PUBLISH_NAME)
            }
        }

        if (ADOPT_BUILD_NUMBER) {
            adopt_build_number = Integer.parseInt(ADOPT_BUILD_NUMBER)
        }

        semver = formSemver()
        return this
    }

    private Integer or0(Matcher matched, String groupName) {
        def number = matched.group(groupName)
        if (number) {
            return number as Integer
        } else {
            return 0
        }
    }

    private boolean matchPre223(versionString) {
        final pre223regex = "jdk\\-?(?<version>(?<major>[0-8]+)(u(?<update>[0-9]+))?(-b(?<build>[0-9]+))(_(?<opt>[-a-zA-Z0-9\\.]+))?)"
        final matched = versionString =~ /${pre223regex}/

        if (matched.matches()) {
            major = or0(matched, 'major')
            minor = 0
            security = or0(matched, 'update')
            build = or0(matched, 'build')
            if (matched.group('opt') != null) opt = matched.group('opt')
            version = matched.group('version')

            return true
        }
        return false
    }

    private boolean match223(versionString) {
        //Regexes based on those in http://openjdk.java.net/jeps/223
        // Technically the standard supports an arbitrary number of numbers, we will support 3 for now
        final vnumRegex = "(?<major>[0-9]+)(\\.(?<minor>[0-9]+))?(\\.(?<security>[0-9]+))?"
        final preRegex = "(?<pre>[a-zA-Z0-9]+)"
        final buildRegex = "(?<build>[0-9]+)"
        final optRegex = "(?<opt>[-a-zA-Z0-9\\.]+)"

        List<String> version223Regexs = [
                "(?:jdk\\-)(?<version>${vnumRegex}(\\-${preRegex})?\\+${buildRegex}(\\-${optRegex})?)".toString(),
                "(?:jdk\\-)(?<version>${vnumRegex}\\-${preRegex}(\\-${optRegex})?)".toString(),
                "(?:jdk\\-)(?<version>${vnumRegex}(\\+\\-${optRegex})?)".toString()
        ]

        for (String regex : version223Regexs) {
            final matched223 = versionString =~ /^${regex}.*/
            if (matched223.matches()) {
                major = or0(matched223, 'major')
                minor = or0(matched223, 'minor')
                security = or0(matched223, 'security')
                if (matched223.group('pre') != null) pre = matched223.group('pre')
                build = or0(matched223, 'build')
                if (matched223.group('opt') != null) opt = matched223.group('opt')
                version = matched223.group('version')
                return true
            }
        }

        return false
    }

    String formSemver() {
        if (major != null) {
            def semver = major + "." + minor + "." + security

            if (pre) {
                semver += "-" + pre
            }

            semver += "+"
            semver += (build ?: "0")
            semver += "." + adopt_build_number
            return semver
        } else {
            return null
        }
    }
}

//@TypeChecked(extensions = "JenkinsTypeCheckHelperExtension")
class Build {
    String SCM_REF
    String NODE_LABEL
    String JAVA_TO_BUILD
    String JDK_BOOT_VERSION
    String CONFIGURE_ARGS
    String BUILD_ARGS
    String ARCHITECTURE
    String VARIANT
    String TARGET_OS
    String ADDITIONAL_FILE_NAME_TAG
    String OVERRIDE_FILE_NAME_VERSION
    boolean ENABLE_TESTS
    boolean CLEAN_WORKSPACE
    boolean RELEASE
    String PUBLISH_NAME
    String TEST_LIST
    String ADOPT_BUILD_NUMBER

    def context
    def env
    def currentBuild

    Integer getJavaVersionNumber() {
        // version should be something like "jdk8u"
        def matcher = (JAVA_TO_BUILD =~ /(\d+)/)
        List<String> list = matcher[0] as List
        return Integer.parseInt(list[1] as String)
    }

    def determineTestJobName(testType) {

        def variant
        def number = getJavaVersionNumber()

        if (VARIANT == "openj9") {
            variant = "j9"
        } else {
            variant = "hs"
        }

        def arch = ARCHITECTURE
        if (arch == "x64") {
            arch = "x86-64"
        }

        def os = TARGET_OS
        if (os == "mac") {
            os = "macos"
        }

        def jobName = "openjdk${number}_${variant}_${testType}_${arch}_${os}"

        if (ADDITIONAL_FILE_NAME_TAG) {
            switch (ADDITIONAL_FILE_NAME_TAG) {
                case ~/.*linuxXL.*/: jobName += "_linuxXL"; break
                case ~/.*macosXL.*/: jobName += "_macosXL"; break
            }
        }
        return "${jobName}"
    }

    def runTests() {
        def testStages = [:]

        List testList = TEST_LIST.split(",") as List
        testList.each { testType ->
            // For each requested test, i.e 'openjdktest', 'systemtest', 'perftest', 'externaltest', call test job
            try {
                context.println "Running test: ${testType}"
                testStages["${testType}"] = {
                    context.stage("${testType}") {

                        // example jobName: openjdk10_hs_externaltest_x86-64_linux
                        def jobName = determineTestJobName(testType)

                        if (JobHelper.jobIsRunnable(jobName)) {
                            context.catchError {
                                context.build job: jobName,
                                        propagate: false,
                                        parameters: [
                                                context.string(name: 'UPSTREAM_JOB_NUMBER', value: "${env.BUILD_NUMBER}"),
                                                context.string(name: 'UPSTREAM_JOB_NAME', value: "${env.JOB_NAME}"),
                                                context.string(name: 'RELEASE_TAG', value: "${SCM_REF}")]
                            }
                        } else {
                            context.println "Requested test job that does not exist or is disabled: ${jobName}"
                        }
                    }
                }
            } catch (Exception e) {
                context.println "Failed execute test: ${e.getLocalizedMessage()}"
            }
        }
        return testStages
    }

    def sign() {
        // Sign and archive jobs if needed
        if (TARGET_OS == "windows" || TARGET_OS == "mac") {
            context.node('master') {
                context.stage("sign") {
                    def filter = ""
                    def certificate = ""

                    def nodeFilter = "${TARGET_OS}&&build"

                    if (TARGET_OS == "windows") {
                        filter = "**/OpenJDK*_windows_*.zip"
                        certificate = "C:\\Users\\jenkins\\windows.p12"

                    } else if (TARGET_OS == "mac") {
                        filter = "**/OpenJDK*_mac_*.tar.gz"
                        certificate = "\"Developer ID Application: London Jamocha Community CIC\""

                        // currently only macos10.10 can sign
                        nodeFilter = "${nodeFilter}&&macos10.10"
                    }

                    def params = [
                            context.string(name: 'UPSTREAM_JOB_NUMBER', value: "${env.BUILD_NUMBER}"),
                            context.string(name: 'UPSTREAM_JOB_NAME', value: "${env.JOB_NAME}"),
                            context.string(name: 'OPERATING_SYSTEM', value: "${TARGET_OS}"),
                            context.string(name: 'FILTER', value: "${filter}"),
                            context.string(name: 'CERTIFICATE', value: "${certificate}"),
                            ['$class': 'LabelParameterValue', name: 'NODE_LABEL', label: "${nodeFilter}"],
                    ]

                    def signJob = context.build job: "build-scripts/release/sign_build",
                            propagate: true,
                            parameters: params

                    //Copy signed artifact back and rearchive
                    context.sh "rm workspace/target/* || true"

                    context.copyArtifacts(
                            projectName: "build-scripts/release/sign_build",
                            selector: context.specific("${signJob.getNumber()}"),
                            filter: 'workspace/target/*',
                            fingerprintArtifacts: true,
                            target: "workspace/target/",
                            flatten: true)

                    context.sh 'for file in $(ls workspace/target/*.tar.gz workspace/target/*.zip); do sha256sum "$file" > $file.sha256.txt ; done'
                    context.archiveArtifacts artifacts: "workspace/target/*"
                }
            }
        }
    }


    private void buildMacInstaller(VersionInfo versionData) {
        def filter = "**/OpenJDK*_mac_*.tar.gz"
        def certificate = "Developer ID Installer: London Jamocha Community CIC"

        // currently only macos10.10 can build an installer
        def nodeFilter = "${TARGET_OS}&&macos10.10&&build"

        def installerJob = context.build job: "build-scripts/release/create_installer_mac",
                propagate: true,
                parameters: [
                        context.string(name: 'UPSTREAM_JOB_NUMBER', value: "${env.BUILD_NUMBER}"),
                        context.string(name: 'UPSTREAM_JOB_NAME', value: "${env.JOB_NAME}"),
                        context.string(name: 'FILTER', value: "${filter}"),
                        context.string(name: 'FULL_VERSION', value: "${versionData.semver}"),
                        context.string(name: 'MAJOR_VERSION', value: "${versionData.major}"),
                        context.string(name: 'CERTIFICATE', value: "${certificate}"),
                        ['$class': 'LabelParameterValue', name: 'NODE_LABEL', label: "${nodeFilter}"]
                ]

        context.copyArtifacts(
                projectName: "build-scripts/release/create_installer_mac",
                selector: context.specific("${installerJob.getNumber()}"),
                filter: 'workspace/target/*',
                fingerprintArtifacts: true,
                target: "workspace/target/",
                flatten: true)
    }

    private void buildWindowsInstaller(VersionInfo versionData) {
        def filter = "**/OpenJDK*_windows_*.zip"
        def certificate = "C:\\Users\\jenkins\\windows.p12"

        def installerJob = context.build job: "build-scripts/release/create_installer_windows",
                propagate: true,
                parameters: [
                        context.string(name: 'UPSTREAM_JOB_NUMBER', value: "${env.BUILD_NUMBER}"),
                        context.string(name: 'UPSTREAM_JOB_NAME', value: "${env.JOB_NAME}"),
                        context.string(name: 'FILTER', value: "${filter}"),
                        context.string(name: 'PRODUCT_MAJOR_VERSION', value: "${versionData.major}"),
                        context.string(name: 'PRODUCT_MINOR_VERSION', value: "${versionData.minor}"),
                        context.string(name: 'PRODUCT_MAINTENANCE_VERSION', value: "${versionData.security}"),
                        context.string(name: 'PRODUCT_PATCH_VERSION', value: "${versionData.build}"),
                        context.string(name: 'JVM', value: "${VARIANT}"),
                        context.string(name: 'SIGNING_CERTIFICATE', value: "${certificate}"),
                        context.string(name: 'ARCH', value: "${ARCHITECTURE}"),
                        ['$class': 'LabelParameterValue', name: 'NODE_LABEL', label: "${TARGET_OS}&&wix"]
                ]

        context.copyArtifacts(
                projectName: "build-scripts/release/create_installer_windows",
                selector: context.specific("${installerJob.getNumber()}"),
                filter: 'wix/ReleaseDir/*',
                fingerprintArtifacts: true,
                target: "workspace/target/",
                flatten: true)
    }

    def buildInstaller() {
        VersionInfo versionData = new VersionInfo().parse(PUBLISH_NAME, ADOPT_BUILD_NUMBER)

        if (versionData.major == null) {
            context.println "Failed to parse version number, possibly a nightly? Skipping installer steps"
            return
        }

        context.node('master') {
            context.stage("installer") {
                try {
                    switch (TARGET_OS) {
                        case "mac": buildMacInstaller(versionData); break
                        case "windows": buildWindowsInstaller(versionData); break
                        default: return; break
                    }
                    context.sh 'for file in $(ls workspace/target/*.tar.gz workspace/target/*.pkg workspace/target/*.msi); do sha256sum "$file" > $file.sha256.txt ; done'
                    context.archiveArtifacts artifacts: "workspace/target/*"
                } catch (e) {
                    context.println("Failed to build installer ${TARGET_OS} ${e}")
                }
            }
        }
    }


    List<String> listArchives() {
        return context.sh(
                script: """find workspace/target/ | egrep '.tar.gz|.zip'""",
                returnStdout: true,
                returnStatus: false
        )
                .trim()
                .split('\n')
                .toList()
    }

    def formMetadata() {
        return [
                WARNING     : "THIS METADATA FILE IS STILL IN ALPHA DO NOT USE ME",
                os          : TARGET_OS,
                arch        : ARCHITECTURE,
                variant     : VARIANT,
                version     : JAVA_TO_BUILD,
                scmRef      : SCM_REF,
                version_data: new VersionInfo().parse(PUBLISH_NAME, ADOPT_BUILD_NUMBER)
        ]
    }

    def writeMetadata(List<String> filesCreated) {
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
        context.node("master") {
            //Clean workspace on parent
            context.sh 'find . -regex ".*/OpenJDK.*\\.json" -exec rm ./{} \\; || true'
            filesCreated.each({ file ->
                def type = "jdk"
                if (file.contains("-jre")) {
                    type = "jre"
                }

                Map<String, ?> data = formMetadata().clone() as Map
                data.put("binary_type", type)

                context.writeFile file: "${file}.json", text: JsonOutput.prettyPrint(JsonOutput.toJson(data))
            })
            context.archiveArtifacts artifacts: "workspace/target/**/*.json"
        }
    }

    def determineFileName() {
        String javaToBuild = JAVA_TO_BUILD
        String architecture = ARCHITECTURE
        String os = TARGET_OS
        String variant = VARIANT
        String additionalFileNameTag = ADDITIONAL_FILE_NAME_TAG
        String overrideFileNameVersion = OVERRIDE_FILE_NAME_VERSION

        def extension = "tar.gz"

        if (os == "windows") {
            extension = "zip"
        }

        javaToBuild = javaToBuild.toUpperCase()

        def fileName = "Open${javaToBuild}-jdk_${architecture}_${os}_${variant}"

        if (additionalFileNameTag) {
            fileName = "${fileName}_${additionalFileNameTag}"
        }

        if (overrideFileNameVersion) {
            fileName = "${fileName}_${overrideFileNameVersion}"
        } else if (PUBLISH_NAME) {
            def nameTag = PUBLISH_NAME
                    .replace("jdk-", "")
                    .replaceAll("\\+", "_")

            fileName = "${fileName}_${nameTag}"
        } else {
            def timestamp = new Date().format("YYYY-MM-dd-HH-mm", TimeZone.getTimeZone("UTC"))

            fileName = "${fileName}_${timestamp}"
        }


        fileName = "${fileName}.${extension}"

        context.println "Filename will be: $fileName"
        return fileName
    }

    def build() {
        try {

            def filename = determineFileName()
            def metadata = formMetadata()

            context.println "Executing tests: ${TEST_LIST}"
            context.println "Build num: ${env.BUILD_NUMBER}"
            context.println "File name: ${filename}"
            context.println "Metadata: ${JsonOutput.prettyPrint(JsonOutput.toJson(metadata))}"

            List<String> filesCreated = []

            def enableTests = Boolean.valueOf(ENABLE_TESTS)
            def cleanWorkspace = Boolean.valueOf(CLEAN_WORKSPACE)


            context.stage("queue") {
                if (NodeHelper.nodeIsOnline(NODE_LABEL)) {
                    context.node(NODE_LABEL) {
                        context.stage("build") {
                            if (cleanWorkspace) {
                                try {
                                    context.cleanWs notFailBuild: true
                                } catch (e) {
                                    context.println "Failed to clean ${e}"
                                }
                            }
                            context.checkout context.scm
                            try {
                                context.withEnv(["FILENAME=${filename}"]) {
                                    context.sh "./build-farm/make-adopt-build-farm.sh"
                                }
                                context.archiveArtifacts artifacts: "workspace/target/*"
                                filesCreated = listArchives()
                            } finally {
                                if (TARGET_OS == "aix") {
                                    context.cleanWs notFailBuild: true
                                }
                            }
                        }
                    }
                } else {
                    context.error("No node of this type exists: ${NODE_LABEL}")
                    return
                }
            }

            if (enableTests && TEST_LIST.trim().length() > 0) {
                try {
                    def testStages = runTests()
                    context.parallel testStages
                } catch (Exception e) {
                    context.println "Failed test: ${e}"
                }
            }

            writeMetadata(filesCreated)

            // Sign and archive jobs if needed
            sign()

            //buildInstaller if needed
            buildInstaller()
        } catch (Exception e) {
            currentBuild.result = 'FAILURE'
            context.println "Execution error: " + e.getMessage()
        }
    }
}

if (!binding.hasVariable("context")) {
    context = this
}

if (String.class.isInstance(ENABLE_TESTS)) {
    ENABLE_TESTS = Boolean.parseBoolean(ENABLE_TESTS as String)
}

if (String.class.isInstance(CLEAN_WORKSPACE)) {
    CLEAN_WORKSPACE = Boolean.parseBoolean(CLEAN_WORKSPACE as String)
}

if (String.class.isInstance(RELEASE)) {
    RELEASE = Boolean.parseBoolean(RELEASE as String)
}

new Build(SCM_REF: SCM_REF,
        NODE_LABEL: NODE_LABEL,
        JAVA_TO_BUILD: JAVA_TO_BUILD,
        JDK_BOOT_VERSION: JDK_BOOT_VERSION,
        CONFIGURE_ARGS: CONFIGURE_ARGS,
        BUILD_ARGS: BUILD_ARGS,
        ARCHITECTURE: ARCHITECTURE,
        VARIANT: VARIANT,
        TARGET_OS: TARGET_OS,
        ADDITIONAL_FILE_NAME_TAG: ADDITIONAL_FILE_NAME_TAG,
        OVERRIDE_FILE_NAME_VERSION: OVERRIDE_FILE_NAME_VERSION,
        ENABLE_TESTS: ENABLE_TESTS,
        CLEAN_WORKSPACE: CLEAN_WORKSPACE,
        PUBLISH_NAME: PUBLISH_NAME,
        ADOPT_BUILD_NUMBER: ADOPT_BUILD_NUMBER,
        TEST_LIST: TEST_LIST,
        RELEASE: RELEASE,

        context: context,
        env: env,
        currentBuild: currentBuild).build()
