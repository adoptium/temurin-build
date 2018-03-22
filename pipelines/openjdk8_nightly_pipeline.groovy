/*
 * DO NOT EDIT DIRECTLY!  This code comes from https://github.com/AdoptOpenJDK/openjdk-build/pipelines/
 * please create a PR there before copying the code over
 */
println "building ${JDK_VERSION}"
stage('build OpenJDK') {
    def Platforms = [:]
    Platforms["Mac"] = {
        def buildJob = build job: 'openjdk8_build_x86-64_macos'
        def buildJobNumber = buildJob.getNumber()
        build job:'openjdk8_hs_openjdktest_x86-64_macos',
            propagate: false,
            parameters: [string(name: 'UPSTREAM_JOB_NUMBER', value: "${buildJob.getNumber()}")]
    }
    Platforms["Linux"] = {
        build job: 'openjdk8_build_x86-64_linux'
    }
    Platforms["zLinux"] = {
        build job: 'openjdk8_build_s390x_linux'
    }
    Platforms["ppc64le"] = {
        build job: 'openjdk8_build_ppc64le_linux'
    }
    Platforms["Windows"] = {
        build job: 'openjdk8_build_x86-64_windows'
    }
    Platforms["AIX"] = {
        build job: 'openjdk8_build_ppc64_aix'
    }
    parallel Platforms
}
stage('checksums') {
    build job: 'openjdk8_build_checksum'
}
stage('publish nightly') {
    build job: 'openjdk_release_tool', parameters: [string(name: 'REPO', value: 'nightly'), string(name: 'TAG', value: 'jdk8u172-b00'), string(name: 'VERSION', value: 'jdk8')]
}
