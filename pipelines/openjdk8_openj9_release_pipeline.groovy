println "building ${JDK_VERSION}"

def buildPlatforms = ['Linux', 'zLinux', 'ppc64le', 'AIX', 'Windows']
def buildMaps = [:]
buildMaps['Linux'] = [test:true, ArchOSs:'x86-64_linux']
buildMaps['zLinux'] = [test:true, ArchOSs:'s390x_linux']
buildMaps['ppc64le'] = [test:true, ArchOSs:'ppc64le_linux']
buildMaps['AIX'] = [test:false, ArchOSs:'ppc64_aix']
buildMaps['Windows'] = [test:false, ArchOSs:'x86-64_windows']
def typeTests = ['openjdktest', 'systemtest']

def jobs = [:]
for ( int i = 0; i < buildPlatforms.size(); i++ ) {
	def index = i
	def platform = buildPlatforms[index]
	def archOS = buildMaps[platform].ArchOSs
	jobs[platform] = {
		def buildJob
		stage('build') {
			buildJob = build job: "openjdk8_openj9_build_${archOS}"
		}
		if (buildMaps[platform].test) {
			stage('test') {
				typeTests.each {
					build job:"openjdk8_j9_${it}_${archOS}",
							propagate: false,
							parameters: [string(name: 'UPSTREAM_JOB_NUMBER', value: "${buildJob.getNumber()}"),
									string(name: 'UPSTREAM_JOB_NAME', value: "openjdk8_openj9_build_${archOS}"),
									string(name: 'JVM_VERSION', value: 'openjdk8-openj9'),
									string(name: 'TARGET', value: 'sanity.openjdk')]
				}
			}
		}
	}
}
parallel jobs

def checksumJob
stage('checksums') {
	checksumJob = build job: 'openjdk8_openj9_build_checksum',
							parameters: [string(name: 'PRODUCT', value: 'releases')]
}
stage('publish release') {
	build job: 'openjdk_release_tool', 
		parameters: [string(name: 'REPO', value: 'releases'), 
					string(name: 'TAG', value: "${JDK_TAG}"), 
					string(name: 'VERSION', value: 'jdk8-openj9')，
					string(name: 'CHECKSUM_JOB_NAME', value: "openjdk8_openj9_build_checksum"),
					string(name: 'CHECKSUM_JOB_NUMBER', value: "${checksumJob.getNumber()}")]
}
