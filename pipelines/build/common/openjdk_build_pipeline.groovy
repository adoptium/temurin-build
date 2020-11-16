import common.IndividualBuildConfig
import common.MetaData
@Library('local-lib@master')
import common.VersionInfo
import groovy.json.*
import java.nio.file.NoSuchFileException
import org.jenkinsci.plugins.workflow.steps.FlowInterruptedException

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

class Build {
    final IndividualBuildConfig buildConfig

    final def context
    final def env
    final def currentBuild
    VersionInfo versionInfo = null
    String scmRef = ""
    String fullVersionOutput = ""
    String configureArguments = ""
    String j9Major = ""
    String j9Minor = ""
    String j9Security = ""
    String j9Tags = ""
    String vendorName = ""
    String buildSource = ""
    String riscvVersionPath = ""
    Map variantVersion = [:]

    // Declare timeouts for each critical stage (unit is HOURS)
    Map buildTimeouts = [
        API_REQUEST_TIMEOUT : 1,
        NODE_CLEAN_TIMEOUT : 1,
        NODE_CHECKOUT_TIMEOUT : 1,
        BUILD_JDK_TIMEOUT : 8,
        BUILD_ARCHIVE_TIMEOUT : 3,
        AIX_CLEAN_TIMEOUT : 1,
        MASTER_CLEAN_TIMEOUT : 1,
        DOCKER_CHECKOUT_TIMEOUT : 1,
        DOCKER_PULL_TIMEOUT : 2,
        SIGN_JOB_TIMEOUT : 2,
        INSTALLER_JOBS_TIMEOUT : 3
    ]

    /*
    Constructor
    */
    Build(IndividualBuildConfig buildConfig, def context, def env, def currentBuild) {
        this.buildConfig = buildConfig
        this.context = context
        this.currentBuild = currentBuild
        this.env = env
    }


    /*
    Returns the java version number for this job (e.g. 8, 11, 15, 16)
    */
    Integer getJavaVersionNumber() {
        def javaToBuild = buildConfig.JAVA_TO_BUILD
        // version should be something like "jdk8u" or "jdk" for HEAD
        Matcher matcher = javaToBuild =~ /.*?(?<version>\d+).*?/
        if (matcher.matches()) {
            return Integer.parseInt(matcher.group('version'))
        } else if ("jdk".equalsIgnoreCase(javaToBuild.trim())) {
            int headVersion
            try {
                context.timeout(time: buildTimeouts.API_REQUEST_TIMEOUT, unit: "HOURS") {
                    // Query the Adopt api to get the "tip_version"
                    def JobHelper = context.library(identifier: 'openjdk-jenkins-helper@master').JobHelper
                    context.println "Querying Adopt Api for the JDK-Head number (tip_version)..."

                    def response = JobHelper.getAvailableReleases(context)
                    headVersion = (int) response.getAt("tip_version")
                    context.println "Found Java Version Number: ${headVersion}"
                }
            } catch (FlowInterruptedException e) {
                context.println "[ERROR] Adopt API Request timeout (${buildTimeouts.API_REQUEST_TIMEOUT} HOURS) has been reached. Exiting..."
                throw new Exception()
            }
            return headVersion
        } else {
            context.error("Failed to read java version '${javaToBuild}'")
            throw new Exception()
        }
    }

    /*
    Calculates which test job we should execute for each requested test type.
    The test jobs all follow the same name naming pattern that is defined in the openjdk-tests repository.
    E.g. Test_openjdk11_hs_sanity.system_ppc64_aix
    */
    def determineTestJobName(testType) {

        def variant
        def number = getJavaVersionNumber()

        switch (buildConfig.VARIANT) {
            case "openj9": variant = "j9"; break
            case "corretto": variant = "corretto"; break
            case "dragonwell": variant = "dragonwell"; break;
            default: variant = "hs"
        }

        def arch = buildConfig.ARCHITECTURE
        if (arch == "x64") {
            arch = "x86-64"
        }

        def os = buildConfig.TARGET_OS

        def jobName = "Test_openjdk${number}_${variant}_${testType}_${arch}_${os}"

        if (buildConfig.ADDITIONAL_FILE_NAME_TAG) {
            switch (buildConfig.ADDITIONAL_FILE_NAME_TAG) {
                case ~/.*XL.*/: jobName += "_xl"; break
            }
        }
        return "${jobName}"
    }

    /*
    Retrieve the corresponding OpenJDK source code repository branch. This is used the downstream tests to determine what source code branch the tests should run against.
    */
    private def getJDKBranch() {

        def jdkBranch

        if (buildConfig.SCM_REF) {
            jdkBranch = buildConfig.SCM_REF
        } else {
            if (buildConfig.VARIANT == "corretto") {
                jdkBranch = 'develop'
            } else if (buildConfig.VARIANT == "openj9") {
                jdkBranch = 'openj9'
            } else if (buildConfig.VARIANT == "hotspot"){
                jdkBranch = 'dev'
            } else if (buildConfig.VARIANT == "dragonwell") {
                jdkBranch = 'master'
            } else {
                context.error("Unrecognised build variant '${buildConfig.VARIANT}' ")
                throw new Exception()
            }
        }

        return jdkBranch
    }

    /*
    Retrieve the corresponding OpenJDK source code repository. This is used the downstream tests to determine what source code the tests should run against.
    */
    private def getJDKRepo() {

        def jdkRepo
        def suffix
        def javaNumber = getJavaVersionNumber()

        if (buildConfig.VARIANT == "corretto") {
            suffix="corretto/corretto-${javaNumber}"
        } else if (buildConfig.VARIANT == "openj9") {
            suffix = "ibmruntimes/openj9-openjdk-jdk${javaNumber}"
        } else if (buildConfig.VARIANT == "hotspot") {
            suffix = "adoptopenjdk/openjdk-${buildConfig.JAVA_TO_BUILD}"
        } else if (buildConfig.VARIANT == "dragonwell") {
            suffix = "alibaba/dragonwell${javaNumber}"
        } else {
            context.error("Unrecognised build variant '${buildConfig.VARIANT}' ")
            throw new Exception()
        }

        jdkRepo = "https://github.com/${suffix}"
        if (buildConfig.BUILD_ARGS.count("--ssh") > 0) {
            jdkRepo = "git@github.com:${suffix}"
        }

        return jdkRepo
    }

