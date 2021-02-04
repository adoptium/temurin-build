package common

import groovy.json.JsonOutput
import groovy.json.JsonSlurper

class IndividualBuildConfig implements Serializable {
    final String ARCHITECTURE
    final String TARGET_OS
    final String VARIANT
    final String JAVA_TO_BUILD
    final List<String> TEST_LIST
    final String SCM_REF
    final String BUILD_ARGS
    final String NODE_LABEL
    final String ADDITIONAL_TEST_LABEL
    final boolean KEEP_TEST_REPORTDIR
    final String ACTIVE_NODE_TIMEOUT
    final boolean CODEBUILD
    final String DOCKER_IMAGE
    final String DOCKER_FILE
    final String DOCKER_NODE
    final String PLATFORM_CONFIG_LOCATION
    final String CONFIGURE_ARGS
    final String OVERRIDE_FILE_NAME_VERSION
    final boolean USE_ADOPT_SHELL_SCRIPTS
    final String ADDITIONAL_FILE_NAME_TAG
    final String JDK_BOOT_VERSION
    final boolean RELEASE
    final String PUBLISH_NAME
    final String ADOPT_BUILD_NUMBER
    final boolean ENABLE_TESTS
    final boolean ENABLE_INSTALLERS
    final boolean ENABLE_SIGNER
    final boolean CLEAN_WORKSPACE
    final boolean CLEAN_WORKSPACE_AFTER
    final boolean CLEAN_WORKSPACE_BUILD_OUTPUT_ONLY_AFTER

    IndividualBuildConfig(String json) {
        this(new JsonSlurper().parseText(json) as Map)
    }

    IndividualBuildConfig(Map<String, ?> map) {
        ARCHITECTURE = map.get("ARCHITECTURE")
        TARGET_OS = map.get("TARGET_OS")
        VARIANT = map.get("VARIANT")
        JAVA_TO_BUILD = map.get("JAVA_TO_BUILD")

        if (String.class.isInstance(map.get("TEST_LIST"))) {
            TEST_LIST = map.get("TEST_LIST").split(",")
        } else if (List.class.isInstance(map.get("TEST_LIST"))) {
            TEST_LIST = map.get("TEST_LIST")
        } else {
            TEST_LIST = []
        }

        SCM_REF = map.get("SCM_REF")
        BUILD_ARGS = map.get("BUILD_ARGS")
        NODE_LABEL = map.get("NODE_LABEL")
        ADDITIONAL_TEST_LABEL = map.get("ADDITIONAL_TEST_LABEL")
        KEEP_TEST_REPORTDIR = map.get("KEEP_TEST_REPORTDIR")
        ACTIVE_NODE_TIMEOUT = map.get("ACTIVE_NODE_TIMEOUT")
        CODEBUILD = map.get("CODEBUILD")
        DOCKER_IMAGE = map.get("DOCKER_IMAGE")
        DOCKER_FILE = map.get("DOCKER_FILE")
        DOCKER_NODE = map.get("DOCKER_NODE")
        PLATFORM_CONFIG_LOCATION = map.get("PLATFORM_CONFIG_LOCATION")
        CONFIGURE_ARGS = map.get("CONFIGURE_ARGS")
        OVERRIDE_FILE_NAME_VERSION = map.get("OVERRIDE_FILE_NAME_VERSION")
        USE_ADOPT_SHELL_SCRIPTS = map.get("USE_ADOPT_SHELL_SCRIPTS")
        ADDITIONAL_FILE_NAME_TAG = map.get("ADDITIONAL_FILE_NAME_TAG")
        JDK_BOOT_VERSION = map.get("JDK_BOOT_VERSION")
        RELEASE = map.get("RELEASE")
        PUBLISH_NAME = map.get("PUBLISH_NAME")
        ADOPT_BUILD_NUMBER = map.get("ADOPT_BUILD_NUMBER")
        ENABLE_TESTS = map.get("ENABLE_TESTS")
        ENABLE_INSTALLERS = map.get("ENABLE_INSTALLERS")
        ENABLE_SIGNER = map.get("ENABLE_SIGNER")
        CLEAN_WORKSPACE = map.get("CLEAN_WORKSPACE")
        CLEAN_WORKSPACE_AFTER = map.get("CLEAN_WORKSPACE_AFTER")
        CLEAN_WORKSPACE_BUILD_OUTPUT_ONLY_AFTER = map.get("CLEAN_WORKSPACE_BUILD_OUTPUT_ONLY_AFTER")
    }

