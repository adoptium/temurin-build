println "building ${JDK_VERSION}"

def buildPlatforms = ['Linux', 'zLinux', 'ppc64le', 'AIX', 'Windows', 'Windows32', 'LinuxXL']
def buildMaps = [:]
buildMaps['Linux'] = [test:['openjdktest', 'systemtest', 'perftest', 'externaltest'], ArchOSs:'x86-64_linux']
buildMaps['LinuxXL'] = buildMaps['AIX'] = [test:false, ArchOSs:'x86-64_linux_largeHeap']
buildMaps['zLinux'] = [test:['openjdktest', 'systemtest'], ArchOSs:'s390x_linux']
buildMaps['ppc64le'] = [test:['openjdktest', 'systemtest'], ArchOSs:'ppc64le_linux']
buildMaps['AIX'] = [test:false, ArchOSs:'ppc64_aix']
buildMaps['Windows'] = [test:['openjdktest'], ArchOSs:'x86-64_windows']
buildMaps['Windows32'] = [test:['openjdktest'], ArchOSs:'x86-32_windows']

def jobs = [:]
for ( int i = 0; i < buildPlatforms.size(); i++ ) {
	def index = i
	def platform = buildPlatforms[index]
	def archOS = buildMaps[platform].ArchOSs
	jobs[platform] = {
		def buildJob
		def buildJobNum
		def checksumJob
		stage('build') {
			buildJob = build job: "openjdk8_openj9_build_${archOS}"
			buildJobNum = buildJob.getNumber()
		}
		if (buildMaps[platform].test) {
			stage('test') {
				buildMaps[platform].test.each {
					build job:"openjdk8_j9_${it}_${archOS}",
							propagate: false,
							parameters: [string(name: 'UPSTREAM_JOB_NUMBER', value: "${buildJobNum}"),
									string(name: 'UPSTREAM_JOB_NAME', value: "openjdk8_openj9_build_${archOS}")]
				}
			}
		}
		stage('checksums') {
			checksumJob = build job: 'openjdk8_openj9_build_checksum',
							parameters: [string(name: 'UPSTREAM_JOB_NUMBER', value: "${buildJobNum}"),
									string(name: 'UPSTREAM_JOB_NAME', value: "openjdk8_openj9_build_${archOS}")]
		}
		stage('publish nightly') {
			build job: 'openjdk_release_tool',
						parameters: [string(name: 'REPO', value: 'nightly'),
									string(name: 'TAG', value: 'jdk8u172-b11'),
									string(name: 'VERSION', value: 'jdk8-openj9'),
									string(name: 'CHECKSUM_JOB_NAME', value: "openjdk8_openj9_build_checksum"),
									string(name: 'CHECKSUM_JOB_NUMBER', value: "${checksumJob.getNumber()}")]
		}
	}
}
parallel jobs

