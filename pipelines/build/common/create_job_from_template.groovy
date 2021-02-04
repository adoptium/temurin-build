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
 * A template that defines a build job.
 *
 * This mostly is just a wrapper to call the openjdk_build_pipeline.groovy script that defines the majority of
 * what a pipeline job does
 */

String buildFolder = "$JOB_FOLDER"

if (!binding.hasVariable('GIT_URL')) GIT_URL = "https://github.com/AdoptOpenJDK/openjdk-build.git"
if (!binding.hasVariable('GIT_BRANCH')) GIT_BRANCH = "master"

folder(buildFolder) {
    description 'Automatically generated build jobs.'
}

pipelineJob("$buildFolder/$JOB_NAME") {
    description('<h1>THIS IS AN AUTOMATICALLY GENERATED JOB DO NOT MODIFY, IT WILL BE OVERWRITTEN.</h1><p>This job is defined in create_job_from_template.groovy in the openjdk-build repo, if you wish to change it modify that</p>')
    definition {
        cpsScm {
            scm {
                git {
                    remote {
                        url(GIT_URL)
                        refspec(" +refs/pull/*:refs/remotes/origin/pr/* +refs/heads/master:refs/remotes/origin/master +refs/heads/*:refs/remotes/origin/*")
                        credentials("${CHECKOUT_CREDENTIALS}")
                    }
                    branch("${GIT_BRANCH}")
                    extensions {
                        //repo clean is performed after scm checkout in pipelines/build/common/openjdk_build_pipeline.groovy
                        pruneStaleBranch()
                    }
                }
            }
            scriptPath("${SCRIPT_PATH}")
        }
    }
    properties {
	disableConcurrentBuilds()
        copyArtifactPermission {
            projectNames('*')
        }
    }
    logRotator {
        numToKeep(30)
        artifactNumToKeep(1)
    }

    parameters {
        stringParam('NODE_LABEL', "$NODE_LABEL")
        textParam('BUILD_CONFIGURATION', "$BUILD_CONFIG", """
            <dl>
                <dt><strong>ARCHITECTURE</strong></dt><dd>x64, ppc64, s390x...</dd>
                <dt><strong>TARGET_OS</strong></dt><dd>windows, linux, aix...</dd>
                <dt><strong>VARIANT</strong></dt><dd>hotspot, openj9...</dd>
                <dt><strong>JAVA_TO_BUILD</strong></dt><dd>i.e jdk11u, jdk12u...</dd>
                <dt><strong>TEST_LIST</strong></dt><dd>Comma seperated list of tests, i.e: sanity.openjdk,sanity.perf,sanity.system</dd>
                <dt><strong>SCM_REF</strong></dt><dd>Source code ref to build, i.e branch, tag, commit id</dd>
                <dt><strong>BUILD_ARGS</strong></dt><dd>args to pass to makejdk-any-platform.sh</dd>
                <dt><strong>NODE_LABEL</strong></dt><dd>Labels of node to build on</dd>
                <dt><strong>ADDITIONAL_TEST_LABEL</strong></dt><dd>Additional label for test jobs</dd>
                <dt><strong>KEEP_TEST_REPORTDIR</strong></dt><dd>If true, test report dir (including core files where generated) will be kept even when the testcase passes, failed testcases always keep the report dir. Does not apply to JUnit jobs which are always kept, eg.openjdk.</dd>
                <dt><strong>ACTIVE_NODE_TIMEOUT</strong></dt><dd>Number of minutes we will wait for a label-matching node to become active.</dd>
                <dt><strong>CODEBUILD</strong></dt><dd>Use a dynamic codebuild machine if no other machine is available</dd>
                <dt><strong>DOCKER_IMAGE</strong></dt><dd>Use a docker build environment</dd>
                <dt><strong>DOCKER_FILE</strong></dt><dd>Relative path to a dockerfile to be built and used on top of the DOCKER_IMAGE</dd>
                <dt><strong>PLATFORM_CONFIG_LOCATION</strong></dt><dd>Repo owner, branch name and relative path to the platform specific configuration for this paticular OS</dd>
                <dt><strong>CONFIGURE_ARGS</strong></dt><dd>Arguments for ./configure. Escape all speech marks used within this parameter.</dd>
                <dt><strong>OVERRIDE_FILE_NAME_VERSION</strong></dt><dd>Set the version string on the file name</dd>
                <dt><strong>USE_ADOPT_SHELL_SCRIPTS</strong></dt><dd>Use Adopt's make-adopt-build-farm.sh and other bash scripts</dd>
                <dt><strong>RELEASE</strong></dt><dd>Is this build a release</dd>
                <dt><strong>PUBLISH_NAME</strong></dt><dd>Set name of publish</dd>
                <dt><strong>ADOPT_BUILD_NUMBER</strong></dt><dd>Adopt build number</dd>
                <dt><strong>ENABLE_TESTS</strong></dt><dd>Run tests</dd>
                <dt><strong>ENABLE_INSTALLERS</strong></dt><dd>Run installers</dd>
                <dt><strong>ENABLE_SIGNER</strong></dt><dd>Run signer</dd>
                <dt><strong>CLEAN_WORKSPACE</strong></dt><dd>Wipe out workspace before build</dd>
                <dt><strong>CLEAN_WORKSPACE_AFTER</strong></dt><dd>Wipe out workspace after build</dd>
                <dt><strong>CLEAN_WORKSPACE_BUILD_OUTPUT_ONLY_AFTER</strong></dt><dd>Wipe out workspace build output only, after build</dd>
            </dl>
        """)
        textParam('USER_REMOTE_CONFIGS', "$USER_REMOTE_CONFIGS", """
        <strong>DO NOT ALTER THIS PARAM UNLESS YOU KNOW WHAT YOU ARE DOING!</strong> This passes down the user's git checkout configs to the downstream job.
        """)
        textParam('DEFAULTS_JSON', "$DEFAULTS_JSON", """
        <strong>DO NOT ALTER THIS PARAM UNLESS YOU KNOW WHAT YOU ARE DOING!</strong> This passes the user's default constants to the downstream job.
        """)
        textParam('ADOPT_DEFAULTS_JSON', "$ADOPT_DEFAULTS_JSON", """
        <strong>DO NOT ALTER THIS PARAM UNDER ANY CIRCUMSTANCES!</strong> This passes down adopt's default constants to the downstream job. NOTE: <code>DEFAULTS_JSON</code> has priority, the constants contained within this param will only be used as a failsafe.
        """)
        if (binding.hasVariable('CUSTOM_LIBRARY_LOCATION')) {
            stringParam('CUSTOM_LIBRARY_LOCATION', "$CUSTOM_LIBRARY_LOCATION")
        }
        if (binding.hasVariable('CUSTOM_BASEFILE_LOCATION')) {
            stringParam('CUSTOM_BASEFILE_LOCATION', "$CUSTOM_BASEFILE_LOCATION")
        }
    }
}