    /*
    Run the downstream test jobs based off the configuration passed down from the top level pipeline jobs.
    If we try to call a test job that doesn't exist, the pipeline will not fail but it will print out a warning.
    If you need more test jobs added, please request so in #testing on Slack.
    */
    def runTests() {
        def testStages = [:]
        List testList = []
        def jdkBranch = getJDKBranch()
        def jdkRepo = getJDKRepo()
        def openj9Branch = (buildConfig.SCM_REF && buildConfig.VARIANT == "openj9") ? buildConfig.SCM_REF : "master"

        if (buildConfig.VARIANT == "corretto") {
            testList = buildConfig.TEST_LIST.minus(['sanity.external'])
        } else {
            testList = buildConfig.TEST_LIST
        }

        testList.each { testType ->

			// For each requested test, i.e 'sanity.openjdk', 'sanity.system', 'sanity.perf', 'sanity.external', call test job
			try {
				context.println "Running test: ${testType}"
				testStages["${testType}"] = {
					context.stage("${testType}") {

						// example jobName: Test_openjdk11_hs_sanity.system_ppc64_aix
						def jobName = determineTestJobName(testType)

						def JobHelper = context.library(identifier: 'openjdk-jenkins-helper@master').JobHelper

                        // Execute test job
						if (JobHelper.jobIsRunnable(jobName as String)) {
							context.catchError {
								context.build job: jobName,
										propagate: false,
										parameters: [
												context.string(name: 'UPSTREAM_JOB_NUMBER', value: "${env.BUILD_NUMBER}"),
												context.string(name: 'UPSTREAM_JOB_NAME', value: "${env.JOB_NAME}"),
												context.string(name: 'RELEASE_TAG', value: "${buildConfig.SCM_REF}"),
												context.string(name: 'JDK_REPO', value: jdkRepo),
												context.string(name: 'JDK_BRANCH', value: jdkBranch),
												context.string(name: 'OPENJ9_BRANCH', value: openj9Branch),
												context.string(name: 'ACTIVE_NODE_TIMEOUT', value: "${buildConfig.ACTIVE_NODE_TIMEOUT}")]
							}
						} else {
							context.println "[WARNING] Requested test job that does not exist or is disabled: ${jobName}"
						}
					}
				}
			} catch (Exception e) {
				context.println "Failed execute test: ${e.getLocalizedMessage()}"
			}
        }
        return testStages
    }

