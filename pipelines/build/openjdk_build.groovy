def unkeepAllBuildsOfType(buildName, build) {
    if (build != null) {
        if (build.displayName == buildName) {
            build.keepLog(false)
        }
        lastSuccessfullBuild(buildName, build.getPreviousBuild())
    }
}

def keepLastSuccessfulBuildOfType(buildName, build, found) {
    if (build != null) {
        if (displayName == buildName && build.result == 'SUCCESS') {
            if (found == false) {
                build.keepLog(true)
                found = true
            } else {
                build.keepLog(false)
            }
        }
        keepLastSuccessfulAllBuildsOfType(buildName, build.getPreviousBuild(), found)
    }
}

def setKeepFlagsForThisBuild(build, success) {
    build.keepLog(true)
    lastBuild = build.getPreviousBuild()
    if (success) {
        //build successful so allow all other builds to be removed if needed
        unkeepAllBuildsOfType(build.displayName, lastBuild)
    } else {
        //build unsuccessful so keep last success and this one
        keepLastSuccessfulBuildOfType(build.displayName, lastBuild, false)
    }
}

currentBuild.displayName = "${JAVA_TO_BUILD}-${ARCHITECTURE}-${VARIANT}"

def status = 1;
job('build-'+currentBuild.displayName) {
    try {
        steps {
            shell("${WORKSPACE}/build-farm/make-adopt-build-farm.sh")
        }
        publishers {
            archiveArtifacts("${WORKSPACE}/workspace/target/${configuration.os}/${configuration.arch}/${configuration.variant}/*")
        }
    } finally {
        // Enable this if we want to allow this script to run outside a sandbox
        setKeepFlagsForThisBuild(currentBuild, status == 0);

        if (status != 0) {
            currentBuild.result = 'FAILURE'
        }
    }
}

