def filter = ""
if (OPERATING_SYSTEM == "mac") {
    filter = '**/*.tar.gz'
} else if (OPERATING_SYSTEM == "windows") {
    filter = '**/*.zip'
}

steps {
    copyArtifacts("${UPSTREAM_JOB_NAME}") {
        includePatterns(filter)
        buildSelector {
            specific {
                buildNumber("${UPSTREAM_JOB_NUMBER}")
            }
        }
    }

    shell(readFileFromWorkspace('build-farm/sign-releases.sh'))
}