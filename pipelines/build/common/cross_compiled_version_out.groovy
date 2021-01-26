import org.jenkinsci.plugins.workflow.steps.FlowInterruptedException
/**
 * This file is a jenkins job for extracting a version string from a cross-compiled binary.
 * See https://github.com/AdoptOpenJDK/openjdk-build/issues/1773 for the inspiration for this.
 *
 * This file is referenced by the upstream job at pipelines/build/common/openjdk_build_pipeline.groovy.
 * This job is run at build-scripts/job/utils/job/cross-compiled-version-out/.
 *
 * The job looks like:
 *  1. Switch into a suitable node
 *  2. Retrieve the artifacts built in the upstream job
 *  3. Run java -version and export to file
 *  4. Expose to the upstream job by archiving file
 */

// TODO: ADD THE ACTIVE NODE TIMEOUT LOGIC HERE OR GET IT MERGED INTO JOB HELPER (https://github.com/AdoptOpenJDK/openjdk-build/issues/2235)
String nodeLabel = (params.NODE) ?: ""

node (nodeLabel) {
    timestamps {
        try {
            Integer JOB_TIMEOUT = 1
            timeout(time: JOB_TIMEOUT, unit: "HOURS") {
                String jobName = params.UPSTREAM_JOB_NAME ? params.UPSTREAM_JOB_NAME : ""
                String jobNumber = params.UPSTREAM_JOB_NUMBER ? params.UPSTREAM_JOB_NUMBER : ""
                String jdkFileFilter = params.JDK_FILE_FILTER ? params.JDK_FILE_FILTER : ""
                String fileName = params.FILENAME ? params.FILENAME : ""
                String os = params.OS ? params.OS : ""


                println "[INFO] PARAMS:"
                println "UPSTREAM_JOB_NAME = ${jobName}"
                println "UPSTREAM_JOB_NUMBER = ${jobNumber}"
                println "JDK_FILE_FILTER = ${jdkFileFilter}"
                println "FILENAME = ${fileName}"
                println "OS = ${os}"

                // Verify any previous binaries and versions have been cleaned out
                if (fileExists('OpenJDKBinary')) {
                    dir('OpenJDKBinary') {
                        deleteDir()
                    }
                }

                if (fileExists('CrossCompiledVersionOuts')) {
                    dir('CrossCompiledVersionOuts') {
                        deleteDir()
                    }
                }

                String versionOut = ""

                dir ("OpenJDKBinary") {
                    // Retrieve built JDK & unzip
                    println "[INFO] Retrieving build artifact from ${jobName}/${jobNumber} matching filter ${jdkFileFilter}"
                    copyArtifacts(
                        projectName: "${jobName}",
                        selector: specific("${jobNumber}"),
                        filter: "workspace/target/${jdkFileFilter}",
                        fingerprintArtifacts: true,
                        flatten: true
                    )

                    println "[INFO] Unzipping..."
                    if (os == "windows") {
                        sh "unzip ${jdkFileFilter} && rm ${jdkFileFilter}"
                    } else {
                        sh "tar -zxvf ${jdkFileFilter} && rm ${jdkFileFilter}"
                    }

                    String jdkDir = sh(
                        script: "ls | grep jdk",
                        returnStdout: true,
                        returnStatus: false
                    ).trim()

                    // Run java version and save to variable
                    dir(jdkDir) {
                        dir ("bin") {

                            println "[INFO] Running java -version on extracted binary ${jdkDir}..."

                            versionOut = sh(
                                script: "./java -version 2>&1",
                                returnStdout: true,
                                returnStatus: false
                            ).trim()

                            if (versionOut == "") {
                                throw new Exception("[ERROR] Java version was not retrieved or found!")
                            } else {
                                println "[INFO] Retrieved version string:\n${versionOut}"
                            }

                        }
                    }

                }

                // Write java version to file
                dir ("CrossCompiledVersionOuts") {
                    println "[INFO] Writing java version to ${fileName}..."
                    writeFile (
                        file: fileName,
                        text: versionOut
                    )
                    println "[INFO] ${fileName} contents:\n${readFile(fileName)}"
                }

                // Archive version.txt file
                println "[INFO] Archiving CrossCompiledVersionOuts/${fileName} to artifactory..."
                archiveArtifacts artifacts: "CrossCompiledVersionOuts/${fileName}"

                println "[SUCCESS] ${fileName} archived! Cleaning up..."
            }
        } catch (FlowInterruptedException e) {
            println "[ERROR] Job timeout (${JOB_TIMEOUT} HOURS) has been reached. Exiting..."
            throw new Exception()
        } finally {
            // Clean up and return to upstream job
            cleanWs notFailBuild: true, deleteDirs: true
        }
    }
}
