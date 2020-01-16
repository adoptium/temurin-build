# AdoptOpenJDK Release Guide

Don't be scared off by this document! If you already understand the stuff in the glossary section and are only working on a HotSpot release, then skip to [Steps for every version](#steps-for-every-version) later on.

## Release glossary and background information

### OpenJDK "New" Release:

- The refers to "new" major OpenJDK release Short or Long Term Release (jdk13, jdk14, jdk15, ...)
- Oracle and contributors work on release in "head" openjdk stream: https://hg.openjdk.java.net/jdk/jdk
- 3 months prior to the GA date, the `head` stream if branched into the new release stream for development rampdown e.g. https://hg.openjdk.java.net/jdk/jdk14
- Regular builds are tagged every week or so in a format such as  `jdk-13+21`
- Eventually after rampdown and final phase testing, all done in the open, the GA build is tagged and released, `jdk-13-ga` tag is tagged along side the actual release build tag.


### OpenJDK Vulnerability Group

- A private group of trusted people who take reports of vulnerabilities in the openjdk codebase and work to resolve them and get them into releases in a timely manner

### Non-Oracle (usually RedHat) maintained OpenJDK Quarterly PSU Update

- Maintainers work on public quarterly update fixes for the next update, in the updates head stream e.g. https://hg.openjdk.java.net/jdk-updates/jdk11u
- Fixes for the subsequent update, are developed in the `dev` stream e.g. https://hg.openjdk.java.net/jdk-updates/jdk11u-dev/
- Regular builds are tagged every week or so, e.g. `jdk-11.0.5+6`
- Eventually after final testing it comes to GA day for the update, at this point any fixes from the Vulnerability Group are merged with the final GA build, and tagged, e.g. `jdk-11.0.5+10`, `jdk-11.0.5-ga`

### Oracle Managed OpenJDK Quarterly PSU Update

- For the most recent JDK release, updates are managed by Oracle, and there will only be two of them, e.g. `jdk-13.0.1` and `jdk-13.0.2` after the initial GA unless it is an LTS release
- Oracle work on the quarterly updates internally and their these branches are not public until GA date along with the Vulnerability Group fixes.
- On GA day, Oracle merges the internal branch and any Vulnerability Group fixes to produce the final GA build, and tagged, e.g. `jdk-13.0.1+9`, `jdk-13.0.1-ga`

### Eclipse OpenJ9/OMR releases

- The OpenJ9 releases are based on three codebases
  - https://github.com/eclipse/openj9-omr (a platform abstraction layer which OpenJ9 builds use, based on https://github.com/eclipse/omr)
  - https://github.com/eclipse/openj9 (The JVM code)
  - The "extensions" repository for each release (see the next section of the glossar for more details) which contains a modified version of the OpenJDK codebase (OpenJDK updates are merged by the IBM team who owns the extensions repository, not the AdoptOpenJDK project)
- Unlike the HotSpot versions, the Eclipse OpenJ9 and OMR projects do not have separate versions for each major java release, but the extensions repository does (Conditional compilation is used in OpenJ9 for any release differences). Each new OpenJ9 version goes into every JDK release.
- In the run up to a new JDK release or quarterly update the OpenJ9 and OMR `master` is branched to create a release branch named according to the OpenJ9 version for that release, e.g. `v0.17.0-release` (In general each quarterly update will have a new OpenJ9 version included)
- Before a new release there will typically be two milestone builds which get their own git tag from a commit in that branch e.g. `openj9-0.17.0-m1`
- This milestone tag is then pulled in by an openjdk "extensions" release branch to build an actual JDK binary.
- When it comes to a GA release day, the release branch will be built with the GA OpenJDK source from the extensions repository, and then tested. If this looks good a tag to indicate the GA level is created in the openj9 repository e.g. `openj9-0.17.0`. This tag is picked up by the openjdk extensions release branch to build the GA JDK binary. You can see the tags at https://github.com/eclipse/openj9/tags


### OpenJDK "extensions" repository for OpenJ9 releases

- The openjdk "extensions" repositories e.g. https://github.com/ibmruntimes/openj9-openjdk-jdk11 follows the same branching process as Eclipse OpenJ9 and OMR. When OpenJ9 creates the release branch for the first milestone, a corresponding release branch (based on the `openj9` branch, not `master`) is created, e.g. `openj9-0.17.0`.
- The "extensions" release branch is updated to pull in the correct OpenJ9 and OMR milestone "tags" to build with for each milestone build.
- In the run up to the JDK GA date, the extensions team's OpenJDK auto-merge and acceptance jobs merge any new jdk builds into the openj9-staging and openj9 branches, but NOT the openj9-0.nn.0 release branch.
- When it comes to the GA date, the auto-merged GA jdk "tag" needs to be merged into the openj9-0.nn.0 release branch by the extensions team.
- The release branch is also updated to pull in the GA Eclipse OpenJ9 & OMR release tags, and then the GA JDK binary is built.


