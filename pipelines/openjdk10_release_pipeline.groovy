println "building ${JDK_VERSION}"

def buildPlatforms = ['Mac', 'Windows', 'Linux', 'zLinux', 'ppc64le', 'AIX', 'aarch64']
def buildMaps = [:]
def PIPELINE_TIMESTAMP = new Date(currentBuild.startTimeInMillis).format("yyyyMMddHHmm")

buildMaps['Mac'] = [test:['openjdktest', 'systemtest'], ArchOSs:'x86-64_macos']
buildMaps['Windows'] = [test:['openjdktest'], ArchOSs:'x86-64_windows']
buildMaps['Linux'] = [test:['openjdktest', 'systemtest'], ArchOSs:'x86-64_linux']
buildMaps['zLinux'] = [test:['openjdktest', 'systemtest'], ArchOSs:'s390x_linux']
buildMaps['ppc64le'] = [test:['openjdktest', 'systemtest'], ArchOSs:'ppc64le_linux']
buildMaps['AIX'] = [test:false, ArchOSs:'ppc64_aix']
buildMaps['aarch64'] = [test:['openjdktest'], ArchOSs:'aarch64_linux']

def jobs = [:]
for ( int i = 0; i < buildPlatforms.size(); i++ ) {
	def index = i
	def platform = buildPlatforms[index]
	def archOS = buildMaps[platform].ArchOSs
	jobs[platform] = {
		def buildJob
		stage('build') {
			buildJob = build job: "openjdk10_build_${archOS}",
			parameters: [string(name: 'TAG', value: "${JDK_TAG}"),
				     string(name: 'PIPELINE_TIMESTAMP', value: "${PIPELINE_TIMESTAMP}")]
		}
		if (buildMaps[platform].test) {
			buildMaps[platform].test.each {
				typeTests.each {
					build job:"openjdk10_hs_${it}_${archOS}",
							propagate: false,
							parameters: [string(name: 'UPSTREAM_JOB_NUMBER', value: "${buildJob.getNumber()}"),
									string(name: 'UPSTREAM_JOB_NAME', value: "openjdk10_build_${archOS}")]
				}
			}
		}
	}
}
parallel jobs

def checksumJob
stage('checksums') {
	checksumJob = build job: 'openjdk10_build_checksum',
							parameters: [string(name: 'PRODUCT', value: 'releases')]
}
stage('installers') {
	build job: 'openjdk10_build_installer', parameters: [string(name: 'VERSION', value: "${JDK_VERSION}")]
}
stage('publish release') {
	build job: 'openjdk_release_tool',
				parameters: [string(name: 'REPO', value: 'releases'),
							string(name: 'TAG', value: "${JDK_TAG}"),
							string(name: 'VERSION', value: 'jdk10'),
							string(name: 'CHECKSUM_JOB_NAME', value: "openjdk10_build_checksum"),
							string(name: 'CHECKSUM_JOB_NUMBER', value: "${checksumJob.getNumber()}")]
}
