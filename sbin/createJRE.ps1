################################################################################
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
################################################################################

################################################################################
#
# createJRE.ps1
#
# Creates a JRE-like runtime using jlink
# Usage ./createJRE.ps1 <directory_to_create_jre>
#
################################################################################

# Get's the top level directory of the JDK
$jdkDirectory = [System.IO.Path]::GetDirectoryName($myInvocation.MyCommand.Path)

if ([string]::IsNullOrEmpty($args[0])) {
    # Throw error if output directory is not defined
    Write-Output "Please specify the path for the generated JRE"
    Write-Output "e.g ./makeJRE.ps1 C:/Users/jreruntime"
    exit 1
}

$jreDirectory=$args[0]
$binPath="$jdkDirectory/bin"

$jlink = Start-Process -PassThru -Wait "$binPath/jlink" -ArgumentList '--add-modules ALL-MODULE-PATH',`
    '--strip-debug',`
    '--no-man-pages',`
    '--no-header-files',`
    '--compress=2',`
    "--output $jreDirectory"

if ($jlink.ExitCode -eq 0) {
    Write-Output "Testing generated JRE"
} else {
    Write-Error "Error generating runtime with jlink"
    exit 1
}

$versionTest = Start-Process -PassThru -Wait "$jreDirectory/bin/java" -ArgumentList '--version'
if ($versionTest.ExitCode -eq 0) {
    Write-Output "Java Version test passed ✅`r`n"
} else {
    Write-Error "Java Version test failed ❌`r`n"
    exit 1
}
    
Write-Output "Success: Your JRE runtime is available at $jreDirectory"