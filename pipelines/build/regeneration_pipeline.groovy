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

// This will need to be updated when jdk HEAD updates
def pipelineConfigs = [
  "jdk15_pipeline_config", 
  "jdk11_pipeline_config", 
  "jdk12_pipeline_config", 
  "jdk13_pipeline_config", 
  "jdk14_pipeline_config", 
  "jdk8_pipeline_config"
]

node ("master") {
  def scmVars = checkout scm
  load "${WORKSPACE}/pipelines/build/common/import_lib.groovy"
  Closure regenerationScript = load "${WORKSPACE}/pipelines/build/common/config_regeneration.groovy"

  // Run through pipeline configurations and pass them down to the job
  pipelineConfigs.each { config -> 
  
    // Get buildConfiguration
    println "[INFO] Loading Pipeline Config File: $config"
    Closure buildConfigurations = load "${WORKSPACE}/pipelines/jobs/configurations/${config}.groovy"

    println "[DEBUG] buildConfigurations class is ${buildConfigurations.getClass()}"
    println "[DEBUG] buildConfigurations is: $buildConfigurations"

    println "[INFO] Running regeneration script..."
    regenerationScript(
      buildConfigurations,
      scmVars,
      currentBuild,
      this,
      env
    ).regenerate()

    println "[SUCCESS] Pipeline $config regenerated."
  }
}
