println "building ${JDK_VERSION}"

def buildPlatforms = ['Mac', 'Linux', 'Windows']
def buildMaps = [:]
buildMaps['Mac'] = [test:false, ArchOSs:'x86-64_macos']
buildMaps['Windows'] = [test:false, ArchOSs:'x86-64_windows']
buildMaps['Linux'] = [test:false, ArchOSs:'x86-64_linux']
def typeTests = ['openjdktest', 'systemtest']

def jobs = [:]
for ( int i = 0; i < buildPlatforms.size(); i++ ) {
	def index = i
	def platform = buildPlatforms[index]
	def archOS = buildMaps[platform].ArchOSs
	jobs[platform] = {
		def buildJob
		stage('build') {
			buildJob = build job: "openjdk_amber_build_${archOS}"
		}
	}
}
parallel jobs

stage('checksums') {
	build job: 'openjdk_amber_build_checksum'
}
stage('publish nightly') {
	build job: 'openjdk_release_tool', parameters: [string(name: 'REPO', value: 'nightly'), string(name: 'TAG', value: "${JDK_TAG}"), string(name: 'VERSION', value: 'jdk-amber')]
}
