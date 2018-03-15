println "building OpenJDK10"
stage 'build OpenJDK'
def Platforms = [:]
Platforms["Linux"] = {
    node {
        build job: 'openjdk10_build_x86-64_linux', propagate: false
    }
}
Platforms["Mac"] = {
    node {
        build job: 'openjdk10_build_x86-64_macos'
    }
}
Platforms["Windows"] = {
    node {
        build job: 'openjdk10_build_x86-64_windows'
    }
}
Platforms["ppc64le"] = {
    node {
        build job: 'openjdk10_build_ppc64le_linux'
    }
}
Platforms["aix"] = {
    node {
        build job: 'openjdk10_build_ppc64_aix'
    }
}
Platforms["aarch64"] = {
    node {
        build job: 'openjdk10_build_arm64_linux'
    }
}
parallel Platforms
stage 'checksums'
node {
    def job = build job: 'openjdk10_build_checksum'
}
stage 'publish release'
node {
    def job = build job: 'openjdk_release_tool', parameters: [string(name: 'REPO', value: 'nightly'), string(name: 'TAG', value: "${JDK_TAG}"), string(name: 'VERSION', value: 'jdk10')]
}