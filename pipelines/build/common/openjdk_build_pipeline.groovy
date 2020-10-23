import common.IndividualBuildConfig
import common.MetaData
@Library('local-lib@master')
import common.VersionInfo
import groovy.json.*
import java.nio.file.NoSuchFileException

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
    Map variantVersion = [:]

    Build(IndividualBuildConfig buildConfig, def context, def env, def currentBuild) {
        this.buildConfig = buildConfig
        this.context = context
        this.currentBuild = currentBuild
        this.env = env
    }


    Integer getJavaVersionNumber() {
        def javaToBuild = buildConfig.JAVA_TO_BUILD
        // version should be something like "jdk8u" or "jdk" for HEAD
        Matcher matcher = javaToBuild =~ /.*?(?<version>\d+).*?/
        if (matcher.matches()) {
            return Integer.parseInt(matcher.group('version'))
        } else if ("jdk".equalsIgnoreCase(javaToBuild.trim())) {
            // Query the Adopt api to get the "tip_version"
            def JobHelper = context.library(identifier: 'openjdk-jenkins-helper@master').JobHelper
            context.println "Querying Adopt Api for the JDK-Head number (tip_version)..."

            def response = JobHelper.getAvailableReleases(context)
            int headVersion = (int) response.getAt("tip_version")
            context.println "Found Java Version Number: ${headVersion}"
            return headVersion
        } else {
            context.error("Failed to read java version '${javaToBuild}'")
            throw new Exception()
        }
    }

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

    private def getJDKBranch() {

        def jdkBranch
        
        if (buildConfig.VARIANT == "corretto") {
            jdkBranch = 'develop'
        } else if (buildConfig.VARIANT == "openj9") {
            jdkBranch = 'openj9'
        } else if (buildConfig.VARIANT == "hotspot"){
            jdkBranch = 'dev'
        } else if (buildConfig.VARIANT == "dragonwell") {
            jdkBranch = 'master'
        } else {
            context.error("Unrecognized build variant '${buildConfig.VARIANT}' ")
            throw new Exception()
        }
        return jdkBranch
    }
    
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
            context.error("Unrecognized build variant '${buildConfig.VARIANT}' ")
            throw new Exception()
        }
        
        jdkRepo = "https://github.com/${suffix}"
        if (buildConfig.BUILD_ARGS.count("--ssh") > 0) {
            jdkRepo = "git@github.com:${suffix}"
        }
        
        return jdkRepo
    }
    
    def runTests() {
        def testStages = [:]
        List testList = []
        def jdkBranch = getJDKBranch()
        def jdkRepo = getJDKRepo()

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
												context.string(name: 'ACTIVE_NODE_TIMEOUT', value: "${buildConfig.ACTIVE_NODE_TIMEOUT}")]
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

    VersionInfo parseVersionOutput(String consoleOut) {
        context.println(consoleOut)
        Matcher matcher = (consoleOut =~ /(?ms)^.*OpenJDK Runtime Environment[^\n]*\(build (?<version>[^)]*)\).*$/)
        if (matcher.matches()) {
            context.println("matched")
            String versionOutput = matcher.group('version')
            context.println(versionOutput)

            return new VersionInfo().parse(versionOutput, buildConfig.ADOPT_BUILD_NUMBER)
        }
        return null
    }

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

                def signJob = context.build job: "build-scripts/release/sign_build",
                        propagate: true,
                        parameters: params
                
                // Output notification of downstream failure (the build will fail automatically)
                def jobResult = signJob.getResult()
                if (jobResult != 'SUCCESS') {
                    context.println "ERROR: downstream sign_build ${jobResult}.\nSee ${signJob.getAbsoluteUrl()} for details"
                } 

                context.node('master') {
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

                    writeMetadata(versionInfo, false)
                    context.archiveArtifacts artifacts: "workspace/target/*"
                }
            }
        }
    }


    private void buildMacInstaller(VersionInfo versionData) {
        def filter = "**/OpenJDK*_mac_*.tar.gz"
        def certificate = "Developer ID Installer: London Jamocha Community CIC"

        def nodeFilter = "${buildConfig.TARGET_OS}&&macos10.14&&xcode10"

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

    private void buildLinuxInstaller(VersionInfo versionData) {
        def filter = "**/OpenJDK*_linux_*.tar.gz"
        def nodeFilter = "${buildConfig.TARGET_OS}&&fpm"

        def buildNumber = versionData.build

        String releaseType = "Nightly"
        if (buildConfig.RELEASE) {
            releaseType = "Release"
        }

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

    private void buildWindowsInstaller(VersionInfo versionData) {
        def filter = "**/OpenJDK*jdk_*_windows*.zip"
        def certificate = "C:\\openjdk\\windows.p12"

        def buildNumber = versionData.build

        if (versionData.major == 8) {
            buildNumber = String.format("%02d", versionData.build)
        }

        def installerJob = context.build job: "build-scripts/release/create_installer_windows",
                propagate: true,
                parameters: [
                        context.string(name: 'UPSTREAM_JOB_NUMBER', value: "${env.BUILD_NUMBER}"),
                        context.string(name: 'UPSTREAM_JOB_NAME', value: "${env.JOB_NAME}"),
                        context.string(name: 'FILTER', value: "${filter}"),
                        context.string(name: 'PRODUCT_MAJOR_VERSION', value: "${versionData.major}"),
                        context.string(name: 'PRODUCT_MINOR_VERSION', value: "${versionData.minor}"),
                        context.string(name: 'PRODUCT_MAINTENANCE_VERSION', value: "${versionData.security}"),
                        context.string(name: 'PRODUCT_PATCH_VERSION', value: "${buildNumber}"),
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
                            context.string(name: 'PRODUCT_PATCH_VERSION', value: "${buildNumber}"),
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

    MetaData formMetadata(VersionInfo version, Boolean initialWrite) {

        // We have to setup some attributes for the first run since formMetadata is sometimes initiated from downstream job on master node with no access to the required files
        if (initialWrite) {

            // Get scmRef
            context.println "INFO: FIRST METADATA WRITE OUT! Checking if we have a scm reference in the build config..."

            String scmRefPath = "workspace/target/metadata/scmref.txt"
            scmRef = buildConfig.SCM_REF

            if (scmRef != "") {
                // Use the buildConfig scmref if it is set
                context.println "SUCCESS: SCM_REF has been set (${buildConfig.SCM_REF})! Using it to build the inital metadata over ${scmRefPath}..."
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
            context.println "INFO: Attempting to read ${versionPath}..."

            try {
                fullVersionOutput = context.readFile(versionPath)
                context.println "SUCCESS: version.txt found"
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

            context.writeFile file: "${file}.json", text: JsonOutput.prettyPrint(JsonOutput.toJson(data.asMap()))
        })
    }

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

    def buildScripts(cleanWorkspace, filename) {
        return context.stage("build") {
            if (cleanWorkspace) {
                try {
                    if (buildConfig.TARGET_OS == "windows") {
                        // Windows machines struggle to clean themselves, see:
                        // https://github.com/AdoptOpenJDK/openjdk-build/issues/1855
                        context.sh(script: "rm -rf C:/workspace/openjdk-build/workspace/build/src/build/*/jdk/gensrc")
                        // https://github.com/AdoptOpenJDK/openjdk-infrastructure/issues/1419
                        context.sh(script: "rm -rf J:/jenkins/tmp/workspace/build/src/build/*/jdk/gensrc")
                        context.cleanWs notFailBuild: true, disableDeferredWipeout: true, deleteDirs: true
                    } else {
                        context.cleanWs notFailBuild: true
                    }
                } catch (e) {
                    context.println "Failed to clean ${e}"
                }
            }
            context.checkout context.scm
            try {
                List<String> envVars = buildConfig.toEnvVars()
                envVars.add("FILENAME=${filename}" as String)
                context.withEnv(envVars) {
                    context.sh(script: "./build-farm/make-adopt-build-farm.sh")
                    String versionOut = context.readFile("workspace/target/metadata/version.txt")

                    versionInfo = parseVersionOutput(versionOut)
                }
                writeMetadata(versionInfo, true)
                context.archiveArtifacts artifacts: "workspace/target/*"
            } finally {
                if (buildConfig.TARGET_OS == "aix") {
                    context.cleanWs notFailBuild: true
                }
            }
        }
    }

    def waitForANodeToBecomeActive(def label) {
        def NodeHelper = context.library(identifier: 'openjdk-jenkins-helper@master').NodeHelper

        if (NodeHelper.nodeIsOnline(label)) {
            return
        }

        context.println("No active node matches this label: " + label)

        int activeNodeTimeout = 0
        if (buildConfig.ACTIVE_NODE_TIMEOUT.isInteger()) {
            activeNodeTimeout = buildConfig.ACTIVE_NODE_TIMEOUT as Integer
        }


        if (activeNodeTimeout > 0) {
            context.println("Will check again periodically until a node labelled " + label + " comes online, or " + buildConfig.ACTIVE_NODE_TIMEOUT + " minutes (ACTIVE_NODE_TIMEOUT) has passed.")
            int x = 0
            while (x < activeNodeTimeout) {
                context.sleep(60 * 1000)  // 1 minute sleep
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

    def build() {
        context.timestamps {
            context.timeout(time: 18, unit: "HOURS") {
                try {

                    context.println "Build config"
                    context.println buildConfig.toJson()

                    def filename = determineFileName()

                    context.println "Executing tests: ${buildConfig.TEST_LIST}"
                    context.println "Build num: ${env.BUILD_NUMBER}"
                    context.println "File name: ${filename}"

                    def enableTests = Boolean.valueOf(buildConfig.ENABLE_TESTS)
                    def enableInstallers = Boolean.valueOf(buildConfig.ENABLE_INSTALLERS)
                    def cleanWorkspace = Boolean.valueOf(buildConfig.CLEAN_WORKSPACE)

                    context.stage("queue") {
                        // This loads the library containing two Helper classes, and causes them to be
                        // imported/updated from their repo. Without the library being imported here, runTests 
                        // method will fail to execute the post-build test jobs for reasons unknown.
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

                            context.node(label) {
                                // Cannot clean workspace from inside docker container
                                if (cleanWorkspace) {
                                    try {
                                        context.cleanWs notFailBuild: true
                                    } catch (e) {
                                        context.println "Failed to clean ${e}"
                                    }
                                    cleanWorkspace = false
                                }
                                if (buildConfig.DOCKER_FILE) {
                                    context.checkout context.scm
                                    context.docker.build("build-image", "--build-arg image=${buildConfig.DOCKER_IMAGE} -f ${buildConfig.DOCKER_FILE} .").inside {    
                                        buildScripts(cleanWorkspace, filename)
                                    }
                                } else {
                                    context.docker.image(buildConfig.DOCKER_IMAGE).pull()
                                    context.docker.image(buildConfig.DOCKER_IMAGE).inside {
                                        buildScripts(cleanWorkspace, filename)
                                    }
                                }
                            }

                        } else {
                            waitForANodeToBecomeActive(buildConfig.NODE_LABEL)
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
                        }
                    }

                    // Sign and archive jobs if needed
                    sign(versionInfo)

                    if (enableTests && buildConfig.TEST_LIST.size() > 0) {
                        try {
                            def testStages = runTests()
                            context.parallel testStages
                        } catch (Exception e) {
                            context.println "Failed test: ${e}"
                        }
                    }

                    //buildInstaller if needed
                    if (enableInstallers) {
                        buildInstaller(versionInfo)
                    }

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
