package common

import java.util.regex.Matcher

class VersionInfo {
    Integer major // 8
    Integer minor // 0
    Integer security // 181
    Integer build // 8
    String opt
    String version
    String pre
    Integer adopt_build_number
    String semver

    VersionInfo() {
    }

    VersionInfo parse(String PUBLISH_NAME, String ADOPT_BUILD_NUMBER) {

        if (PUBLISH_NAME != null) {
            if (!matchPre223(PUBLISH_NAME)) {
                match223(PUBLISH_NAME)
            }
        }

        // ADOPT_BUILD_NUMBER is a string, so we also need to account for an empty string value
        if (ADOPT_BUILD_NUMBER != null && ADOPT_BUILD_NUMBER != "") {
            adopt_build_number = Integer.parseInt(ADOPT_BUILD_NUMBER)
        } else if (opt != null) {
            // if an opt is present then set adopt_build_number to pad out the semver
            adopt_build_number = 0
        }

        semver = formSemver()
        return this
    }

    private Integer or0(Matcher matched, String groupName) {
        def number = matched.group(groupName)
        if (number != null) {
            return number as Integer
        } else {
            return 0
        }
    }

    private boolean matchAltPre223(versionString) {
        //1.8.0_202-internal-201903130451-b08
        final pre223regex = "(?<version>1\\.(?<major>[0-8])\\.0(_(?<update>[0-9]+))?(-(?<additional>.*))?)"
        final matched = versionString =~ /${pre223regex}/

        if (matched.matches()) {
            major = or0(matched, 'major')
            minor = 0
            security = or0(matched, 'update')
            if (matched.group('additional') != null) {
                String additional = matched.group('additional')
                additional.split("-")
                        .each { val ->
                            def matcher = val =~ /b(?<build>[0-9]+)/
                            if (matcher.matches()) build = Integer.parseInt(matcher.group("build"));

                            matcher = val =~ /^(?<opt>[0-9]{12})$/
                            if (matcher.matches()) opt = matcher.group("opt");
                        }
            }
            version = matched.group('version')
            return true
        }

        return false
    }

    private boolean matchPre223(versionString) {
        final pre223regex = "jdk\\-?(?<version>(?<major>[0-8]+)(u(?<update>[0-9]+))?(-b(?<build>[0-9]+))(_(?<opt>[-a-zA-Z0-9\\.]+))?)"
        final matched = versionString =~ /${pre223regex}/

        if (matched.matches()) {
            major = or0(matched, 'major')
            minor = 0
            security = or0(matched, 'update')
            build = or0(matched, 'build')
            if (matched.group('opt') != null) opt = matched.group('opt')
            version = matched.group('version')
            return true
        } else {
            return matchAltPre223(versionString)
        }
    }

    private boolean match223(versionString) {
        //Regexes based on those in http://openjdk.java.net/jeps/223
        // Technically the standard supports an arbitrary number of numbers, we will support 3 for now
        final vnumRegex = "(?<major>[0-9]+)(\\.(?<minor>[0-9]+))?(\\.(?<security>[0-9]+))?"
        final preRegex = "(?<pre>[a-zA-Z0-9]+)"
        final buildRegex = "(?<build>[0-9]+)"
        final optRegex = "(?<opt>[-a-zA-Z0-9\\.]+)"

        List<String> version223Regexs = [
                "(?:jdk\\-)?(?<version>${vnumRegex}(\\-${preRegex})?\\+${buildRegex}(\\-${optRegex})?)".toString(),
                "(?:jdk\\-)?(?<version>${vnumRegex}\\-${preRegex}(\\-${optRegex})?)".toString(),
                "(?:jdk\\-)?(?<version>${vnumRegex}(\\+\\-${optRegex})?)".toString()
        ]

        for (String regex : version223Regexs) {
            final matched223 = versionString =~ /^${regex}.*/
            if (matched223.matches()) {
                major = or0(matched223, 'major')
                minor = or0(matched223, 'minor')
                security = or0(matched223, 'security')
                if (matched223.group('pre') != null) pre = matched223.group('pre')
                build = or0(matched223, 'build')
                if (matched223.group('opt') != null) opt = matched223.group('opt')
                version = matched223.group('version')
                return true
            }
        }

        return false
    }

    String formSemver() {
        if (major != null) {
            def semver = major + "." + minor + "." + security

            if (pre) {
                semver += "-" + pre
            }

            semver += "+"
            semver += (build ?: "0")

            if (adopt_build_number != null) {
                semver += "." + adopt_build_number
            }

            if (opt != null) {
                semver += "." + opt
            }
            return semver
        } else {
            return null
        }
    }

    /**
     * Form semver without build, adopt build number or timestamp.
     * This is the format dirs inside an adopt archive will look like, i.e 8.0.212
     * @return
     */
    String formOpenjdkSemver() {
        if (major != null) {
            def semver = major + "." + minor + "." + security

            if (pre != null) {
                semver += "-" + pre
            }
            return semver
        } else {
            return null
        }
    }
}
