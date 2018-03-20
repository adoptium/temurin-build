println "building OpenJDK amber"
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
    node {
        def job = build job: 'openjdk_amber_build_checksum'
    }
}
stage('publish release') {
    node {
        def job = build job: 'openjdk_release_tool', parameters: [string(name: 'REPO', value: 'nightly'), string(name: 'TAG', value: "${JDK_TAG}"), string(name: 'VERSION', value: 'jdk-amber')]
    }
}