    Map<String, ?> toMap() {
        toRawMap().findAll { key, value ->
            value != null
        }
    }

    List<String> toEnvVars() {
        return toRawMap().collect { key, value ->
            if (value == null) {
                value = ""
            }
            return "${key}=${value}"
        }
    }

    Map<String, ?> toRawMap() {
        [
                ARCHITECTURE              : ARCHITECTURE,
                TARGET_OS                 : TARGET_OS,
                VARIANT                   : VARIANT,
                JAVA_TO_BUILD             : JAVA_TO_BUILD,
                TEST_LIST                 : TEST_LIST,
                SCM_REF                   : SCM_REF,
                BUILD_ARGS                : BUILD_ARGS,
                NODE_LABEL                : NODE_LABEL,
                ADDITIONAL_TEST_LABEL     : ADDITIONAL_TEST_LABEL,
                KEEP_TEST_REPORTDIR       : KEEP_TEST_REPORTDIR,
                ACTIVE_NODE_TIMEOUT       : ACTIVE_NODE_TIMEOUT,
                CODEBUILD                 : CODEBUILD,
                DOCKER_IMAGE              : DOCKER_IMAGE,
                DOCKER_FILE               : DOCKER_FILE,
                DOCKER_NODE               : DOCKER_NODE,
                PLATFORM_CONFIG_LOCATION  : PLATFORM_CONFIG_LOCATION,
                CONFIGURE_ARGS            : CONFIGURE_ARGS,
                OVERRIDE_FILE_NAME_VERSION: OVERRIDE_FILE_NAME_VERSION,
                USE_ADOPT_SHELL_SCRIPTS   : USE_ADOPT_SHELL_SCRIPTS,
                ADDITIONAL_FILE_NAME_TAG  : ADDITIONAL_FILE_NAME_TAG,
                JDK_BOOT_VERSION          : JDK_BOOT_VERSION,
                RELEASE                   : RELEASE,
                PUBLISH_NAME              : PUBLISH_NAME,
                ADOPT_BUILD_NUMBER        : ADOPT_BUILD_NUMBER,
                ENABLE_TESTS              : ENABLE_TESTS,
                ENABLE_INSTALLERS         : ENABLE_INSTALLERS,
                ENABLE_SIGNER             : ENABLE_SIGNER,
                CLEAN_WORKSPACE           : CLEAN_WORKSPACE,
                CLEAN_WORKSPACE_AFTER     : CLEAN_WORKSPACE_AFTER,
                CLEAN_WORKSPACE_BUILD_OUTPUT_ONLY_AFTER : CLEAN_WORKSPACE_BUILD_OUTPUT_ONLY_AFTER
        ]
    }

    String toJson() {
        return JsonOutput.prettyPrint(JsonOutput.toJson(toMap()))
    }

    IndividualBuildConfig fromJson(String json) {
        def map = new groovy.json.JsonSlurper().parseText(json) as Map
        return new IndividualBuildConfig(map)
    }

    List<?> toBuildParams() {
        List<?> buildParams = []

        buildParams.add(['$class': 'LabelParameterValue', name: 'NODE_LABEL', label: NODE_LABEL])
        buildParams.add(['$class': 'TextParameterValue', name: 'BUILD_CONFIGURATION', value: toJson()])

        return buildParams
    }
}
