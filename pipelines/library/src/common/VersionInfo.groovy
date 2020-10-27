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

    def context

    VersionInfo() {
    }

    VersionInfo parse(def outputStream, String PUBLISH_NAME, String ADOPT_BUILD_NUMBER) {
        context = outputStream

        context.println "[INFO] ATTEMPTING TO PARSE PUBLISH_NAME: $PUBLISH_NAME"

        if (PUBLISH_NAME != null) {
            if (!matchPre223(PUBLISH_NAME)) {
                context.println "[WARNING] Failed to match matchAltPre223 regex! Attempting to match223 regex..."
                match223(PUBLISH_NAME)
            }
        }

        context.println "[INFO] FINISHED PARSING PUBLISH_NAME:"
        context.println "major = ${major}"
        context.println "minor = ${minor}"
        context.println "security = ${security}"
        context.println "build = ${build}"
        context.println "opt = ${opt}"
        context.println "version = ${version}"
        context.println "pre = ${pre}"

        // ADOPT_BUILD_NUMBER is a string, so we also need to account for an empty string value
        if (ADOPT_BUILD_NUMBER != null && ADOPT_BUILD_NUMBER != "") {
            adopt_build_number = Integer.parseInt(ADOPT_BUILD_NUMBER)
        } else if (opt != null) {
            // if an opt is present then set adopt_build_number to pad out the semver
            adopt_build_number = 0
        }
        context.println "adopt build number = ${adopt_build_number}"

        semver = formSemver()
        context.println "semver = ${semver}"

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
            context.println "[SUCCESS] matchAltPre223 regex matched!"
            major = or0(matched, 'major')
            minor = 0
            security = or0(matched, 'update')
            if (matched.group('additional') != null) {
                context.println "[INFO] Parsing additional group of matchAltPre223 regex..."
                String additional = matched.group('additional')
                additional.split("-")
                        .each { val ->
                            def matcher = val =~ /b(?<build>[0-9]+)/
                            if (matcher.matches()) {
                                build = Integer.parseInt(matcher.group("build"))
                                context.println "[SUCCESS] matchAltPre223 regex group (build) matched to ${build}"
                            }

                            matcher = val =~ /^(?<opt>[0-9]{12})$/

                            if (matcher.matches()) {
                                opt = matcher.group("opt")
                                context.println "[SUCCESS] matchAltPre223 regex group (opt) matched to ${opt}"
                            }
                        }
            }
            version = matched.group('version')
            return true
        }

        return false
    }

    private boolean matchPre223(versionString) {
        context.println "[INFO] Attempting to match pre223 regex..."

        final pre223regex = "jdk\\-?(?<version>(?<major>[0-8]+)(u(?<update>[0-9]+))?(-b(?<build>[0-9]+))(_(?<opt>[-a-zA-Z0-9\\.]+))?)"
        final matched = versionString =~ /${pre223regex}/

        if (matched.matches()) {
            context.println "[SUCCESS] pre223 regex matched!"
            major = or0(matched, 'major')
            minor = 0
            security = or0(matched, 'update')
            build = or0(matched, 'build')

            if (matched.group('opt') != null) {
                opt = matched.group('opt')
                context.println "[SUCCESS] pre223 regex group (opt) matched to ${opt}"
            }

            version = matched.group('version')
            return true
        } else {
            context.println "[WARNING] Failed to match pre223 regex! Attempting to matchAltPre223 regex..."
            return matchAltPre223(versionString)
        }
    }

    private boolean match223(versionString) {
        context.println "[INFO] Attempting to match223 regex..."

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
            context.println "[INFO] Attempting to match223 regex: ${regex}"
            final matched223 = versionString =~ /^${regex}.*/
            if (matched223.matches()) {
                context.println "[SUCCESS] match223 regex matched!"

                major = or0(matched223, 'major')
                minor = or0(matched223, 'minor')
                security = or0(matched223, 'security')

                if (matched223.group('pre') != null) {
                    pre = matched223.group('pre')
                    context.println "[SUCCESS] regex group (pre) of last 223 regex matched to ${pre}"
                } else {
                    // Unique case for builds with ea in the version string (i.e. 1.8.0_272-ea-b10)
                    // See https://github.com/AdoptOpenJDK/openjdk-build/issues/2172
                    if (versionString.contains("ea")) {
                        String eaString = "ea"
                        pre = eaString
                        context.println "[SUCCESS] Version string contains ea. Setting pre to ${eaString}"
                    }
                }

                build = or0(matched223, 'build')

                if (matched223.group('opt') != null) {
                    opt = matched223.group('opt')
                    context.println "[SUCCESS] regex group (opt) of last 223 regex matched to ${opt}"
                }

                version = matched223.group('version')
                return true
            }
            context.println "[WARNING] FAILED to match last 223 regex"
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
