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

def javaToBuild = "jdk9u"
def scmVars = null
Closure configureBuild = null
def buildConfigurations = null
Map<String, ?> DEFAULTS_JSON = null

node ("master") {
    scmVars = checkout scm

    // Load defaultsJson. These are passed down from the build_pipeline_generator and is a JSON object containing some default constants.
    if (!params.defaultsJson || defaultsJson == "") {
        throw new Exception("[ERROR] No Defaults JSON found! Please ensure the defaultsJson parameter is populated and not altered during parameter declaration.")
    } else {
        DEFAULTS_JSON = new JsonSlurper().parseText(defaultsJson) as Map
    }

    load "${WORKSPACE}/${DEFAULTS_JSON['importLibraryScript']}"

    // Load baseFilePath. This is where build_base_file.groovy is located. It runs the downstream job setup and configuration retrieval services.
    if (params.baseFilePath) {
        configureBuild = load "${WORKSPACE}/${baseFilePath}"
    } else {
        configureBuild = load "${WORKSPACE}/${DEFAULTS_JSON['baseFileDirectories']['upstream']}"
    }

    // Load buildConfigFilePath. This is where jdkxx_pipeline_config.groovy is located. It contains the build configurations for each platform, architecture and variant.
    if (params.buildConfigFilePath) {
        buildConfigurations = load "${WORKSPACE}/${buildConfigFilePath}"
    } else {
        buildConfigurations = load "${WORKSPACE}/${DEFAULTS_JSON['configDirectories']['build']}/${javaToBuild}_pipeline_config.groovy"
    }

}

// If a parameter below hasn't been declared above, it is declared in the jenkins job itself
if (scmVars != null || configureBuild != null || buildConfigurations != null) {
    configureBuild(
        javaToBuild,
        buildConfigurations,
        targetConfigurations,
        DEFAULTS_JSON,
        activeNodeTimeout,
        dockerExcludes,
        enableTests,
        enableInstallers,
        enableSigner,
        releaseType,
        scmReference,
        overridePublishName,
        additionalConfigureArgs,
        scmVars,
        additionalBuildArgs,
        overrideFileNameVersion,
        cleanWorkspaceBeforeBuild,
        adoptBuildNumber,
        propagateFailures,
        keepTestReportDir,
        keepReleaseLogs,
        currentBuild,
        this,
        env
    ).doBuild()
} else {
    throw new Exception("[ERROR] One or more setup parameters are null.\nscmVars = ${scmVars}\nconfigureBuild = ${configureBuild}\nbuildConfigurations = ${buildConfigurations}")
}
