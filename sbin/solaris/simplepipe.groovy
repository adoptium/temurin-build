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

node('worker') {
    cleanWs notFailBuild: false
    def buildJob
    echo "Running pipeline using SCM_REF ${env.SCM_REF}"
    
    stage('build') { // for display purposes
        buildJob = build job: "build-scripts/jobs/jdk8u/jdk8u-solaris-${env.ARCHITECTURE}-temurin-simple",
            parameters: [
                 string(name: 'SCM_REF', value: "${env.SCM_REF}"),
                 booleanParam( name: 'RELEASE', value: "${env.RELEASE}" )
            ]
            
        copyArtifacts(
            projectName:"build-scripts/jobs/jdk8u/jdk8u-solaris-${env.ARCHITECTURE}-temurin-simple",
            selector:specific("${buildJob.getNumber()}"),
            target: ''
        )
        archiveArtifacts '**/workspace/target/*.*'
    }
    stage('sign_sbom_jsf') {
    
        def paramsJsf = [
                  string(name: 'UPSTREAM_JOB_NUMBER', value: "${env.BUILD_NUMBER}"),
                  string(name: 'UPSTREAM_JOB_NAME', value: "${env.JOB_NAME}"),
                  string(name: 'UPSTREAM_DIR', value: 'workspace/target'),
                  string(name: 'SBOM_LIBRARY_JOB_NUMBER', value: "lastSuccessfulBuild")
           ]
        def jsfSignJob = build job: 'build-scripts/release/sign_temurin_jsf', 
            parameters: paramsJsf
        copyArtifacts(
            projectName: 'build-scripts/release/sign_temurin_jsf',
            selector:specific("${jsfSignJob.getNumber()}"),
            target: 'workspace/target',
            flatten: true
        )
        archiveArtifacts '**/workspace/target/*sbom*.json'
        sh: "find . -name '*sbom*' -ls"
    }
    stage('sign_temurin_gpg') {
        def signJob=build job: 'build-scripts/release/sign_temurin_gpg',
        parameters: [
            string( name: 'UPSTREAM_JOB_NAME', value: "build-scripts/jobs/jdk8u/jdk8u-solaris-${env.ARCHITECTURE}-temurin-simplepipe"),
            string( name: 'UPSTREAM_JOB_NUMBER', value: "${env.BUILD_ID}"),
            string( name: 'UPSTREAM_DIR', value: 'workspace/target')
        ]
        copyArtifacts(
            projectName:'build-scripts/release/sign_temurin_gpg',
            selector:specific("${signJob.getNumber()}"),
            target: 'workspace/target',
            flatten: true
        )
        //archiveArtifacts 'workspace/target/*.gpg'
        archiveArtifacts '**/*.sig'
    }
    stage('test') {
        if ( params.ENABLE_TESTS == true ) {
            warnError("The command failed") {
                testJob = build job: "build-scripts/jobs/jdk8u/jdk8u-solaris-${env.ARCHITECTURE}-temurin-simpletest",
                parameters: [
                    string( name: 'UPSTREAM_JOBLINK', value: "https://ci.adoptium.net/job/build-scripts/job/jobs/job/jdk8u/job/jdk8u-solaris-${env.ARCHITECTURE}-temurin-simplepipe/${env.BUILD_ID}")
                ]
            }
        }
    }
    // Note: This stage will fail if SCM_REF is blank
    
    stage('release') {
        // Release name under temurin8-binaries does not have _adopt suffix
        def releaseTag = env.SCM_REF.replaceAll('_adopt','-ea')
        // Line below copied from build_base_file.groovy
        def timestamp = new Date().format('yyyy-MM-dd-HH-mm', TimeZone.getTimeZone('UTC'))

        build job: 'build-scripts/release/refactor_openjdk_release_tool',
        parameters: [
            string( name: 'VERSION', value: 'jdk8'),
            string( name: 'UPSTREAM_JOB_NAME', value: "build-scripts/jobs/jdk8u/jdk8u-solaris-${env.ARCHITECTURE}-temurin-simplepipe"),
            string( name: 'UPSTREAM_JOB_NUMBER', value: "$env.BUILD_ID"),
            string( name: 'TAG', value: "$releaseTag"),
            // string( name: 'TIMESTAMP', value: "${env.TIMESTAMP}"),
            string( name: 'TIMESTAMP', value: timestamp),
            booleanParam( name: 'DRY_RUN', value: params.DRY_RUN),
            string( name: 'ARTIFACTS_TO_COPY', value: "**/*.tar.gz,**/*.zip,**/*.sha256.txt,**/*.json,**/*.sig")
        ]
    }
    stage('Results') {
        // THESE PHASES NEED US TO COPY THE ARTIFACTS FROM BUILD/TEST
        // ALSO WHEN THAT IS DONE WE WON'T NEED TO OVERRIDE ARTIFACTS_TO_COPY IN THE RELEASE INVOCATION
        // ALSO NOTE THAT WHEN COPYING UP THE STUFF WILL NEED TO BE IN THE TEMURIN DIR
        // junit '**/target/surefire-reports/TEST-*.xml'
        // archiveArtifacts 'workspace/target/*.gz'
    }
}
