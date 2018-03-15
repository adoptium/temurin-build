stage 'build OpenJDK'
def Platforms = [:]
Platforms["Linux"] = {
    node {
        build job: 'openjdk8_openj9_build_x86-64_linux', parameters: [string(name: 'TAG', value: "${JDK_TAG}")]
    }
}
Platforms["s390x"] = {
    node {
        build job: 'openjdk8_openj9_build_s390x_linux', parameters: [string(name: 'TAG', value: "${JDK_TAG}")]
    }
}
Platforms["ppc64le"] = {
    node {
        build job: 'openjdk8_openj9_build_ppc64le_linux', parameters: [string(name: 'TAG', value: "${JDK_TAG}")]
    }
}
Platforms["aix"] = {
    node {
        build job: 'openjdk8_openj9_build_ppc64_aix', parameters: [string(name: 'TAG', value: "${JDK_TAG}")]
    }
}
parallel Platforms
stage 'checksums'
node {
    def job = build job: 'openjdk8_openj9_build_checksum'
}
stage 'publish release'
node {
    def job = build job: 'openjdk_release_tool', parameters: [string(name: 'REPO', value: 'releases'), string(name: 'TAG', value: "${JDK_TAG}"), string(name: 'VERSION', value: 'jdk8-openj9')]
}