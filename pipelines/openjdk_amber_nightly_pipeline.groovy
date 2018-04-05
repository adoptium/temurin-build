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
		def checksumJob
		stage('build') {
			buildJob = build job: "openjdk_amber_build_${archOS}"
		}
		stage('checksums') {
			checksumJob = build job: 'openjdk_amber_build_checksum',
							parameters: [string(name: 'UPSTREAM_JOB_NUMBER', value: "${buildJob.getNumber()}"),
									string(name: 'UPSTREAM_JOB_NAME', value: "openjdk_amber_build_${archOS}")]
		}
		stage('publish nightly') {
			build job: 'openjdk_release_tool',
						parameters: [string(name: 'REPO', value: 'nightly'),
									string(name: 'TAG', value: "${JDK_TAG}"),
									string(name: 'VERSION', value: 'jdk-amber'),
									string(name: 'CHECKSUM_JOB_NAME', value: "openjdk_amber_build_checksum"),
									string(name: 'CHECKSUM_JOB_NUMBER', value: "${checksumJob.getNumber()}")]
		}
	}
}
parallel jobs
