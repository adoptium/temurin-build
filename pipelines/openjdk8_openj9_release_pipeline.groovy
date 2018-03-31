/*
 * DO NOT EDIT DIRECTLY!  This code comes from https://github.com/AdoptOpenJDK/openjdk-build/pipelines/
 * please create a PR there before copying the code over
 */
println "building ${JDK_VERSION}"
stage('build OpenJDK') {
    def Platforms = [:]
    Platforms["Linux"] = {
        build job: 'openjdk8_openj9_build_x86-64_linux', parameters: [string(name: 'TAG', value: "${JDK_TAG}")]
    }
    Platforms["s390x"] = {
        build job: 'openjdk8_openj9_build_s390x_linux', parameters: [string(name: 'TAG', value: "${JDK_TAG}")]
    }
    Platforms["ppc64le"] = {
        build job: 'openjdk8_openj9_build_ppc64le_linux', parameters: [string(name: 'TAG', value: "${JDK_TAG}")]
    }
    Platforms["aix"] = {
        build job: 'openjdk8_openj9_build_ppc64_aix', parameters: [string(name: 'TAG', value: "${JDK_TAG}")]
    }
    parallel Platforms
}
stage('checksums') {
    build job: 'openjdk8_openj9_build_checksum'
}
stage('publish release') {
    build job: 'openjdk_release_tool', parameters: [string(name: 'REPO', value: 'releases'), string(name: 'TAG', value: "${JDK_TAG}"), string(name: 'VERSION', value: 'jdk8-openj9')]
}
