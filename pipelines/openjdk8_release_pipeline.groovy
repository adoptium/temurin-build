/*
 * DO NOT EDIT DIRECTLY!  This code comes from https://github.com/AdoptOpenJDK/openjdk-build/pipelines/
 * please create a PR there before copying the code over
 */
println "building ${JDK_VERSION}"
def buildPlatforms = ['Mac', 'Linux', 'zLinux', 'ppc64le', 'Windows', 'AIX']
def buildArchOSs = ['x86-64_macos', 'x86-64_linux', 's390x_linux', 'ppc64le_linux', 'x86-64_windows', 'ppc64_aix']
def buildjobMap = [:]
stage('build OpenJDK') {
	def buildJobs = [:]
	for ( int i = 0; i < buildPlatforms.size(); i++ ) {
		def index = i
		def platform = buildPlatforms[index]
		def archOS = buildArchOSs[index]
		buildJobs[platform] = {
			buildjobMap[platform] = build job: "openjdk8_build_${archOS}"
		}
	}
	parallel buildJobs
}

/*There are some platform unavailable for tests for now, temporarily run test builds on available platforms. Eventually should use same Map of build.*/
def testPlatforms = ['Mac', 'Linux', 'zLinux', 'ppc64le']
def testArchOSs = ['x86-64_macos', 'x86-64_linux', 's390x_linux', 'ppc64le_linux']
def typeTests = ['openjdktest', 'systemtest']
stage('testOpenJDK') {
	def testJobs = [:]
	for ( int i = 0; i < buildPlatforms.size(); i++ ) {
		def index = i
		def platform = testPlatforms[index]
		def archOS = testArchOSs[index]
		def buildJobNumber = buildjobMap[platform].getNumber()
		testJobs[platform] = {
			/*TODO the following openjdktest , systemtest are sequential, need to be parallel too.*/
			typeTests.each {
				build job:"openjdk8_hs_${it}_${archOS}",
						propagate: false,
						parameters: [string(name: 'UPSTREAM_JOB_NUMBER', value: "${buildJobNumber}"),
									 string(name: 'UPSTREAM_JOB_NAME', value: "openjdk8_build_${archOS}")]
			}
		}
	}
	parallel testJobs
}
stage('checksums') {
	build job: 'openjdk8_build_checksum'
}
stage('installers') {
	build job: 'openjdk8_build_installer', parameters: [string(name: 'VERSION', value: "${JDK_VERSION}")]
}
stage('publish release') {
	build job: 'openjdk_release_tool', parameters: [string(name: 'REPO', value: 'release'), string(name: 'TAG', value: "${JDK_TAG}"), string(name: 'VERSION', value: 'jdk8')]
}
