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
                build.getRawBuild().keepLog(true)
                found = true
            } else {
                build.getRawBuild().keepLog(false)
            }
        }
        keepLastSuccessfulAllBuildsOfType(buildName, build.getPreviousBuild(), found)
    }
}

def setKeepFlagsForThisBuild(build, success) {
    build.getRawBuild().keepLog(true)
    lastBuild = build.getPreviousBuild()
    if (success) {
        //build successful so allow all other builds to be removed if needed
        unkeepAllBuildsOfType(build.displayName, lastBuild)
    } else {
        //build unsuccessful so keep last success and this one
        keepLastSuccessfulBuildOfType(build.displayName, lastBuild, false)
    }
}

currentBuild.displayName = "${JAVA_TO_BUILD}-${TARGET_OS}-${ARCHITECTURE}-${VARIANT}"
node(NODE_LABEL) {
    checkout scm
    currentBuild.getRawBuild().keepLog(true)

    success = false;
    try {
        sh "./build-farm/make-adopt-build-farm.sh"
        archiveArtifacts artifacts: "workspace/target/*"
        success = true
    } catch (Exception e) {
        success = false
        currentBuild.result = 'FAILURE'
    } finally {
        setKeepFlagsForThisBuild(currentBuild, success);
    }
}