# OpenJDK Quarterly/New Release Process

1. Wait for RedHat/Oracle to push the GA code to mercurial and announce availability:
   * jdk8u : https://hg.openjdk.java.net/jdk8u/jdk8u/jdk/
     * Announce: https://mail.openjdk.java.net/pipermail/jdk8u-dev/
   * jdk11+u:  https://hg.openjdk.java.net/jdk-updates/jdk11u/
     * Announce: https://mail.openjdk.java.net/pipermail/jdk-updates-dev/
   * jdkNN: https://hg.openjdk.java.net/jdk/jdkNN/
     * Announce: https://mail.openjdk.java.net/pipermail/jdk-dev/


# Extra OpenJ9 prerequisite steps (skip for a HotSpot release)

1. The extensions release branch (e.g. `openj9-0.17.0`) will exist from doing the milestone builds (OpenJ9 milestone process is covered in a later section)
2. Ask the extensions team to run their release-specific merge jobs to ensure they are up to date - this is not done by jobs at AdoptOpenJDK
3. Having merged to openj9-staging successfully, then a job hosted by the extensions team (not at AdoptOpenJDK) will have automatically been triggered, which will perform "sanity" testing on all platforms for the new `openj9-staging` branch and if successful testing will automatically promote the code to the "openj9" branch, acceptance jobs: https://ci.eclipse.org/openj9/
4. OpenJ9 leads (Currently [Peter Shipton](https://github.com/pshipton) and [Dan Heidinga](https://github.com/danheidinga)) will now verify the Eclipse OpenJ9 and OMR release branch against the newly merged openjdk GA level in openj9-staging. If they are happy they will tag their release branches with the release tag, eg. "openj9-0.17.0", you are then ready to build the release.
5. Get someone in the extensions team to make the following changes in the extensions release branch corresponding to the openj9 version for the release:
   - Merge into the openj9 extensions "release" branch (e.g. `openj9-0.17.0`) the latest tag merged from openjdk (automated jobs merge the tag into openj9-staging, but not the release branch so this has to be done manually). eg.:
     - git checkout openj9-0.18.0
     - git merge -m"Merge jdk-11.0.6+10" jdk-11.0.6+10
     - (Resolve any merge conflicts again if necessary)
     - Create a PullRequest and Merge (using a Merge Commit, do not Squash&Merge, otherwise we lose track of history)
   - Update closed/openjdk-tag.gmk with tag just merged. (This is used for the java - version) e.g.:
   ```
   OPENJDK_TAG:= jdk-11.0.6+10
   ```
   - Update closed/get_j9_sources.sh to pull in Eclipse OpenJ9 and OMR release tag, e.g. `openj9-0.18.0`
   - Update custom-spec.gmk.in in the appropriate branch with the correct `J9JDK_EXT_VERSION` for the release, e.g:
   - For jdk8:
   ```
   J9JDK_EXT_VERSION       := $(JDK_MINOR_VERSION).$(JDK_MICRO_VERSION).$(JDK_MOD_VERSION).$(JDK_FIX_VERSION)
   [Sample commit](https://github.com/ibmruntimes/openj9-openjdk-jdk8/commit/7eb1dfe231f40f94117c893adcb0a3e6da63b2a8#diff-828ea264e53560b6d0d572bc5be1693a)
   ```
   and update jdk/make/closed/autoconf/openj9ext-version-numbers with the correct MOD & FIX versions
   ```
   JDK_MOD_VERSION=232
   JDK_FIX_VERSION=0
   ```
   - For jdk11+ update custom-spec.gmk.in to set the following [Sample commit](https://github.com/ibmruntimes/openj9-openjdk-jdk11/commit/08085f7ff4d3720530b981a7b59ac19a46363e5a#diff-d6f51dbe595d728e2d1111f036170369)
   ```
     J9JDK_EXT_VERSION       := 11.0.5.0
     # J9JDK_EXT_VERSION       := HEAD   <==  !!! Comment out this line
   ```
6. Get permission to submit the release pipeline job from the Adopt TSC members, discussion is via the AdoptOpenJDK #release channel (https://adoptopenjdk.slack.com/messages/CLCFNV2JG).

# Steps for every version

Here are the steps:

1. Build and Test the OpenJDK for "release" at AdoptOpenJDK using a build pipeline job as follows:
   * Job: https://ci.adoptopenjdk.net/job/build-scripts/job/openjdk8-pipeline/build (Switch `openjdk8` for your version number)
   * `targetConfigurations`: remove all the entries for the variants you don't want to build (e.g. remove the openj9 ones for hotspot releases) or any platforms you don't want to release (Currently that would include OpenJ9 aarch64)
   * `releaseType: Release`
   * [OpenJ9 ONLY] `overridePublishName`: github binaries publish name (NOTE: If you are doing a point release, do NOT adjust this as we don't want the filenames to include the `.x` part), e.g. `jdk8u232-b09_openj9-0.14.0` or `jdk-11.0.5+10_openj9-0.14.0`
   * `adoptBuildNumber`: Leave blank unless you are doing a point release in which case it should be a number starting at `1` for the first point release.
   * [OpenJ9 only] `scmReference`: extensions release branch: e.g. `openj9-0.14.0`
   * `additionalConfigureArgs`: For JDK8 add `--with-milestone=fcs`, for later releases use `--without-version-pre --without-version-opt`
   * `scmReference`: One of the following:
     * For HotSpot JDK8, use the openjdk tag as-is e.g. `jdk8u232-b09`
     * For HotSpot JDK11+, it's the same tag suffixed with `_adopt` e.g. `jdk-13.0.1+9_adopt`
     * For OpenJ9 (all versions) use the OpenJ9 branch e.g. `openj9-0.15.1`
   * `enableTests`: tick
   * SUBMIT!!
2. Once the Build and Test pipeline has completed,
   [triage the results](https://github.com/AdoptOpenJDK/openjdk-tests/blob/master/doc/Triage.md)
   ([TRSS](https://trss.adoptopenjdk.net/tests/Test) will probably help!)
   * Find the milestone build row, and click the "Grid" link
   * Check all tests are "Green", and if not "hover" over the icon and follow the Jenkins link to triage the errors...
   * Raise issues either at:
     * [openjdk-build](https://github.com/adoptopenjdk/openjdk-build) or [openjdk-tests](https://github.com/AdoptOpenJDK/openjdk-tests) (for Adopt build or test issues)
     * [eclipse/openj9](https://github.com/eclipse/openj9) (for OpenJ9 issues)
3. Discuss failing tests with [Shelley Lambert](https://github.com/smlambert)
4. If "good to publish", then get permission to publish the release from the Adopt TSC members, discussion is via the AdoptOpenJDK [#release](https://adoptopenjdk.slack.com/messages/CLCFNV2JG) Slack channel and create a Promotion TSC item [here](https://github.com/AdoptOpenJDK/TSC/issues/new?assignees=&labels=&template=promote-release.md&title=Promote+AdoptOpenJDK+Version+%3Cx%3E).
5. Once permission has been obtained, run the [Adopt "Publish" job](https://ci.adoptopenjdk.net/job/build-scripts/job/release/job/refactor_openjdk_release_tool/) (restricted access - if you can't see this link, you don't have access)
   * `TAG`: (github binaries published name)  e.g. `jdk-11.0.5+9` or `jdk-11.0.5+9_openj9-0.nn.0` for OpenJ9 releases. If doing a point release, add that into the name e.g. for a `.3` release use something like these (NOTE that for OpenJ9 the point number goes before the openj9 version): `jdk8u232-b09.3` or `jdk-11.0.4+11.3_openj9-0.15.1`
   * `VERSION`: (select version)
   * `UPSTREAM_JOB_NAME`: (build-scripts/openjdkNN-pipeline)
   * `UPSTREAM_JOB_NUMBER`: (the job number of the build pipeline under build-scripts/openjdkNN-pipeline) eg.86
   * `RELEASE`: "ticked"
   * SUBMIT!!
6. Once the job completes successfully, check the binaries have uploaded to github at somewhere like https://github.com/AdoptOpenJDK/openjdk8-binaries/releases/jdk8u232-b09
7. Within 15 minutes the binaries should be available on the website too at e.g. https://adoptopenjdk.net/?variant=openjdk11&jvmVariant=openj9
8. Since you have 15 minutes free, use that time to update https://github.com/AdoptOpenJDK/openjdk-website/blob/master/src/handlebars/support.handlebars which is the source of  https://adoptopenjdk.net/support.html and (if required) the supported platforms table at https://github.com/AdoptOpenJDK/openjdk-website/blob/master/src/handlebars/supported_platforms.handlebars which is the source of https://adoptopenjdk.net/supported_platforms.html.
9. [Mac only] Once the binaries are available on the website you need to run the [homebrew-cask_updater](https://ci.adoptopenjdk.net/job/homebrew-cask_updater/) which will create a series of pull requests [here](https://github.com/AdoptOpenJDK/homebrew-openjdk/pulls). Normally George approves these but in principle as long as the CI passes, they should be good to approve. You don't need to wait around and merge the PR's because the Mergify bot will automatically do this for you as long as somebody has approved it.
10. Publicise the Adopt JDK release via slack on AdoptOpenJDK #release
11. If desired, find someone with the appropriate authority (George, Martijn, Shelley, Stewart) to post a tweet about the new release from the AdoptOpenJDK twitter account

# [OpenJ9 Only] Milestone Process

The following examples all use `-m1` as an example - this gets replaced with a later number for the second and subsequent milestones as required.

1. Eclipse OpenJ9 creates a new branch for their release branch: e.g. `v0.17.0-release`
2. Eclipse OpenJ9 tag the commit in the "release" branch that they want to be the milestone level as e.g. `openj9-0.17.0-m1`
3. OpenJDK extensions branches the `openj9` branch to create the release branch, called `openj9-0.nn.0`
4. Ask someone in the extensions team to make the following modifications:
   * Update [closed/get_j9_source.sh](https://github.com/ibmruntimes/openj9-openjdk-jdk11/blob/openj9/closed/get_j9_source.sh) (Link is for JDK11, chnage as appropriate!) to pull in Eclipse OpenJ9 & OMR milestone 1 tags e.g. `openj9-0.nn.0-m1`([Sample PR](https://github.com/ibmruntimes/openj9-openjdk-jdk11/commit/4607d33d99c566054261557fdf34bcbfaefc6480))
   * Update custom-spec.gmk.in with correct `J9JDK_EXT_VERSION` for the release, [Sample commit for 11](https://github.com/ibmruntimes/openj9-openjdk-jdk8/commit/8512fe26e568962d4ee08f82f2f59d3bb241bb9d) and [Sample commit for 11](https://github.com/ibmruntimes/openj9-openjdk-jdk11/commit/c7964e29fea19a7803a86bc991de0d0e45547dc8) e.g:
```
jdk11+ ==> J9JDK_EXT_VERSION       := 11.0.5.0-m1
jdk8     ==>  J9JDK_EXT_VERSION       := $(JDK_MINOR_VERSION).$(JDK_MICRO_VERSION).$(JDK_MOD_VERSION).$(JDK_FIX_VERSION)-m1
# J9JDK_EXT_VERSION       := HEAD   <==  !!! Comment out this line
JDK_MOD_VERSION=232
JDK_FIX_VERSION=0
```
5. Build and Test the OpenJDK for OpenJ9 "release" at AdoptOpenJDK using a build pipeline job as follows https://ci.adoptopenjdk.net/job/build-scripts/job/openjdkNN-pipeline/build?delay=0sec
   * `targetConfigurations`: remove all "hotspot" entries
   * `releaseType`: `Nightly`
   * `overridePublishName`: github binaries publish name, e.g. `jdk8u232-b09_openj9-0.17.0-m1` or `jdk-11.0.5+10_openj9-0.17.0-m1`
   * `scmReference`: extensions release branch: e.g. `openj9-0.17.0`
   * `additionalConfigureArgs`: JDK8: `--with-milestone=fcs`, JDK11+: `--without-version-pre --without-version-opt`
   * `enableTests`: "ticked"
   * SUBMIT!!
6. Triage the results and publish as required with using the publish name from `overridePublishName` in the previous step but with `RELEASE` UNCHECKED as this is not a full release build.

## Summary on point releases

Occasionally we may have to do an out-of-band release that does not align with a quarterly release from the upstream openjdk project. This may occur if there has been a problem with our build process that we missed at GA time, to fix a critical issue, or when a project outside openjdk (e.g. OpenJ9) need to do an interim release. In order to do such a release, follow the steps included in the process above which I'll repeat here for clarity:

1. When triggering the pipeline, set `AdoptBuildNumber` to a unique number for the point release
2. If you used a custom entry in `overridePublishName` when kicking off the GA pipeline, keep it the same as for the GA release - we DO NOT want the filenames changed to include the point number
3. When running the publish job, you need to use a custom `TAG` in order to publish it to the website with a separate name from what you had initially e.g.  `jdk-11.0.5+10.1_openj9-0.17.1` (Note the position of the `.1` for OpenJ9 releases in that example - it's after the openj9 version but before the OpenJ9 version.
