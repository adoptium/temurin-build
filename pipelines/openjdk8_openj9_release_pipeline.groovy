println "building ${JDK_VERSION}"

def buildPlatforms = ['Linux', 'zLinux', 'ppc64le', 'AIX']
def buildMaps = [:]
buildMaps['Linux'] = [build:true, test:true, ArchOSs:'x86-64_linux']
buildMaps['zLinux'] = [build:true, test:true, ArchOSs:'s390x_linux']
buildMaps['ppc64le'] = [build:true, test:true, ArchOSs:'ppc64le_linux']
buildMaps['AIX'] = [build:true, test:false, ArchOSs:'ppc64_aix']
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
									string(name: 'UPSTREAM_JOB_NAME', value: "openjdk8_openj9_build_${archOS}")]
				}
			}
		}
	}
}
parallel jobs

stage('checksums') {
	build job: 'openjdk8_openj9_build_checksum'
}
stage('publish release') {
	build job: 'openjdk_release_tool', parameters: [string(name: 'REPO', value: 'releases'), string(name: 'TAG', value: "${JDK_TAG}"), string(name: 'VERSION', value: 'jdk8-openj9')]
}
