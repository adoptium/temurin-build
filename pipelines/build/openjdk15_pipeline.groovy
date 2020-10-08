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

def javaToBuild = "jdk15u"
def scmVars = null
Closure configureBuild = null
def buildConfigurations = null

node ("master") {
    scmVars = checkout scm
    load "${WORKSPACE}/pipelines/build/common/import_lib.groovy"
    configureBuild = load "${WORKSPACE}/pipelines/build/common/build_base_file.groovy"
    buildConfigurations = load "${WORKSPACE}/pipelines/jobs/configurations/${javaToBuild}_pipeline_config.groovy"
}

if (scmVars != null && configureBuild != null && buildConfigurations != null) {
    configureBuild(
        javaToBuild,
        buildConfigurations,
        targetConfigurations,
        activeNodeTimeout,
        dockerExcludes,
        enableTests,
        enableInstallers,
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
        currentBuild,
        this,
        env
    ).doBuild()
} else {
    println "[ERROR] One or more setup parameters are null.\nscmVars = ${scmVars}\nconfigureBuild = ${configureBuild}\nbuildConfigurations = ${buildConfigurations}"
    throw new Exception()
}