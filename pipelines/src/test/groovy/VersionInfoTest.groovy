import common.VersionInfo
import org.junit.jupiter.api.Assertions
import org.junit.jupiter.api.Test

class VersionInfoTest {
    @Test
    void doesNotDefaultAdoptNumber() {
        VersionInfo parsed = new VersionInfo().parse(null, "11.0.2+10", null)
        Assertions.assertEquals(11, parsed.major)
        Assertions.assertEquals(0, parsed.minor)
        Assertions.assertEquals(2, parsed.security)
        Assertions.assertEquals(10, parsed.build)
        Assertions.assertNull(parsed.opt)
        Assertions.assertEquals("11.0.2+10", parsed.version)
        Assertions.assertNull(parsed.pre)
        Assertions.assertNull(parsed.adopt_build_number)
        Assertions.assertEquals("11.0.2+10", parsed.semver)
    }

    @Test
    void addsZeroAdoptBuildWhenThereIsAnOpt() {
        VersionInfo parsed = new VersionInfo().parse(null, "11.0.2+10-ea", null)
        Assertions.assertEquals(11, parsed.major)
        Assertions.assertEquals(0, parsed.minor)
        Assertions.assertEquals(2, parsed.security)
        Assertions.assertEquals(10, parsed.build)
        Assertions.assertEquals("ea", parsed.opt)
        Assertions.assertEquals("11.0.2+10-ea", parsed.version)
        Assertions.assertNull(parsed.pre)
        Assertions.assertEquals(0, parsed.adopt_build_number)
        Assertions.assertEquals("11.0.2+10.0.ea", parsed.semver)
    }

    @Test
    void addsAdoptBuildNum() {
        VersionInfo parsed = new VersionInfo().parse(null, "11.0.2+10", "2")
        Assertions.assertEquals(11, parsed.major)
        Assertions.assertEquals(0, parsed.minor)
        Assertions.assertEquals(2, parsed.security)
        Assertions.assertEquals(10, parsed.build)
        Assertions.assertNull(parsed.opt)
        Assertions.assertEquals("11.0.2+10", parsed.version)
        Assertions.assertNull(parsed.pre)
        Assertions.assertEquals(2, parsed.adopt_build_number)
        Assertions.assertEquals("11.0.2+10.2", parsed.semver)
    }

    def versionOut = """openjdk version "11.0.2" 2018-10-16
OpenJDK Runtime Environment AdoptOpenJDK (build 11.0.2+7)
OpenJDK 64-Bit Server VM AdoptOpenJDK (build 11.0.2+7, mixed mode)"""

    @Test
    void addsFullVersionOutput() {
        VersionInfo parsed = new VersionInfo().parse(versionOut, "11.0.2+7", null)
        Assertions.assertEquals(11, parsed.major)
        Assertions.assertEquals(0, parsed.minor)
        Assertions.assertEquals(2, parsed.security)
        Assertions.assertEquals(7, parsed.build)
        Assertions.assertEquals(versionOut, parsed.full_version_output)
        Assertions.assertNull(parsed.opt)
        Assertions.assertEquals("11.0.2+7", parsed.version)
        Assertions.assertNull(parsed.pre)
        Assertions.assertNull(parsed.adopt_build_number)
        Assertions.assertEquals("11.0.2+7", parsed.semver)
    }

    @Test
    void addsNullWhenNoFullVersionOutput() {
        VersionInfo parsed = new VersionInfo().parse(null, "11.0.2+7", null)
        Assertions.assertEquals(11, parsed.major)
        Assertions.assertEquals(0, parsed.minor)
        Assertions.assertEquals(2, parsed.security)
        Assertions.assertEquals(7, parsed.build)
        Assertions.assertNull(parsed.full_version_output)
        Assertions.assertNull(parsed.opt)
        Assertions.assertEquals("11.0.2+7", parsed.version)
        Assertions.assertNull(parsed.pre)
        Assertions.assertNull(parsed.adopt_build_number)
        Assertions.assertEquals("11.0.2+7", parsed.semver)
    }

}
