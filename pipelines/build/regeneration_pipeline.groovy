import java.io.File
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
def pipelines = [
  "openjdk15_pipeline", 
  "openjdk11_pipeline", 
  "openjdk12_pipeline", 
  "openjdk13_pipeline", 
  "openjdk14_pipeline", 
  "openjdk8_pipeline"
]

node ("master") {
  def scmVars = checkout scm
  load "${WORKSPACE}/pipelines/build/common/import_lib.groovy"
  Closure regenerationScript = load "${WORKSPACE}/pipelines/build/common/config_regeneration.groovy"

  // Run through pipeline configurations and pass them down to the job
  pipelines.each { pipeline -> 
    println "[INFO] Loading buildConfiguration for pipeline: $pipeline"

    //def pipelineConfiguration = new File("${WORKSPACE}/pipelines/build/${pipeline}.groovy")
    // Get buildConfigurations variable
    Closure pipelineConfig = load "${WORKSPACE}/pipelines/build/${pipeline}.groovy"

    def buildConfigurations = 
      pipelineConfig(
        null,
        null,
        null,
        null,
        null,
        null,
        null,
        null,
        null,
        null,
        null,
        null,
        null,
        null,
        null,
        null,
        null
      ).returnConfig()

    println "[DEBUG] buildConfigurations is: $buildConfigurations"

    regenerationScript(
      buildConfigurations,
      scmVars,
      currentBuild,
      this,
      env
    ).regenerate()
  }
}
