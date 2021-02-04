import common.IndividualBuildConfig
import groovy.json.JsonOutput
import org.junit.jupiter.api.Assertions
import org.junit.jupiter.api.Test

class IndividualBuildConfigTest {

    @Test
    void serializationTransfersDataCorrectly() {
        def config = new IndividualBuildConfig([
                ARCHITECTURE               : "a",
                TARGET_OS                  : "b",
                VARIANT                    : "c",
                JAVA_TO_BUILD              : "d",
                TEST_LIST                  : "e",
                SCM_REF                    : "f",
                BUILD_ARGS                 : "g",
                NODE_LABEL                 : "h",
                ADDITIONAL_TEST_LABEL      : "t",
                KEEP_TEST_REPORTDIR        : false,
                ACTIVE_NODE_TIMEOUT        : "r",
                CODEBUILD                  : false,
                DOCKER_IMAGE               : "o",
                DOCKER_FILE                : "p",
                DOCKER_NODE                : "q",
                PLATFORM_CONFIG_LOCATION   : "r",
                CONFIGURE_ARGS             : "i",
                OVERRIDE_FILE_NAME_VERSION : "j",
                USE_ADOPT_SHELL_SCRIPTS    : true,
                ADDITIONAL_FILE_NAME_TAG   : "k",
                JDK_BOOT_VERSION           : "l",
                RELEASE                    : false,
                PUBLISH_NAME               : "m",
                ADOPT_BUILD_NUMBER         : "n",
                ENABLE_TESTS               : true,
                ENABLE_INSTALLERS          : true,
                ENABLE_SIGNER              : true,
                CLEAN_WORKSPACE            : false,
                CLEAN_WORKSPACE_AFTER      : false,
                CLEAN_WORKSPACE_BUILD_OUTPUT_ONLY_AFTER : false
        ])

        def json = config.toJson()
        def parsedConfig = new IndividualBuildConfig(json)

        parsedConfig.toRawMap()
                .each { val ->
            Assertions.assertNotNull(val.value, "${val.key} is null")
        }

        Assertions.assertEquals(JsonOutput.toJson(config), JsonOutput.toJson(parsedConfig))
    }

}
