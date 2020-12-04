import groovy.json.JsonSlurper

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

//TODO: Change me
String DEFAULTS_FILE_URL = "https://raw.githubusercontent.com/M-Davies/openjdk-build/parameterised_everything/pipelines/build/defaults.json"

node("master") {
    // Retrieve Defaults
    def get = new URL(DEFAULTS_FILE_URL).openConnection()
    Map<String, ?> DEFAULTS_JSON = new JsonSlurper().parseText(get.getInputStream().getText()) as Map

    String branch = "${ghprbActualCommit}"
    String url = DEFAULTS_JSON['repository']['url']

    checkout([
        $class: 'GitSCM',
        branches: [[name: branch]],
        userRemoteConfigs: [[
            refspec: " +refs/pull/*/head:refs/remotes/origin/pr/*/head +refs/heads/master:refs/remotes/origin/master +refs/heads/*:refs/remotes/origin/*",
            url: url
        ]]
    ])

    Closure prTest = load DEFAULTS_JSON['scriptDirectories']['tester']

    prTest(
        branch,
        currentBuild,
        this,
        url,
        DEFAULTS_JSON
    ).runTests()
}
