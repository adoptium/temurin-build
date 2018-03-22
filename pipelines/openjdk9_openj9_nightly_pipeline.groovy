/*
 * DO NOT EDIT DIRECTLY!  This code comes from https://github.com/AdoptOpenJDK/openjdk-build/pipelines/
 * please create a PR there before copying the code over
 */
println "building ${JDK_VERSION}"
stage('build OpenJDK') {
    def Platforms = [:]
    Platforms["Linux"] = {
        build job: 'openjdk9_openj9_build_x86-64_linux'
    }
    Platforms["Windows"] = {
        build job: 'openjdk9_openj9_build_x86-64_windows'
    }
    Platforms["s390x"] = {
        build job: 'openjdk9_openj9_build_s390x_linux'
    }
    Platforms["ppc64le"] = {
        build job: 'openjdk9_openj9_build_ppc64le_linux'
    }
    Platforms["aix"] = {
        build job: 'openjdk9_openj9_build_ppc64_aix'
    }
    parallel Platforms
}
stage('checksums') {
    build job: 'openjdk9_openj9_build_checksum'
}
stage('publish nightly') {
    build job: 'openjdk_release_tool', parameters: [string(name: 'REPO', value: 'nightly'), string(name: 'TAG', value: 'jdk-9+181'), string(name: 'VERSION', value: 'jdk9-openj9')]
}
