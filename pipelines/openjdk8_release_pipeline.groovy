println "building ${JDK_VERSION}"
stage ('build OpenJDK') {
    def Platforms = [:]
    Platforms["Mac"] = {
        node {
            build job: 'openjdk8_build_x86-64_macos'
        }
    }
    Platforms["Linux"] = {
        node {
            build job: 'openjdk8_build_x86-64_linux'
        }
    }
    Platforms["zLinux"] = {
        node {
            build job: 'openjdk8_build_s390x_linux'
        }
    }
    Platforms["ppc64le"] = {
        node {
            build job: 'openjdk8_build_ppc64le_linux'
        }
    }
    Platforms["Windows"] = {
        node {
            build job: 'openjdk8_build_x86-64_windows'
        }
    }
    Platforms["AIX"] = {
        node {
            build job: 'openjdk8_build_ppc64_aix'
        }
    }
    parallel Platforms
}
stage ('checksums') {
    node {
        def job = build job: 'openjdk8_build_checksum'
    }
}
stage ('installers') {
    node {
        def job = build job: 'openjdk8_build_installer', parameters: [string(name: 'VERSION', value: "${JDK_VERSION}")]
    }
}
stage ('publish release') {
    node {
        def job = build job: 'openjdk_release_tool', parameters: [string(name: 'REPO', value: 'release'), string(name: 'TAG', value: "${JDK_TAG}"), string(name: 'VERSION', value: 'jdk8')]
    }
}
