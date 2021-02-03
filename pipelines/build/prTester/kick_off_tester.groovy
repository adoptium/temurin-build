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

node("master") {
    // Don't parameterise url as we currently have no need and the job generates its own params anyway
    String branch = "${ghprbActualCommit}"
    String DEFAULTS_FILE_URL = "https://raw.githubusercontent.com/AdoptOpenJDK/openjdk-build/${branch}/pipelines/defaults.json"

    // Retrieve User defaults
    def getUser = new URL(DEFAULTS_FILE_URL).openConnection()
    Map<String, ?> DEFAULTS_JSON = new JsonSlurper().parseText(getUser.getInputStream().getText()) as Map
    if (!DEFAULTS_JSON) {
        throw new Exception("[ERROR] No DEFAULTS_JSON found at ${DEFAULTS_FILE_URL}. Please ensure this path is correct and it leads to a JSON or Map object file.")
    }

    String url = DEFAULTS_JSON['repository']['url']
    checkout([
        $class: 'GitSCM',
        branches: [[name: branch]],
        userRemoteConfigs: [[
            refspec: " +refs/pull/*/head:refs/remotes/origin/pr/*/head +refs/heads/master:refs/remotes/origin/master +refs/heads/*:refs/remotes/origin/*",
            url: url
        ]]
    ])

    load DEFAULTS_JSON['importLibraryScript']
    Closure prTest = load DEFAULTS_JSON['scriptDirectories']['tester']

    prTest(
        branch,
        currentBuild,
        this,
        url,
        DEFAULTS_JSON
    ).runTests()
}
