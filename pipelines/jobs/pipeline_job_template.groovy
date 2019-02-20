import groovy.json.JsonOutput

if (!binding.hasVariable('TEST')) TEST = true

triggerSchedual = "@daily"
gitRefSpec = ""

if (TEST) {
    triggerSchedual = "@yearly"
    gitRefSpec = "+refs/pull/*/head:refs/remotes/pull/* +refs/heads/master:refs/remotes/origin/master"
}

folder("${BUILD_FOLDER}")
folder("${BUILD_FOLDER}/jobs")

pipelineJob("${BUILD_FOLDER}/${JOB_NAME}") {
    definition {
        cpsScm {
            scm {
                git {
                    remote {
                        url("${GIT_URL}")
                        refspec(gitRefSpec)
                    }
                    branch("${BRANCH}")
                }
            }
            scriptPath(SCRIPT)
        }
    }
    triggers {
        cron(triggerSchedual)
    }
    logRotator {
        numToKeep(10)
        artifactNumToKeep(2)
    }

    properties {
        copyArtifactPermissionProperty {
            projectNames('*')
        }
    }

    parameters {
        textParam('targetConfigurations', JsonOutput.prettyPrint(JsonOutput.toJson(targetConfigurations)))
        booleanParam('publish', !TEST, 'If set to true the final assets will be published to github')
        stringParam('publishName', "", 'Name that release will be given when pushed to github.')
        booleanParam('release', false, 'If set to true this will be considered a release')
        stringParam('scmReference', "", 'Tag name or Branch name from which to build.')
        booleanParam('enableTests', !TEST, 'If set to true tests will be executed')
        stringParam('additionalConfigureArgs', "", "Arguments that will be ultimately passed to the java ./configure")
        stringParam('additionalBuildArgs', "", "Additional arguments to be passed to makejdk-any-platform.sh")
        stringParam('overrideFileNameVersion', "", "When forming the filename, ignore the build version and override it. For instance if you set this to 'FOO' the final file name will be of the form: OpenJDK8U-jre_ppc64le_linux_openj9_FOO.tar.gz")
        booleanParam('cleanWorkspaceBeforeBuild', false, "Clean out the workspace before the build")
        stringParam('adoptBuildNumber', "", "When releasing can add a adopt version number, currently this is only added to the build metadata")
    }
}