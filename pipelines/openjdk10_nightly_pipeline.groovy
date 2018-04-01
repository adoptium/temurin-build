println "building ${JDK_VERSION}"
def buildPlatforms = ['Mac', 'Linux', 'ppc64le', 'Windows', 'AIX', 'aarch64']
def buildArchOSs = ['x86-64_macos', 'x86-64_linux', 'ppc64le_linux', 'x86-64_windows', 'ppc64_aix', 'arm64_linux']
def buildjobMap = [:]
stage('build OpenJDK') {
	def buildJobs = [:]
	for ( int i = 0; i < buildPlatforms.size(); i++ ) {
		def index = i
		def platform = buildPlatforms[index]
		def archOS = buildArchOSs[index]
		buildJobs[platform] = {
			buildjobMap[platform] = build job: "openjdk10_build_${archOS}"
		}
	}
	parallel buildJobs
}

/*There are some platform unavailable for tests for now, temporarily run test builds on available platforms. Eventually should use same Map of build.*/
def testPlatforms = ['Mac', 'Linux', 'ppc64le', 'aarch64']
def testArchOSs = ['x86-64_macos', 'x86-64_linux', 'ppc64le_linux', 'aarch64_linux']
def typeTests = ['openjdktest', 'systemtest']
stage('testOpenJDK') {
	def testJobs = [:]
	for ( int i = 0; i < testPlatforms.size(); i++ ) {
		def index = i
		def platform = testPlatforms[index]
		def archOS = testArchOSs[index]
		def buildJobNumber = buildjobMap[platform].getNumber()
		testJobs[platform] = {
			/*TODO the following openjdktest , systemtest are sequential, need to be parallel too.*/
			typeTests.each {
				build job:"openjdk10_hs_${it}_${archOS}",
						propagate: false,
						parameters: [string(name: 'UPSTREAM_JOB_NUMBER', value: "${buildJobNumber}"),
									 string(name: 'UPSTREAM_JOB_NAME', value: "openjdk10_build_${archOS}")]
			}
		}
	}
	parallel testJobs
}
stage('checksums') {
	build job: 'openjdk10_build_checksum'
}
stage('publish release') {
	build job: 'openjdk_release_tool', parameters: [string(name: 'REPO', value: 'nightly'), string(name: 'TAG', value: "${JDK_TAG}"), string(name: 'VERSION', value: 'jdk10')]
}
