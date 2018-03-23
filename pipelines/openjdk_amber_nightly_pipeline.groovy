/*
 * DO NOT EDIT DIRECTLY!  This code comes from https://github.com/AdoptOpenJDK/openjdk-build/pipelines/
 * please create a PR there before copying the code over
 */
println "building ${JDK_VERSION}"

def buildPlatforms = ['Mac', 'Linux', 'Windows']
def buildArchOSs = ['x86-64_macos', 'x86-64_linux', 'x86-64_windows']
def buildjobMap = [:]
stage('build OpenJDK') {
	def buildJobs = [:]
    for ( int i = 0; i < buildPlatforms.size(); i++ ) {
    	def index = i
    	def platform = buildPlatforms[index]
    	def archOS = buildArchOSs[index]
		buildJobs[platform] = {
			buildjobMap[platform] = build job: "openjdk_amber_build_${archOS}"
		}
	}
	parallel buildJobs
}

stage('checksums') {
    build job: 'openjdk_amber_build_checksum'
}
stage('publish release') {
    build job: 'openjdk_release_tool', parameters: [string(name: 'REPO', value: 'nightly'), string(name: 'TAG', value: "${JDK_TAG}"), string(name: 'VERSION', value: 'jdk-amber')]
}
