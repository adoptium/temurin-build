import common.VersionInfo
import org.junit.jupiter.api.Assertions
import org.junit.jupiter.api.Test

class VersionInfoTest {
    @Test
    void doesNotDefaultAdoptNumber() {
        VersionInfo parsed = new VersionInfo().parse(this, "11.0.2+10", null)
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
        VersionInfo parsed = new VersionInfo().parse(this, "11.0.8-ea+10", null)
        Assertions.assertEquals(11, parsed.major)
        Assertions.assertEquals(0, parsed.minor)
        Assertions.assertEquals(8, parsed.security)
        Assertions.assertEquals(10, parsed.build)
        Assertions.assertNull(parsed.opt)
        Assertions.assertEquals("11.0.8-ea+10", parsed.version)
        Assertions.assertEquals("ea", parsed.pre)
        Assertions.assertEquals(0, parsed.adopt_build_number)
        Assertions.assertEquals("11.0.8-ea+10", parsed.semver)
    }

    @Test
    void addsAdoptBuildNum() {
        VersionInfo parsed = new VersionInfo().parse(this, "11.0.2+10", "2")
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

}