    /*
    We use this function at the end of a build to parse a java version string and create a VersionInfo object for deployment in the metadata objects.
    E.g. 11.0.9+10-202010192351 would be one example of a matched string.
    */
    VersionInfo parseVersionOutput(String consoleOut) {
        context.println(consoleOut)
        Matcher matcher = (consoleOut =~ /(?ms)^.*OpenJDK Runtime Environment[^\n]*\(build (?<version>[^)]*)\).*$/)
        if (matcher.matches()) {
            context.println("matched")
            String versionOutput = matcher.group('version')

            context.println(versionOutput)

            return new VersionInfo(context).parse(versionOutput, buildConfig.ADOPT_BUILD_NUMBER)
        }
        return null
    }

    /*
    Run the Sign downstream job. We run this job on windows and jdk8 hotspot & jdk13 mac builds.
    The job code signs and notarizes the binaries so they can run on these operating systems without encountering issues.
    */
    def sign(VersionInfo versionInfo) {
        // Sign and archive jobs if needed
        // TODO: This version info check needs to be updated when the notarization fix gets applied to other versions.
        if (
            buildConfig.TARGET_OS == "windows" ||
        (buildConfig.TARGET_OS == "mac" && versionInfo.major == 8 && buildConfig.VARIANT != "openj9") || (buildConfig.TARGET_OS == "mac" && versionInfo.major == 13)
        ) {
            context.stage("sign") {
                def filter = ""
                def certificate = ""

                def nodeFilter = "${buildConfig.TARGET_OS}"

                if (buildConfig.TARGET_OS == "windows") {
                    filter = "**/OpenJDK*_windows_*.zip"
                    certificate = "C:\\openjdk\\windows.p12"
                    nodeFilter = "${nodeFilter}&&build&&win2012"

                } else if (buildConfig.TARGET_OS == "mac") {
                    filter = "**/OpenJDK*_mac_*.tar.gz"
                    certificate = "\"Developer ID Application: London Jamocha Community CIC\""

                    nodeFilter = "${nodeFilter}&&macos10.14"
                }

                def params = [
                        context.string(name: 'UPSTREAM_JOB_NUMBER', value: "${env.BUILD_NUMBER}"),
                        context.string(name: 'UPSTREAM_JOB_NAME', value: "${env.JOB_NAME}"),
                        context.string(name: 'OPERATING_SYSTEM', value: "${buildConfig.TARGET_OS}"),
                        context.string(name: 'VERSION', value: "${versionInfo.major}"),
                        context.string(name: 'FILTER', value: "${filter}"),
                        context.string(name: 'CERTIFICATE', value: "${certificate}"),
                        ['$class': 'LabelParameterValue', name: 'NODE_LABEL', label: "${nodeFilter}"],
                ]

                // Execute sign job
                def signJob = context.build job: "build-scripts/release/sign_build",
                        propagate: true,
                        parameters: params

                // Output notification of downstream failure (the build will fail automatically)
                def jobResult = signJob.getResult()
                if (jobResult != 'SUCCESS') {
                    context.println "ERROR: downstream sign_build ${jobResult}.\nSee ${signJob.getAbsoluteUrl()} for details"
                }

                context.node('master') {
                    //Copy signed artifact back and archive again
                    context.sh "rm workspace/target/* || true"

                    context.copyArtifacts(
                            projectName: "build-scripts/release/sign_build",
                            selector: context.specific("${signJob.getNumber()}"),
                            filter: 'workspace/target/*',
                            fingerprintArtifacts: true,
                            target: "workspace/target/",
                            flatten: true)


                    context.sh 'for file in $(ls workspace/target/*.tar.gz workspace/target/*.zip); do sha256sum "$file" > $file.sha256.txt ; done'

                    writeMetadata(versionInfo, false)
                    context.archiveArtifacts artifacts: "workspace/target/*"
                }
            }
        }
    }

    /*
    Run the Mac installer downstream job.
    */
    private void buildMacInstaller(VersionInfo versionData) {
        def filter = "**/OpenJDK*_mac_*.tar.gz"
        def certificate = "Developer ID Installer: London Jamocha Community CIC"

        def nodeFilter = "${buildConfig.TARGET_OS}&&macos10.14&&xcode10"

        // Execute installer job
        def installerJob = context.build job: "build-scripts/release/create_installer_mac",
                propagate: true,
                parameters: [
                        context.string(name: 'UPSTREAM_JOB_NUMBER', value: "${env.BUILD_NUMBER}"),
                        context.string(name: 'UPSTREAM_JOB_NAME', value: "${env.JOB_NAME}"),
                        context.string(name: 'FILTER', value: "${filter}"),
                        context.string(name: 'FULL_VERSION', value: "${versionData.version}"),
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

    /*
    Run the Linux installer downstream job.
    */
    private void buildLinuxInstaller(VersionInfo versionData) {
        def filter = "**/OpenJDK*_linux_*.tar.gz"
        def nodeFilter = "${buildConfig.TARGET_OS}&&fpm"

        def buildNumber = versionData.build

        String releaseType = "Nightly"
        if (buildConfig.RELEASE) {
            releaseType = "Release"
        }

        // Execute installer job
        def installerJob = context.build job: "build-scripts/release/create_installer_linux",
                propagate: true,
                parameters: [
                        context.string(name: 'UPSTREAM_JOB_NUMBER', value: "${env.BUILD_NUMBER}"),
                        context.string(name: 'UPSTREAM_JOB_NAME', value: "${env.JOB_NAME}"),
                        context.string(name: 'FILTER', value: "${filter}"),
                        context.string(name: 'RELEASE_TYPE', value: "${releaseType}"),
                        context.string(name: 'VERSION', value: "${versionData.version}"),
                        context.string(name: 'MAJOR_VERSION', value: "${versionData.major}"),
                        context.string(name: 'ARCHITECTURE', value: "${buildConfig.ARCHITECTURE}"),
                        ['$class': 'LabelParameterValue', name: 'NODE_LABEL', label: "${nodeFilter}"]
                ]

    }

    /*
    Run the Windows installer downstream jobs.
    We run two jobs if we have a JRE (see https://github.com/AdoptOpenJDK/openjdk-build/issues/1751).
    */
    private void buildWindowsInstaller(VersionInfo versionData) {
        def filter = "**/OpenJDK*jdk_*_windows*.zip"
        def certificate = "C:\\openjdk\\windows.p12"

        def buildNumber = versionData.build

        if (versionData.major == 8) {
            buildNumber = String.format("%02d", versionData.build)
        }

        // Get version patch number if one is present
        def patch_version = versionData.patch ?: 0

        // Execute installer job
        def installerJob = context.build job: "build-scripts/release/create_installer_windows",
                propagate: true,
                parameters: [
                        context.string(name: 'UPSTREAM_JOB_NUMBER', value: "${env.BUILD_NUMBER}"),
                        context.string(name: 'UPSTREAM_JOB_NAME', value: "${env.JOB_NAME}"),
                        context.string(name: 'FILTER', value: "${filter}"),
                        context.string(name: 'PRODUCT_MAJOR_VERSION', value: "${versionData.major}"),
                        context.string(name: 'PRODUCT_MINOR_VERSION', value: "${versionData.minor}"),
                        context.string(name: 'PRODUCT_MAINTENANCE_VERSION', value: "${versionData.security}"),
                        context.string(name: 'PRODUCT_PATCH_VERSION', value: "${patch_version}"),
                        context.string(name: 'PRODUCT_BUILD_NUMBER', value: "${buildNumber}"),
                        context.string(name: 'MSI_PRODUCT_VERSION', value: "${versionData.msi_product_version}"),
                        context.string(name: 'PRODUCT_CATEGORY', value: "jdk"),
                        context.string(name: 'JVM', value: "${buildConfig.VARIANT}"),
                        context.string(name: 'SIGNING_CERTIFICATE', value: "${certificate}"),
                        context.string(name: 'ARCH', value: "${buildConfig.ARCHITECTURE}"),
                        ['$class': 'LabelParameterValue', name: 'NODE_LABEL', label: "${buildConfig.TARGET_OS}&&wix"]
                ]
        context.copyArtifacts(
                projectName: "build-scripts/release/create_installer_windows",
                selector: context.specific("${installerJob.getNumber()}"),
                filter: 'wix/ReleaseDir/*',
                fingerprintArtifacts: true,
                target: "workspace/target/",
                flatten: true)

        // Check if JRE exists, if so, build another installer for it
        listArchives().each({ file ->

            if (file.contains("-jre")) {

                context.println("We have a JRE. Running another installer for it...")
                def jreinstallerJob = context.build job: "build-scripts/release/create_installer_windows",
                        propagate: true,
                        parameters: [
                            context.string(name: 'UPSTREAM_JOB_NUMBER', value: "${env.BUILD_NUMBER}"),
                            context.string(name: 'UPSTREAM_JOB_NAME', value: "${env.JOB_NAME}"),
                            context.string(name: 'FILTER', value: "**/OpenJDK*jre_*_windows*.zip"),
                            context.string(name: 'PRODUCT_MAJOR_VERSION', value: "${versionData.major}"),
                            context.string(name: 'PRODUCT_MINOR_VERSION', value: "${versionData.minor}"),
                            context.string(name: 'PRODUCT_MAINTENANCE_VERSION', value: "${versionData.security}"),
                            context.string(name: 'PRODUCT_PATCH_VERSION', value: "${patch_version}"),
                            context.string(name: 'PRODUCT_BUILD_NUMBER', value: "${buildNumber}"),
                            context.string(name: 'MSI_PRODUCT_VERSION', value: "${versionData.msi_product_version}"),
                            context.string(name: 'PRODUCT_CATEGORY', value: "jre"),
                            context.string(name: 'JVM', value: "${buildConfig.VARIANT}"),
                            context.string(name: 'SIGNING_CERTIFICATE', value: "${certificate}"),
                            context.string(name: 'ARCH', value: "${buildConfig.ARCHITECTURE}"),
                            ['$class': 'LabelParameterValue', name: 'NODE_LABEL', label: "${buildConfig.TARGET_OS}&&wix"]
                        ]

                context.copyArtifacts(
                    projectName: "build-scripts/release/create_installer_windows",
                    selector: context.specific("${jreinstallerJob.getNumber()}"),
                    filter: 'wix/ReleaseDir/*',
                    fingerprintArtifacts: true,
                    target: "workspace/target/",
                    flatten: true
                )
            }

        })
    }

    /*
    Build installer master function. This builds the downstream installer jobs on completion of the sign and test jobs.
    The installers create our rpm, msi and pkg files that allow for an easier installation of the jdk binaries over a compressed archive.
    */
    def buildInstaller(VersionInfo versionData) {
        if (versionData == null || versionData.major == null) {
            context.println "Failed to parse version number, possibly a nightly? Skipping installer steps"
            return
        }

        context.node('master') {
            context.stage("installer") {
                switch (buildConfig.TARGET_OS) {
                    case "mac": buildMacInstaller(versionData); break
                    case "linux": buildLinuxInstaller(versionData); break
                    case "windows": buildWindowsInstaller(versionData); break
                    default: return; break
                }

                // Archive the Mac and Windows pkg/msi
                // (Linux installer job produces no artifacts, it just uploads rpm/deb to the repositories)
                if (buildConfig.TARGET_OS == "mac" || buildConfig.TARGET_OS == "windows") {
                    try {
                        context.sh 'for file in $(ls workspace/target/*.tar.gz workspace/target/*.pkg workspace/target/*.msi); do sha256sum "$file" > $file.sha256.txt ; done'
                        writeMetadata(versionData, false)
                        context.archiveArtifacts artifacts: "workspace/target/*"
                    } catch (e) {
                        context.println("Failed to build ${buildConfig.TARGET_OS} installer ${e}")
                        currentBuild.result = 'FAILURE'
                    }
                }
            }
        }
    }


    /*
    Lists and returns any compressed archived contents of the top directory of the build node
    */
    List<String> listArchives() {
        return context.sh(
                script: '''find workspace/target/ | egrep '(.tar.gz|.zip|.msi|.pkg|.deb|.rpm)$' ''',
                returnStdout: true,
                returnStatus: false
        )
                .trim()
                .split('\n')
                .toList()
    }

    /*
    On any writeMetadata other than the first, we simply return a MetaData object from the previous writeout adjusted to the situation.
    On the first writeout, we pull in the .txt files created by the build that list the attributes of what we used to build the jdk (e.g. configure args, commit hash, etc)
    */
    MetaData formMetadata(VersionInfo version, Boolean initialWrite) {

        // We have to setup some attributes for the first run since formMetadata is sometimes initiated from downstream job on master node with no access to the required files
        if (initialWrite) {

            // Get scmRef
            context.println "INFO: FIRST METADATA WRITE OUT! Checking if we have a scm reference in the build config..."

            String scmRefPath = "workspace/target/metadata/scmref.txt"
            scmRef = buildConfig.SCM_REF

            if (scmRef != "") {
                // Use the buildConfig scmref if it is set
                context.println "SUCCESS: SCM_REF has been set (${buildConfig.SCM_REF})! Using it to build the initial metadata over ${scmRefPath}..."
            } else {
                // If we don't have a scmref set in config, check if we have a scmref from the build
                context.println "INFO: SCM_REF is NOT set. Attempting to read ${scmRefPath}..."
                try {
                    scmRef = context.readFile(scmRefPath).trim()
                    context.println "SUCCESS: scmref.txt found: ${scmRef}"
                } catch (NoSuchFileException e) {
                    // In rare cases, we will fail to create the scmref.txt file
                    context.println "WARNING: $scmRefPath was not found. Using build config SCM_REF instead (even if it's empty)..."
                }

            }

            // Get Full Version Output
            String versionPath = "workspace/target/metadata/version.txt"
            if (buildConfig.ARCHITECTURE.contains("riscv")) {
                versionPath = riscvVersionPath
            }
            context.println "INFO: Attempting to read ${versionPath}..."

            try {
                fullVersionOutput = context.readFile(versionPath)
                context.println "SUCCESS: ${versionPath} found"
            } catch (NoSuchFileException e) {
                context.println "ERROR: ${versionPath} was not found. Exiting..."
                throw new Exception()
            }

            // Get Configure Args
            String configurePath = "workspace/target/metadata/configure.txt"
            context.println "INFO: Attempting to read ${configurePath}..."

            try {
                configureArguments = context.readFile(configurePath)
                context.println "SUCCESS: configure.txt found"
            } catch (NoSuchFileException e) {
                context.println "ERROR: ${configurePath} was not found. Exiting..."
                throw new Exception()
            }

            // Get Variant Version for OpenJ9
            if (buildConfig.VARIANT == "openj9") {
                String j9MajorPath = "workspace/target/metadata/variant_version/major.txt"
                String j9MinorPath = "workspace/target/metadata/variant_version/minor.txt"
                String j9SecurityPath = "workspace/target/metadata/variant_version/security.txt"
                String j9TagsPath = "workspace/target/metadata/variant_version/tags.txt"

                context.println "INFO: Build variant openj9 detected..."

                context.println "INFO: Attempting to read workspace/target/metadata/variant_version/major.txt..."
                try {
                    j9Major = context.readFile(j9MajorPath)
                    context.println "SUCCESS: major.txt found"
                } catch (NoSuchFileException e) {
                    context.println "ERROR: ${j9MajorPath} was not found. Exiting..."
                    throw new Exception()
                }

                context.println "INFO: Attempting to read workspace/target/metadata/variant_version/minor.txt..."
                try {
                    j9Minor = context.readFile(j9MinorPath)
                    context.println "SUCCESS: minor.txt found"
                } catch (NoSuchFileException e) {
                    context.println "ERROR: ${j9MinorPath} was not found. Exiting..."
                    throw new Exception()
                }

                context.println "INFO: Attempting to read workspace/target/metadata/variant_version/security.txt..."
                try {
                    j9Security = context.readFile(j9SecurityPath)
                    context.println "SUCCESS: security.txt found"
                } catch (NoSuchFileException e) {
                    context.println "ERROR: ${j9SecurityPath} was not found. Exiting..."
                    throw new Exception()
                }

                context.println "INFO: Attempting to read workspace/target/metadata/variant_version/tags.txt..."
                try {
                    j9Tags = context.readFile(j9TagsPath)
                    context.println "SUCCESS: tags.txt found"
                } catch (NoSuchFileException e) {
                    context.println "ERROR: ${j9TagsPath} was not found. Exiting..."
                    throw new Exception()
                }

                variantVersion = [major: j9Major, minor: j9Minor, security: j9Security, tags: j9Tags]
            }

            // Get Vendor
            String vendorPath = "workspace/target/metadata/vendor.txt"
            context.println "INFO: Attempting to read ${vendorPath}..."

            try {
                vendorName = context.readFile(vendorPath)
                context.println "SUCCESS: vendor.txt found"
            } catch (NoSuchFileException e) {
                context.println "ERROR: ${vendorPath} was not found. Exiting..."
                throw new Exception()
            }

            // Get Build Source
            String buildSourcePath = "workspace/target/metadata/buildSource.txt"
            context.println "INFO: Attempting to read ${buildSourcePath}..."

            try {
                buildSource = context.readFile(buildSourcePath)
                context.println "SUCCESS: buildSource.txt found"
            } catch (NoSuchFileException e) {
                context.println "ERROR: ${buildSourcePath} was not found. Exiting..."
                throw new Exception()
            }

        }

        return new MetaData(
            vendorName,
            buildConfig.TARGET_OS,
            scmRef,
            buildSource,
            version,
            buildConfig.JAVA_TO_BUILD,
            buildConfig.VARIANT,
            variantVersion,
            buildConfig.ARCHITECTURE,
            fullVersionOutput,
            configureArguments
        )

    }

    /*
    Calculates and writes out the metadata to a file.
    The metadata defines and summarises a build and the jdk it creates.
    The adopt v3 api makes use of it in its endpoints to quickly display information about the jdk binaries that are stored on github.
    */
    def writeMetadata(VersionInfo version, Boolean initialWrite) {
        /*
        example data:
            {
                "vendor": "AdoptOpenJDK",
                "os": "mac",
                "arch": "x64",
                "variant": "openj9",
                "variant_version": {
                    "major": "0",
                    "minor": "22",
                    "security": "0",
                    "tags": "m2"
                },
                "version": {
                    "minor": 0,
                    "security": 0,
                    "pre": null,
                    "adopt_build_number": 0,
                    "major": 15,
                    "version": "15+29-202007070926",
                    "semver": "15.0.0+29.0.202007070926",
                    "build": 29,
                    "opt": "202007070926"
                },
                "scmRef": "<output of git describe OR buildConfig.SCM_REF>",
                "buildRef": "<build-repo-name/build-commit-sha>",
                "version_data": "jdk15",
                "binary_type": "debugimage",
                "sha256": "<shasum>",
                "full_version_output": <output of java --version>,
                "configure_arguments": <output of bash configure>
            }
        */

        MetaData data = initialWrite ? formMetadata(version, true) : formMetadata(version, false)

        Boolean metaWrittenOut = false
        listArchives().each({ file ->
            def type = "jdk"
            if (file.contains("-jre")) {
                type = "jre"
            } else if (file.contains("-testimage")) {
                type = "testimage"
            } else if (file.contains("-debugimage")) {
                type = "debugimage"
            }

            String hash = context.sh(script: """\
                                              if [ -x "\$(command -v shasum)" ]; then
                                                (shasum -a 256 | cut -f1 -d' ') <$file
                                              else
                                                sha256sum $file | cut -f1 -d' '
                                              fi
                                            """.stripIndent(), returnStdout: true, returnStatus: false)

            hash = hash.replaceAll("\n", "")

            data.binary_type = type
            data.sha256 = hash

            // To save on spam, only print out the metadata the first time
            if (!metaWrittenOut && initialWrite) {
                context.println "===METADATA OUTPUT==="
                context.println JsonOutput.prettyPrint(JsonOutput.toJson(data.asMap()))
                context.println "=/=METADATA OUTPUT=/="
                metaWrittenOut = true
            }

            context.writeFile file: "${file}.json", text: JsonOutput.prettyPrint(JsonOutput.toJson(data.asMap()))
        })
    }

    /*
    Calculates what the binary filename will be based off of the version, arch, os, variant, timestamp and extension.
    It will usually be something like OpenJDK8U-jdk_x64_linux_hotspot_2020-10-19-17-06.tar.gz
    */
    def determineFileName() {
        String javaToBuild = buildConfig.JAVA_TO_BUILD
        String architecture = buildConfig.ARCHITECTURE
        String os = buildConfig.TARGET_OS
        String variant = buildConfig.VARIANT
        String additionalFileNameTag = buildConfig.ADDITIONAL_FILE_NAME_TAG
        String overrideFileNameVersion = buildConfig.OVERRIDE_FILE_NAME_VERSION

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
        } else if (buildConfig.PUBLISH_NAME) {

            // for java 11 remove jdk- and +. i.e jdk-11.0.3+7 -> 11.0.3_7_openj9-0.14.0
            def nameTag = buildConfig.PUBLISH_NAME
                    .replace("jdk-", "")
                    .replaceAll("\\+", "_")

            // for java 8 remove jdk and - before the build. i.e jdk8u212-b03_openj9-0.14.0 -> 8u212b03_openj9-0.14.0
            nameTag = nameTag
                    .replace("jdk", "")
                    .replace("-b", "b")

            fileName = "${fileName}_${nameTag}"
        } else {
            def timestamp = new Date().format("yyyy-MM-dd-HH-mm", TimeZone.getTimeZone("UTC"))

            fileName = "${fileName}_${timestamp}"
        }


        fileName = "${fileName}.${extension}"

        context.println "Filename will be: $fileName"
        return fileName
    }

    /*
    Run the RISC-V version reader downstream job.
    In short, we archive the build artifacts to expose them to the job and run ./java version, copying the output back to here.
    See riscv_version_out.groovy.
    */
    def readRiscvVersionString() {
        // Archive the artifacts early so we can copy them over to the downstream job
        try {
            context.timeout(time: buildTimeouts.BUILD_ARCHIVE_TIMEOUT, unit: "HOURS") {
                context.archiveArtifacts artifacts: "workspace/target/*"
            }
        } catch (FlowInterruptedException e) {
            context.println "[ERROR] Build archive timeout (${buildTimeouts.BUILD_ARCHIVE_TIMEOUT} HOURS) has been reached. Exiting..."
            throw new Exception()
        }

        // Setup params for downstream job & execute
        String shortJobName = env.JOB_NAME.split('/').last()
        String copyFileFilter = "${shortJobName}_${env.BUILD_NUMBER}_version.txt"

        def riscvJob = context.build job: "build-scripts/utils/riscv-version-out",
            propagate: true,
            parameters: [
                context.string(name: 'UPSTREAM_JOB_NAME', value: "${env.JOB_NAME}"),
                context.string(name: 'UPSTREAM_JOB_NUMBER', value: "${env.BUILD_NUMBER}"),
                context.string(name: 'JDK_FILE_FILTER', value: "OpenJDK*-jdk*_linux_*.tar.gz"),
                context.string(name: 'FILENAME', value: "${copyFileFilter}")
            ]

        context.copyArtifacts(
            projectName: "build-scripts/utils/riscv-version-out",
            selector: context.specific("${riscvJob.getNumber()}"),
            filter: "RiscvVersionOuts/${copyFileFilter}",
            target: "workspace/target/metadata",
            flatten: true
        )

        // We assign to a variable so it can be used in formMetadata() to find the correct version info
        riscvVersionPath = "workspace/target/metadata/${copyFileFilter}"
        return context.readFile(riscvVersionPath)
    }

    /*
    Executed on a build node, the function checks out the repository and executes the build via ./make-adopt-build-farm.sh
    Once the build completes, it will calculate its version output, commit the first metadata writeout, and archive the build results.
    */
    def buildScripts(cleanWorkspace, filename) {
        return context.stage("build") {

            if (cleanWorkspace) {
                try {

                    try {
                        context.timeout(time: buildTimeouts.NODE_CLEAN_TIMEOUT, unit: "HOURS") {
                            if (buildConfig.TARGET_OS == "windows") {
                                // Windows machines struggle to clean themselves, see:
                                // https://github.com/AdoptOpenJDK/openjdk-build/issues/1855
                                context.sh(script: "rm -rf C:/workspace/openjdk-build/workspace/build/src/build/*/jdk/gensrc")
                                // https://github.com/AdoptOpenJDK/openjdk-infrastructure/issues/1419
                                context.sh(script: "rm -rf J:/jenkins/tmp/workspace/build/src/build/*/jdk/gensrc")
                                // https://github.com/AdoptOpenJDK/openjdk-infrastructure/issues/1662
                                context.sh(script: "rm -rf E:/jenkins/tmp/workspace/build/src/build/*/jdk/gensrc")
                                context.cleanWs notFailBuild: true, disableDeferredWipeout: true, deleteDirs: true
                            } else {
                                context.cleanWs notFailBuild: true
                            }
                        }
                    } catch (FlowInterruptedException e) {
                        context.println "[ERROR] Node Clean workspace timeout (${buildTimeouts.NODE_CLEAN_TIMEOUT} HOURS) has been reached. Exiting..."
                        throw new Exception()
                    }

                } catch (e) {
                    context.println "[WARNING] Failed to clean workspace: ${e}"
                }
            }

            try {
                context.timeout(time: buildTimeouts.NODE_CHECKOUT_TIMEOUT, unit: "HOURS") {
                    context.checkout context.scm

                    // Perform a git clean outside of checkout to avoid the Jenkins enforced 10 minute timeout
                    // https://github.com/AdoptOpenJDK/openjdk-infrastructure/issues/1553
                    context.sh(script: "git clean -fdx")
                }
            } catch (FlowInterruptedException e) {
                context.println "[ERROR] Node checkout workspace timeout (${buildTimeouts.NODE_CHECKOUT_TIMEOUT} HOURS) has been reached. Exiting..."
                throw new Exception()
            }

            try {
                // Convert IndividualBuildConfig to jenkins env variables
                List<String> envVars = buildConfig.toEnvVars()
                envVars.add("FILENAME=${filename}" as String)

                // Execute build
                context.withEnv(envVars) {
                    try {
                        context.timeout(time: buildTimeouts.BUILD_JDK_TIMEOUT, unit: "HOURS") {
                            context.sh(script: "./build-farm/make-adopt-build-farm.sh")
                        }
                    } catch (FlowInterruptedException e) {
                        context.println "[ERROR] Build JDK timeout (${buildTimeouts.BUILD_JDK_TIMEOUT} HOURS) has been reached. Exiting..."
                        throw new Exception()
                    }

                    // Run a downstream job on riscv machine that returns the java version
                    // otherwise, just read the version.txt
                    String versionOut
                    if (buildConfig.ARCHITECTURE.contains("riscv")) {
                        context.println "[WARNING] Don't read faked version.txt on riscv! Archiving early and running downstream job on riscv machine to retrieve java version..."
                        versionOut = readRiscvVersionString()
                    } else {
                        versionOut = context.readFile("workspace/target/metadata/version.txt")
                    }

                    versionInfo = parseVersionOutput(versionOut)
                }

                writeMetadata(versionInfo, true)

                try {
                    context.timeout(time: buildTimeouts.BUILD_ARCHIVE_TIMEOUT, unit: "HOURS") {
                        // We have already archived riscv artifacts, so only archive the metadata files
                        if (buildConfig.ARCHITECTURE.contains("riscv")) {
                            context.println "[INFO] Archiving JSON Files..."
                            context.archiveArtifacts artifacts: "workspace/target/*.json"
                        } else {
                            context.archiveArtifacts artifacts: "workspace/target/*"
                        }
                    }
                } catch (FlowInterruptedException e) {
                    context.println "[ERROR] Build archive timeout (${buildTimeouts.BUILD_ARCHIVE_TIMEOUT} HOURS) has been reached. Exiting..."
                    throw new Exception()
                }
            } finally {
                if (buildConfig.TARGET_OS == "aix") {
                    try {
                        context.timeout(time: buildTimeouts.AIX_CLEAN_TIMEOUT, unit: "HOURS") {
                            context.cleanWs notFailBuild: true
                        }
                    } catch (FlowInterruptedException e) {
                        context.println "[ERROR] AIX clean workspace timeout (${buildTimeouts.AIX_CLEAN_TIMEOUT} HOURS) has been reached. Exiting..."
                        throw new Exception()
                    }
                }
            }
        }
    }

    /*
    Pulls in and applies the activeNodeTimeout parameter.
    The function will use the jenkins helper nodeIsOnline lib to check once a minute if a node with the specified label has come online.
    If it doesn't find one or the timeout is set to 0 (default), it'll crash out. Otherwise, it'll return and jump onto the node.
    */
    def waitForANodeToBecomeActive(def label) {
        def NodeHelper = context.library(identifier: 'openjdk-jenkins-helper@master').NodeHelper

        // A node with the requested label is ready to go
        if (NodeHelper.nodeIsOnline(label)) {
            return
        }

        context.println("No active node matches this label: " + label)

        // Import activeNodeTimeout param
        int activeNodeTimeout = 0
        if (buildConfig.ACTIVE_NODE_TIMEOUT.isInteger()) {
            activeNodeTimeout = buildConfig.ACTIVE_NODE_TIMEOUT as Integer
        }


        if (activeNodeTimeout > 0) {
            context.println("Will check again periodically until a node labelled " + label + " comes online, or " + buildConfig.ACTIVE_NODE_TIMEOUT + " minutes (ACTIVE_NODE_TIMEOUT) has passed.")
            int x = 0
            while (x < activeNodeTimeout) {
                context.sleep(time: 1, unit: "MINUTES")
                if (NodeHelper.nodeIsOnline(label)) {
                    context.println("A node which matches this label is now active: " + label)
                    return
                }
                x++
            }
            context.error("No node matching this label became active prior to the timeout: " + label)
            throw new Exception()
        } else {
            context.error("As the timeout value is set to 0, we will not wait for a node to become active.")
            throw new Exception()
        }
    }

    /*
    Main function. This is what is executed remotely via the helper file kick_off_build.groovy, which is in turn executed by the downstream jobs.
    */
    @SuppressWarnings("unused")
    def build() {
        context.timestamps {
            try {
                context.println "Build config"
                context.println buildConfig.toJson()

                def filename = determineFileName()

                context.println "Executing tests: ${buildConfig.TEST_LIST}"
                context.println "Build num: ${env.BUILD_NUMBER}"
                context.println "File name: ${filename}"

                def enableTests = Boolean.valueOf(buildConfig.ENABLE_TESTS)
                def enableInstallers = Boolean.valueOf(buildConfig.ENABLE_INSTALLERS)
                def enableSigner = Boolean.valueOf(buildConfig.ENABLE_SIGNER)
                def cleanWorkspace = Boolean.valueOf(buildConfig.CLEAN_WORKSPACE)

                context.stage("queue") {
                    /* This loads the library containing two Helper classes, and causes them to be
                    imported/updated from their repo. Without the library being imported here, runTests 
                    method will fail to execute the post-build test jobs for reasons unknown.
                    */
                    context.library(identifier: 'openjdk-jenkins-helper@master')

                    if (buildConfig.DOCKER_IMAGE) {
                        // Docker build environment
                        def label = buildConfig.NODE_LABEL + "&&dockerBuild"
                        if (buildConfig.DOCKER_NODE) {
                            label = buildConfig.NODE_LABEL + "&&" + "$buildConfig.DOCKER_NODE"
                        }

                        if (buildConfig.CODEBUILD) {
                            label = "codebuild"
                        }

                        context.println "[NODE SHIFT] MOVING INTO DOCKER NODE MATCHING LABELNAME ${label}..."
                        context.node(label) {
                            // Cannot clean workspace from inside docker container
                            if (cleanWorkspace) {

                                try {
                                    context.timeout(time: buildTimeouts.MASTER_CLEAN_TIMEOUT, unit: "HOURS") {
                                        // Cannot clean workspace from inside docker container
                                        if (cleanWorkspace) {
                                            try {
                                                context.cleanWs notFailBuild: true
                                            } catch (e) {
                                                context.println "Failed to clean ${e}"
                                            }
                                            cleanWorkspace = false
                                        }
                                    }
                                } catch (FlowInterruptedException e) {
                                    context.println "[ERROR] Master clean workspace timeout (${buildTimeouts.MASTER_CLEAN_TIMEOUT} HOURS) has been reached. Exiting..."
                                    throw new Exception()
                                }

                            }

                            // Use our docker file if DOCKER_FILE is defined
                            if (buildConfig.DOCKER_FILE) {
                                try {
                                    context.timeout(time: buildTimeouts.DOCKER_CHECKOUT_TIMEOUT, unit: "HOURS") {
                                        context.checkout context.scm

                                        // Perform a git clean outside of checkout to avoid the Jenkins enforced 10 minute timeout
                                        // https://github.com/AdoptOpenJDK/openjdk-infrastructure/issues/1553
                                        context.sh(script: "git clean -fdx")
                                    }
                                } catch (FlowInterruptedException e) {
                                    context.println "[ERROR] Master docker file scm checkout timeout (${buildTimeouts.DOCKER_CHECKOUT_TIMEOUT} HOURS) has been reached. Exiting..."
                                    throw new Exception()
                                }

                                context.docker.build("build-image", "--build-arg image=${buildConfig.DOCKER_IMAGE} -f ${buildConfig.DOCKER_FILE} .").inside {
                                    buildScripts(cleanWorkspace, filename)
                                }
                            // Otherwise, pull the docker image from DockerHub
                            } else {
                                try {
                                    context.timeout(time: buildTimeouts.DOCKER_PULL_TIMEOUT, unit: "HOURS") {
                                        context.docker.image(buildConfig.DOCKER_IMAGE).pull()
                                    }
                                } catch (FlowInterruptedException e) {
                                    context.println "[ERROR] Master docker image pull timeout (${buildTimeouts.DOCKER_PULL_TIMEOUT} HOURS) has been reached. Exiting..."
                                    throw new Exception()
                                }

                                context.docker.image(buildConfig.DOCKER_IMAGE).inside {
                                    buildScripts(cleanWorkspace, filename)
                                }
                            }
                        }
                        context.println "[NODE SHIFT] OUT OF DOCKER NODE (LABELNAME ${label}!)"

                    // Build the jdk outside of docker container...
                    } else {
                        waitForANodeToBecomeActive(buildConfig.NODE_LABEL)
                        context.println "[NODE SHIFT] MOVING INTO NODE MATCHING LABELNAME ${buildConfig.NODE_LABEL}..."
                        context.node(buildConfig.NODE_LABEL) {
                            // This is to avoid windows path length issues.
                            context.echo("checking ${buildConfig.TARGET_OS}")
                            if (buildConfig.TARGET_OS == "windows") {
                                // See https://github.com/AdoptOpenJDK/openjdk-infrastructure/issues/1284#issuecomment-621909378 for justification of the below path
                                def workspace = "C:/workspace/openjdk-build/"
                                if (env.CYGWIN_WORKSPACE) {
                                    workspace = env.CYGWIN_WORKSPACE
                                }
                                context.echo("changing ${workspace}")
                                context.ws(workspace) {
                                    buildScripts(cleanWorkspace, filename)
                                }
                            } else {
                                buildScripts(cleanWorkspace, filename)
                            }
                        }
                        context.println "[NODE SHIFT] OUT OF NODE (LABELNAME ${buildConfig.NODE_LABEL}!)"
                    }
                }

                // Sign and archive jobs if needed
                if (enableSigner) {
                    try {
                        context.timeout(time: buildTimeouts.SIGN_JOB_TIMEOUT, unit: "HOURS") {
                            sign(versionInfo)
                        }
                    } catch (FlowInterruptedException e) {
                        context.println "[ERROR] Sign job timeout (${buildTimeouts.SIGN_JOB_TIMEOUT} HOURS) has been reached OR the downstream sign job failed. Exiting..."
                        throw new Exception()
                    }
                }

                if (enableTests && buildConfig.TEST_LIST.size() > 0) {
                    try {
                        // Run tests if we have a test list, don't use timeouts as the jobs have their own
                        def testStages = runTests()
                        context.parallel testStages
                    } catch (Exception e) {
                        context.println "Failed test: ${e}"
                    }
                }

                //buildInstaller if needed
                if (enableInstallers) {
                    try {
                        context.timeout(time: buildTimeouts.INSTALLER_JOBS_TIMEOUT, unit: "HOURS") {
                            buildInstaller(versionInfo)
                        }
                    } catch (FlowInterruptedException e) {
                        context.println "[ERROR] Installer job timeout (${buildTimeouts.INSTALLER_JOBS_TIMEOUT} HOURS) has been reached OR the downstream installer job failed. Exiting..."
                        throw new Exception()
                    }
                }

            // Generic catch all. Will usually be the last message in the log.
            } catch (Exception e) {
                currentBuild.result = 'FAILURE'
                context.println "Execution error: ${e}"
                def sw = new StringWriter()
                def pw = new PrintWriter(sw)
                e.printStackTrace(pw)
                context.println sw.toString()
            }
        }
    }
}

return {
    buildConfigArg,
    context,
    env,
    currentBuild ->
        def buildConfig
        if (String.class.isInstance(buildConfigArg)) {
            buildConfig = new IndividualBuildConfig(buildConfigArg as String)
        } else {
            buildConfig = buildConfigArg as IndividualBuildConfig
        }

        return new Build(
                buildConfig,
                context,
                env,
                currentBuild)
}
