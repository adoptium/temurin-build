import common.IndividualBuildConfig
import org.junit.jupiter.api.Assertions
import org.junit.jupiter.api.Test
import testDoubles.ContextStub
import testDoubles.CurrentBuildStub
import testDoubles.EnvStub

class VersionParsingTest {

    def java8 = """openjdk version "1.8.0_202"
OpenJDK Runtime Environment (AdoptOpenJDK)(build 1.8.0_202-b08)
OpenJDK 64-Bit Server VM (AdoptOpenJDK)(build 25.202-b08, mixed mode)"""

    def java8Nightly = """openjdk version "1.8.0_202-internal"
OpenJDK Runtime Environment (AdoptOpenJDK)(build 1.8.0_202-internal-201903130451-b08)
OpenJDK 64-Bit Server VM (AdoptOpenJDK)(build 25.202-b08, mixed mode)"""

    def java11 = """"openjdk version "11.0.2" 2018-10-16
OpenJDK Runtime Environment AdoptOpenJDK (build 11.0.2+7)
OpenJDK 64-Bit Server VM AdoptOpenJDK (build 11.0.2+7, mixed mode)"""

    def java11Nightly = """openjdk version "11.0.3" 2019-04-16
OpenJDK Runtime Environment AdoptOpenJDK (build 11.0.3+9-201903122221)
OpenJDK 64-Bit Server VM AdoptOpenJDK (build 11.0.3+9-201903122221, mixed mode)"""

    def parse(String version) {
        IndividualBuildConfig config = new IndividualBuildConfig([ADOPT_BUILD_NUMBER: 23]);
        def build = new Build(config, new ContextStub(), new EnvStub(), new CurrentBuildStub())
        return build.parseVersionOutput("=JAVA VERSION OUTPUT=\n" + version + "\n=/JAVA VERSION OUTPUT=")
    }

    @Test
    void parsesJava8String() {
        def parsed = parse(java8);
        Assertions.assertEquals(8, parsed.major)
        Assertions.assertEquals(202, parsed.security)
        Assertions.assertEquals(8, parsed.build)
        Assertions.assertEquals("8.0.202+8.23", parsed.semver)
    }

    @Test
    void parsesJava8NightlyString() {
        def parsed = parse(java8Nightly);
        Assertions.assertEquals(8, parsed.major)
        Assertions.assertEquals(202, parsed.security)
        Assertions.assertEquals(8, parsed.build)
        Assertions.assertEquals("201903130451", parsed.opt)
        Assertions.assertEquals("8.0.202-internal+8.23.201903130451", parsed.semver)
    }

    @Test
    void parsesJava11String() {
        def parsed = parse(java11);
        Assertions.assertEquals(11, parsed.major)
        Assertions.assertEquals(2, parsed.security)
        Assertions.assertEquals(7, parsed.build)
        Assertions.assertEquals("11.0.2+7.23", parsed.semver)
    }

    @Test
    void parsesJava11NightlyString() {
        def parsed = parse(java11Nightly);
        Assertions.assertEquals(11, parsed.major)
        Assertions.assertEquals(3, parsed.security)
        Assertions.assertEquals(9, parsed.build)
        Assertions.assertEquals("201903122221", parsed.opt)
        Assertions.assertEquals("11.0.3+9.23.201903122221", parsed.semver)
    }

}
