package common

import java.util.regex.Matcher
import java.lang.IllegalArgumentException

class VersionInfo {
    Integer major // 8
    Integer minor // 0
    Integer security // 181
    Integer patch
    Integer build // 8
    String opt
    String version
    String pre
    Integer adopt_build_number
    String semver
    String msi_product_version

    private final context

    VersionInfo(def context) {
        this.context = context
    }

    VersionInfo parse(String PUBLISH_NAME, String ADOPT_BUILD_NUMBER) {
        context.println "[INFO] ATTEMPTING TO PARSE PUBLISH_NAME: $PUBLISH_NAME"

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
        msi_product_version = formMSIProductVersion() 

        // Lay this out exactly as it would be in the metadata
        context.println "[INFO] FINISHED PARSING PUBLISH_NAME:"
        context.println """
        {
            minor: ${minor},
            security: ${security},
            patch: ${patch},
            pre: ${pre},
            adopt_build_number: ${adopt_build_number},
            major: ${major},
            version: ${version},
            semver: ${semver},
            msi_product_version: ${msi_product_version},
            build: ${build},
            opt: ${opt}
        }
        """

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

    // Matches JDK8 "Nightly" format, or "Release" with pre
    private boolean matchAltPre223(versionString) {
        //<version><-milestone><-user-release-suffix(timestamp)><-build>
        //1.8.0_202-internal-201903130451-b08 (nightly, milestone = internal (defaulted))
        //1.8.0_272-ea-202010231715-b10 (nightly, milestone = ea)
        //1.8.0_272-ea-b10 (release, milestone = ea)
        final pre223regex = "(?<version>1\\.(?<major>[0-8])\\.0(_(?<update>[0-9]+))?(-(?<additional>.*))?)"
        context.println "[INFO] Attempting to match AltPre223 regex: ${pre223regex}"

        final matched = versionString =~ /${pre223regex}/

        if (matched.matches()) {
            context.println "[SUCCESS] matchAltPre223 regex matched!"
            major = or0(matched, 'major')
            minor = 0
            security = or0(matched, 'update')
            if (matched.group('additional') != null) {
                context.println "[INFO] Parsing additional group of matchAltPre223 regex..."
                String additional = matched.group('additional')
                
                additional.split("-").each { val ->
                    // Is it build: b<number>
                    def matcher = val =~ /b(?<build>[0-9]+)/
                    if (matcher.matches()) {
                        build = Integer.parseInt(matcher.group("build"))
                        context.println "[SUCCESS] matchAltPre223 regex group (build) matched to ${build}"
                    } else {
                        // Is it the user-release-suffix timestamp set as opt: <12 digits>
                        matcher = val =~ /^(?<opt>[0-9]{12})$/
                        if (matcher.matches()) {
                            opt = matcher.group("opt")
                            context.println "[SUCCESS] matchAltPre223 regex group (opt) matched to ${opt}"
                        } else {
                            // Is it milestone set as pre: <AlphaNumeric> 
                            matcher = val =~ /(?<pre>[a-zA-Z0-9]+)/
                            if (matcher.matches()) {
                                pre = matcher.group("pre")
                                context.println "[SUCCESS] matchAltPre223 regex group (pre) matched to ${pre}"
                            }
                        }
                    }
                }

            }
            version = matched.group('version')
            return true
        }

        context.println "[WARNING] Failed to match matchAltPre223 regex."
        return false
    }

    // Matches JDK8 "Release" version format with no-pre
    private boolean matchPre223(versionString) {
        //1.8.0_272-b10
        final pre223regex = "jdk\\-?(?<version>(?<major>[0-8]+)(u(?<update>[0-9]+))?(-b(?<build>[0-9]+))(_(?<opt>[-a-zA-Z0-9\\.]+))?)"
        context.println "[INFO] Attempting to match pre223 regex: ${pre223regex}"

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
            context.println "[WARNING] Failed to match pre223 regex."
            return matchAltPre223(versionString)
        }
    }

    // Match JDK9+
    private boolean match223(versionString) {
        // jdk9+ version string format:
        //   jdk-<major>[.<minor>][.<security>][.<patch>][-<pre>]+<build>[-<opt>]
        // eg.
        // jdk-15+36
        // jdk-11.0.9+11
        // jdk-11.0.9.1+1
        // jdk-11.0.9-ea+11
        // jdk-11.0.9+11-202011050024
        // jdk-11.0.9+11-adhoc.username-myfolder
        //
        //Regexes based on those in http://openjdk.java.net/jeps/223
        // Note, currently openjdk only uses the first regex format of 223
        // Technically the standard supports an arbitrary number of numbers, we will support 4 for now
        final vnumRegex = "(?<major>[0-9]+)(\\.(?<minor>[0-9]+))?(\\.(?<security>[0-9]+))?(\\.(?<patch>[0-9]+))?"
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

                if (matched223.group('patch') != null) {
                   patch = matched223.group('patch') as Integer
                    context.println "[SUCCESS] regex group (patch) of 223 regex matched to ${patch}"
                }

                try {
                    if (matched223.group('pre') != null) {
                        pre = matched223.group('pre')
                        context.println "[SUCCESS] regex group (pre) of last 223 regex matched to ${pre}"
                    }
                } catch(IllegalArgumentException e) {
                    // Ignore as 'pre' is not in the given regex
                }

                try {
                    build = or0(matched223, 'build')
                } catch(IllegalArgumentException e) {
                    // Ignore as 'build' is not in the given regex
                }

                if (matched223.group('opt') != null) {
                    opt = matched223.group('opt')
                    context.println "[SUCCESS] regex group (opt) of last 223 regex matched to ${opt}"
                }

                version = matched223.group('version')
                return true
            }
            context.println "[WARNING] Failed to match last 223 regex."
        }

        context.println "[WARNING] Failed to match 223 regex."

        return false
    }

    String formSemver() {
        if (major != null) {
            def semver = major + "." + minor + "." + security

            if (pre) {
                semver += "-" + pre
            }

            semver += "+"
            
            def sem_build = (build ?: 0)

            // if "patch" then increment semver build by patch x 100
            // semver only supports major.minor.security, so to support openjdk patch branches
            // we have to ensure the semver build is incremented by 100 (greater than expected number of builds per version)
            // to ensure semver version ordering
            if (patch != null && patch > 0) {
                sem_build += (patch * 100)
            }

            semver += sem_build

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
     * Form ProductVersion with only 4 number with dot , ie 11.0.9.0 or 11.0.9.101
     */
    String formMSIProductVersion() {
        if (major != null) {
            def productVersion = major + "." + minor + "." + security

            def msi_revision = (build ?: 0)

            // if "patch" then increment productVersion MSI revision by patch x 100
            // To ensure Win MSI product version order when openjdk do a patch branch
            // we have to ensure the productVersion MSI revision is incremented by 100 (greater than expected number of builds per version)
            if (patch != null && patch > 0) {
                msi_revision += (patch * 100)
            }

            productVersion += "." + msi_revision

            return productVersion
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
