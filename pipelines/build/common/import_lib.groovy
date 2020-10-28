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


// Imports our custom groovy library containing classes such as MetaData.groovy, VersionInfo.groovy, etc.
def path = "pipelines/library"
sh("cd ${path} && git init && git add --all . && git config user.email 'none' && git config user.name 'none' && git commit -m init &> /dev/null || true")
def repoPath = sh(returnStdout: true, script: "pwd").trim() + "/" + path;
library(identifier: 'local-lib@master', retriever: modernSCM([$class: 'GitSCMSource', remote: repoPath]))


