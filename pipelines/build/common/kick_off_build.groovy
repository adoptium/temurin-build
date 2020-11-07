package common

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

// Downstream job root executor file, it sets up the library and runs the bash script setup job. 
def builder;
node("master") {
    checkout scm
    load "pipelines/build/common/import_lib.groovy"
    builder = load "pipelines/build/common/openjdk_build_pipeline.groovy"
}

builder(BUILD_CONFIGURATION,
        this,
        env,
        currentBuild).build()
