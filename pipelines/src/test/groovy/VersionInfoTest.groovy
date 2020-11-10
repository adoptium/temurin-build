import common.VersionInfo
import org.junit.jupiter.api.Assertions
import org.junit.jupiter.api.Test

class VersionInfoTest {
    @Test
    void doesNotDefaultAdoptNumber() {
        VersionInfo parsed = new VersionInfo(this).parse("11.0.2+10", null)
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
        VersionInfo parsed = new VersionInfo(this).parse("11.0.2+10-202010281332.username.dirname", null)
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
        VersionInfo parsed = new VersionInfo(this).parse("11.0.2-ea+10-202010281332.username.dirname", null)
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
        VersionInfo parsed = new VersionInfo(this).parse("1.8.0_272-ea-202010281332-b10", null)
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
        VersionInfo parsed = new VersionInfo(this).parse("11.0.2+10", null)
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
        VersionInfo parsed = new VersionInfo(this).parse("1.8.0_272-b10", null)
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
        VersionInfo parsed = new VersionInfo(this).parse("11.0.2-ea+10", null)
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
        VersionInfo parsed = new VersionInfo(this).parse("1.8.0_272-ea-b10", null)
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
        VersionInfo parsed = new VersionInfo(this).parse("11.0.2+10", "2")
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

    // jdk-15+36
    @Test
    void parsesJdk223Format1() {
        VersionInfo parsed = new VersionInfo(this).parse("15+36", null)
        Assertions.assertEquals(15, parsed.major)
        Assertions.assertEquals(0, parsed.minor)
        Assertions.assertEquals(0, parsed.security)
        Assertions.assertNull(parsed.patch)
        Assertions.assertEquals(36, parsed.build)
        Assertions.assertNull(parsed.pre)
        Assertions.assertEquals("15+36", parsed.version)
        Assertions.assertNull(parsed.opt)
        Assertions.assertNull(parsed.adopt_build_number)
        Assertions.assertEquals("15.0.0+36", parsed.semver)
    }

    // jdk-11.0.9+11
    @Test
    void parsesJdk223Format2() {
        VersionInfo parsed = new VersionInfo(this).parse("11.0.9+11", null)
        Assertions.assertEquals(11, parsed.major)
        Assertions.assertEquals(0, parsed.minor)
        Assertions.assertEquals(9, parsed.security)
        Assertions.assertNull(parsed.patch)
        Assertions.assertEquals(11, parsed.build)
        Assertions.assertNull(parsed.pre)
        Assertions.assertEquals("11.0.9+11", parsed.version)
        Assertions.assertNull(parsed.opt)
        Assertions.assertNull(parsed.adopt_build_number)
        Assertions.assertEquals("11.0.9+11", parsed.semver)
        Assertions.assertEquals("11.0.9.11", parsed.msi_product_version)
    }

    // jdk-11.0.9.1+1
    @Test
    void parsesJdk223Format3() {
        VersionInfo parsed = new VersionInfo(this).parse("11.0.9.1+1", null)
        Assertions.assertEquals(11, parsed.major)
        Assertions.assertEquals(0, parsed.minor)
        Assertions.assertEquals(9, parsed.security)
        Assertions.assertEquals(1, parsed.patch)
        Assertions.assertEquals(1, parsed.build)
        Assertions.assertNull(parsed.pre)
        Assertions.assertEquals("11.0.9.1+1", parsed.version)
        Assertions.assertNull(parsed.opt)
        Assertions.assertNull(parsed.adopt_build_number)
        Assertions.assertEquals("11.0.9+101", parsed.semver)
        Assertions.assertEquals("11.0.9.101", parsed.msi_product_version)
    }

    // jdk-11.0.9.1+1 AdoptBuildNumber "2"
    @Test
    void parsesJdk223Format3AdoptBuildNumber2() {
        VersionInfo parsed = new VersionInfo(this).parse("11.0.9.1+1", "2")
        Assertions.assertEquals(11, parsed.major)
        Assertions.assertEquals(0, parsed.minor)
        Assertions.assertEquals(9, parsed.security)
        Assertions.assertEquals(1, parsed.patch)
        Assertions.assertEquals(1, parsed.build)
        Assertions.assertNull(parsed.pre)
        Assertions.assertEquals("11.0.9.1+1", parsed.version)
        Assertions.assertNull(parsed.opt)
        Assertions.assertEquals(2, parsed.adopt_build_number)
        Assertions.assertEquals("11.0.9+101.2", parsed.semver)
        Assertions.assertEquals("11.0.9.101", parsed.msi_product_version)
    }

    // jdk-11.0.9-ea+11
    @Test
    void parsesJdk223Format4() {
        VersionInfo parsed = new VersionInfo(this).parse("11.0.9-ea+11", null)
        Assertions.assertEquals(11, parsed.major)
        Assertions.assertEquals(0, parsed.minor)
        Assertions.assertEquals(9, parsed.security)
        Assertions.assertNull(parsed.patch)
        Assertions.assertEquals(11, parsed.build)
        Assertions.assertEquals("ea", parsed.pre)
        Assertions.assertEquals("11.0.9-ea+11", parsed.version)
        Assertions.assertNull(parsed.opt)
        Assertions.assertNull(parsed.adopt_build_number)
        Assertions.assertEquals("11.0.9-ea+11", parsed.semver)
    }

    // jdk-11.0.9+11-202011050024
    @Test
    void parsesJdk223Format5() {
        VersionInfo parsed = new VersionInfo(this).parse("11.0.9+11-202011050024", null)
        Assertions.assertEquals(11, parsed.major)
        Assertions.assertEquals(0, parsed.minor)
        Assertions.assertEquals(9, parsed.security)
        Assertions.assertNull(parsed.patch)
        Assertions.assertEquals(11, parsed.build)
        Assertions.assertNull(parsed.pre)
        Assertions.assertEquals("11.0.9+11-202011050024", parsed.version)
        Assertions.assertEquals("202011050024", parsed.opt)
        Assertions.assertEquals(0, parsed.adopt_build_number)
        Assertions.assertEquals("11.0.9+11.0.202011050024", parsed.semver)
    }

    // jdk-11.0.9+11-adhoc.username-myfolder
    @Test
    void parsesJdk223Format6() {
        VersionInfo parsed = new VersionInfo(this).parse("11.0.9+11-adhoc.username-myfolder", null)
        Assertions.assertEquals(11, parsed.major)
        Assertions.assertEquals(0, parsed.minor)
        Assertions.assertEquals(9, parsed.security)
        Assertions.assertNull(parsed.patch)
        Assertions.assertEquals(11, parsed.build)
        Assertions.assertNull(parsed.pre)
        Assertions.assertEquals("11.0.9+11-adhoc.username-myfolder", parsed.version)
        Assertions.assertEquals("adhoc.username-myfolder", parsed.opt)
        Assertions.assertEquals(0, parsed.adopt_build_number)
        Assertions.assertEquals("11.0.9+11.0.adhoc.username-myfolder", parsed.semver)
    }
}
