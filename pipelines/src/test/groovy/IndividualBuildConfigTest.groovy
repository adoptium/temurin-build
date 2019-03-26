import common.IndividualBuildConfig
import org.junit.jupiter.api.Assertions
import org.junit.jupiter.api.Test

class IndividualBuildConfigTest {

    @Test
    void serializationTransfersDataCorrectly() {
        def config = new IndividualBuildConfig()

        config.ARCHITECTURE = "a"
        config.TARGET_OS = "b"
        config.VARIANT = "c"
        config.JAVA_TO_BUILD = "d"
        config.TEST_LIST = "e"
        config.SCM_REF = "f"
        config.BUILD_ARGS = "g"
        config.NODE_LABEL = "h"
        config.CONFIGURE_ARGS = "i"
        config.OVERRIDE_FILE_NAME_VERSION = "j"
        config.ADDITIONAL_FILE_NAME_TAG = "k"
        config.JDK_BOOT_VERSION = "l"
        config.RELEASE = false
        config.PUBLISH_NAME = "m"
        config.ADOPT_BUILD_NUMBER = "n"
        config.ENABLE_TESTS = true
        config.CLEAN_WORKSPACE = false

        def json = config.toJson()
        def parsedConfig = new IndividualBuildConfig().fromJson(json);

        parsedConfig.toRawMap()
                .each { val ->
            Assertions.assertNotNull(val.value, "${val.key} is null")
        }

        Assertions.assertEquals(config.toJson(), parsedConfig.toJson())
    }

}
