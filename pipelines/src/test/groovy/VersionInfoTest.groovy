import common.VersionInfo
import org.junit.jupiter.api.Assertions
import org.junit.jupiter.api.Test

class VersionInfoTest {
    @Test
    void doesNotDefaultAdoptNumber() {
        VersionInfo parsed = new VersionInfo().parse("11.0.2+10", null)
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
        VersionInfo parsed = new VersionInfo().parse("11.0.2+10-202010281332.username.dirname", null)
        Assertions.assertEquals(11, parsed.major)
        Assertions.assertEquals(0, parsed.minor)
        Assertions.assertEquals(2, parsed.security)
        Assertions.assertEquals(10, parsed.build)
        Assertions.assertEquals("202010281332.username.dirname", parsed.opt)
        Assertions.assertEquals("11.0.2+10-202010281332.username.dirname", parsed.version)
        Assertions.assertNull(parsed.pre)
        Assertions.assertEquals(0, parsed.adopt_build_number)
        Assertions.assertEquals("11.0.2+10.0.202010281332.username.dirname", parsed.semver)
    }

    @Test
    void parsesJdk11NightlyPreAndOpt() {
        VersionInfo parsed = new VersionInfo().parse("11.0.2-ea+10-202010281332.username.dirname", null)
        Assertions.assertEquals(11, parsed.major)
        Assertions.assertEquals(0, parsed.minor)
        Assertions.assertEquals(2, parsed.security)
        Assertions.assertEquals(10, parsed.build)
        Assertions.assertEquals("ea", parsed.pre)
        Assertions.assertEquals("11.0.2-ea+10-202010281332.username.dirname", parsed.version)
        Assertions.assertEquals("202010281332.username.dirname", parsed.opt)
        Assertions.assertEquals(0, parsed.adopt_build_number)
        Assertions.assertEquals("11.0.2-ea+10.0.202010281332.username.dirname", parsed.semver)
    }

    @Test
    void parsesJdk8NightlyPreAndOpt() {
        VersionInfo parsed = new VersionInfo().parse("1.8.0_272-ea-202010281332-b10", null)
        Assertions.assertEquals(8, parsed.major)
        Assertions.assertEquals(0, parsed.minor)
        Assertions.assertEquals(272, parsed.security)
        Assertions.assertEquals(10, parsed.build)
        Assertions.assertEquals("ea", parsed.pre)
        Assertions.assertEquals("1.8.0_272-ea-202010281332-b10", parsed.version)
        Assertions.assertEquals("202010281332", parsed.opt)
        Assertions.assertEquals(0, parsed.adopt_build_number)
        Assertions.assertEquals("8.0.272-ea+10.0.202010281332", parsed.semver)
    }

    @Test
    void parsesJdk11Release() {
        VersionInfo parsed = new VersionInfo().parse("11.0.2+10", null)
        Assertions.assertEquals(11, parsed.major)
        Assertions.assertEquals(0, parsed.minor)
        Assertions.assertEquals(2, parsed.security)
        Assertions.assertEquals(10, parsed.build)
        Assertions.assertNull(parsed.pre)
        Assertions.assertEquals("11.0.2+10", parsed.version)
        Assertions.assertNull(parsed.opt)
        Assertions.assertNull(parsed.adopt_build_number)
        Assertions.assertEquals("11.0.2+10", parsed.semver)
    }

    @Test
    void parsesJdk8Release() {
        VersionInfo parsed = new VersionInfo().parse("1.8.0_272-b10", null)
        Assertions.assertEquals(8, parsed.major)
        Assertions.assertEquals(0, parsed.minor)
        Assertions.assertEquals(272, parsed.security)
        Assertions.assertEquals(10, parsed.build)
        Assertions.assertNull(parsed.pre)
        Assertions.assertEquals("1.8.0_272-b10", parsed.version)
        Assertions.assertNull(parsed.opt)
        Assertions.assertNull(parsed.adopt_build_number)
        Assertions.assertEquals("8.0.272+10", parsed.semver)
    }

    @Test
    void parsesJdk11ReleaseWithEA() {
        VersionInfo parsed = new VersionInfo().parse("11.0.2-ea+10", null)
        Assertions.assertEquals(11, parsed.major)
        Assertions.assertEquals(0, parsed.minor)
        Assertions.assertEquals(2, parsed.security)
        Assertions.assertEquals(10, parsed.build)
        Assertions.assertEquals("ea", parsed.pre)
        Assertions.assertEquals("11.0.2-ea+10", parsed.version)
        Assertions.assertNull(parsed.opt)
        Assertions.assertNull(parsed.adopt_build_number)
        Assertions.assertEquals("11.0.2-ea+10", parsed.semver)
    }

    @Test
    void parsesJdk8ReleaseWithEA() {
        VersionInfo parsed = new VersionInfo().parse("1.8.0_272-ea-b10", null)
        Assertions.assertEquals(8, parsed.major)
        Assertions.assertEquals(0, parsed.minor)
        Assertions.assertEquals(272, parsed.security)
        Assertions.assertEquals(10, parsed.build)
        Assertions.assertEquals("ea", parsed.pre)
        Assertions.assertEquals("1.8.0_272-ea-b10", parsed.version)
        Assertions.assertNull(parsed.opt)
        Assertions.assertNull(parsed.adopt_build_number)
        Assertions.assertEquals("8.0.272-ea+10", parsed.semver)
    }

    @Test
    void addsAdoptBuildNum() {
        VersionInfo parsed = new VersionInfo().parse("11.0.2+10", "2")
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
