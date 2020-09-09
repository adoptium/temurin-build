package common

def builder;
node("master") {
    checkout scm
    publishChecks name: 'example', title: 'Pipeline Check', summary: 'check through pipeline', text: 'you can publish checks in pipeline script', detailsURL: 'https://github.com/jenkinsci/checks-api-plugin#pipeline-usage'
    load "pipelines/build/common/import_lib.groovy"
    builder = load "pipelines/build/common/openjdk_build_pipeline.groovy"
}

builder(BUILD_CONFIGURATION,
        this,
        env,
        currentBuild).build()
