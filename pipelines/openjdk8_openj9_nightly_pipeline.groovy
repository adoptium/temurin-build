stage ('build OpenJDK') {
    def Platforms = [:]
    Platforms["Linux"] = {
        node {
            build job: 'openjdk8_openj9_build_x86-64_linux', propagate: false
        }
    }
    Platforms["s390x"] = {
        node {
            build job: 'openjdk8_openj9_build_s390x_linux'
        }
    }
    Platforms["ppc64le"] = {
        node {
            build job: 'openjdk8_openj9_build_ppc64le_linux'
        }
    }
    Platforms["aix"] = {
        node {
            build job: 'openjdk8_openj9_build_ppc64_aix'
        }
    }
    parallel Platforms
}
stage ('checksums') {
    node {
        def job = build job: 'openjdk8_openj9_build_checksum'
    }
}
stage ('publish nightly') {
    node {
        def job = build job: 'openjdk_release_tool', parameters: [string(name: 'REPO', value: 'nightly'), string(name: 'TAG', value: 'jdk8u162-b12'), string(name: 'VERSION', value: 'jdk8-openj9')]
    }
}
