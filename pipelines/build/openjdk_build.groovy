
//Params:
// TAG
// NODE_LABEL
// JAVA_TO_BUILD
// JDK_BOOT_VERSION
// CONFIGURE_ARGS
// BUILD_ARGS
// ARCHITECTURE
// VARIANT

currentBuild.displayName="${JAVA_TO_BUILD}-${ARCHITECTURE}-${VARIANT}"
node (NODE_LABEL) {
    checkout scm
    sh "${WORKSPACE}/build-farm/make-adopt-build-farm.sh"
}

