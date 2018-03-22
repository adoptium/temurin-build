/*
 * DO NOT EDIT DIRECTLY!  This code comes from https://github.com/AdoptOpenJDK/openjdk-build/pipelines/
 * please create a PR there before copying the code over
 */
println "building ${JDK_VERSION}"
stage('build OpenJDK') {
    def Platforms = [:]
    Platforms["Linux"] = {
        build job: 'openjdk_amber_build_x86-64_linux'
    }
    Platforms["Mac"] = {
        build job: 'openjdk_amber_build_x86-64_macos'
    }
    Platforms["Windows"] = {
        build job: 'openjdk_amber_build_x86-64_windows'
    }
    parallel Platforms
}
stage('checksums') {
    build job: 'openjdk_amber_build_checksum'
}
stage('publish release') {
    build job: 'openjdk_release_tool', parameters: [string(name: 'REPO', value: 'nightly'), string(name: 'TAG', value: "${JDK_TAG}"), string(name: 'VERSION', value: 'jdk-amber')]
}
