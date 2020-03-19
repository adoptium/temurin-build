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

String javaVersion = "jdk11"

node ("master") {
  try {
    def scmVars = checkout scm
    load "${WORKSPACE}/pipelines/build/common/import_lib.groovy"
  
    def buildConfigurations = load "${WORKSPACE}/pipelines/jobs/configurations/${javaVersion}_pipeline_config.groovy"

    println "[INFO] Found buildConfigurations:\n$buildConfigurations"

    Closure regenerationScript = load "${WORKSPACE}/pipelines/build/common/config_regeneration.groovy"

    println "[INFO] Running regeneration script..."
    regenerationScript(
      javaVersion,
      buildConfigurations,
      scmVars,
      currentBuild,
      this,
      env
    ).regenerate()
      
    println "[SUCCESS] All done!"

  } finally {
    // Always clean up, even on failure (doesn't delete the dsls)
    println "[INFO] Cleaning up..."
    cleanWs()
  }
  
}
