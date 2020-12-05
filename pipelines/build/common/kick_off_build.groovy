package common

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

/*
Downstream job root executor file, it sets up the library and runs the bash script setup job.
*/

// We have to declare JSON defaults again because we're utilising it's content at start of job
def LOCAL_DEFAULTS_JSON = new JsonSlurper().parseText(DEFAULTS_JSON) as Map
def downstreamBuilder = null
node("master") {
    checkout scm
    load LOCAL_DEFAULTS_JSON["importLibraryScript"]
    downstreamBuilder = load LOCAL_DEFAULTS_JSON["baseFileDirectories"]["downstream"]
}

downstreamBuilder(
    BUILD_CONFIGURATION,
    LOCAL_DEFAULTS_JSON,
    this,
    env,
    currentBuild
).build()
