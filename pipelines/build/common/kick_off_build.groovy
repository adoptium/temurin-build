package common

import java.nio.file.NoSuchFileException
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
if (!LOCAL_DEFAULTS_JSON) {
    throw new Exception("[ERROR] No Defaults JSON found! Please ensure the DEFAULTS_JSON parameter is populated and not altered during parameter declaration.")
}
def ADOPT_DEFAULTS_JSON = new JsonSlurper().parseText(DEFAULTS_JSON) as Map
if (!ADOPT_DEFAULTS_JSON) {
    throw new Exception("[ERROR] No Adopt Defaults JSON found! Please ensure the ADOPT_DEFAULTS_JSON parameter is populated and not altered during parameter declaration.")
}

def libraryPath = (params.CUSTOM_LIBRARY_LOCATION) ?: LOCAL_DEFAULTS_JSON["importLibraryScript"]
def baseFilePath = (params.CUSTOM_BASEFILE_LOCATION) ?: LOCAL_DEFAULTS_JSON["baseFileDirectories"]["downstream"]

def downstreamBuilder = null
node("master") {
    /*
    Changes dir to Adopt's repo. Use closures as methods aren't accepted inside node blocks
    */
    def checkoutAdopt = { ->
      checkout([$class: 'GitSCM',
        branches: [ [ name: ADOPT_DEFAULTS_JSON["repository"]["branch"] ] ],
        userRemoteConfigs: [ [ url: ADOPT_DEFAULTS_JSON["repository"]["url"] ] ]
      ])
    }

    checkout scm

    try {
        load libraryPath
    } catch (NoSuchFileException e) {
        println "[WARNING] Using Adopt's import library script as none was found at ${libraryPath}"
        checkoutAdopt()
        load ADOPT_DEFAULTS_JSON["importLibraryScript"]
        checkout scm
    }

    try {
        downstreamBuilder = load baseFilePath
    } catch (NoSuchFileException e) {
        println "[WARNING] Using Adopt's base file script as none was found at ${baseFilePath}"
        checkoutAdopt()
        downstreamBuilder = load ADOPT_DEFAULTS_JSON["baseFileDirectories"]["downstream"]
        checkout scm
    }

}

downstreamBuilder(
    BUILD_CONFIGURATION,
    LOCAL_DEFAULTS_JSON,
    this,
    env,
    currentBuild
).build()
