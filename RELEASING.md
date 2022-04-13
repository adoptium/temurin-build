# Temurin Release Guide

Don't be scared off by this document! If you already understand the stuff in the glossary section and are only working on a HotSpot release, then skip to [Steps for every version](#steps-for-every-version) later on.

## Release glossary and background information

### OpenJDK Vulnerability Group

- A private group of trusted people who take reports of vulnerabilities in the openjdk codebase and work to resolve them and get them into releases in a timely manner

### Non-Oracle (usually Red Hat) maintained OpenJDK Quarterly Patch Set Update (PSU)

- Maintainers work on quarterly update fixes for the next update, in the head stream of the updates repository e.g. https://hg.openjdk.java.net/jdk-updates/jdk11u
- Fixes for the subsequent update are developed in the `dev` stream e.g. https://hg.openjdk.java.net/jdk-updates/jdk11u-dev/
- Regular builds are tagged every week or so, e.g. `jdk-11.0.5+6`
- Eventually after final testing it comes to general availability (GA) day for the update, at this point any fixes from the Vulnerability Group are merged with the final GA build, and tagged, e.g. `jdk-11.0.5+10`, `jdk-11.0.5-ga`

### Oracle Managed OpenJDK Quarterly PSU

- The most recent JDK release updates are managed by Oracle, and there will only be two of them, e.g. for `jdk-13` Oracle produced `jdk-13.0.1` and `jdk-13.0.2`.  
- Oracle work on the quarterly updates internally and these update source branches and Vulnerability Group fixes are not public until GA date.
- On GA day, Oracle merges the internal branch and Vulnerability Group fixes to produce the final GA build, and this is tagged, e.g. `jdk-13.0.1+9`, `jdk-13.0.1-ga`
- If the release is a short term support release there are no more releases after the two Oracle-led updates, but if it is a long term support (LTS) release the OpenJDK community picks up subsequent release maintenance, and all work continues in public as described above.

### Eclipse OpenJ9/OMR releases

- The OpenJ9 releases are based on three codebases
  - https://github.com/eclipse-openj9/openj9-omr (a platform abstraction layer which OpenJ9 builds use, based on https://github.com/eclipse/omr)
  - https://github.com/eclipse-openj9/openj9 (The JVM code)
  - The "extensions" repository for each release (see the next section of the glossary for more details) which contains a modified version of the OpenJDK codebase (OpenJDK updates are merged by the IBM team who owns the extensions repository, not the Adoptium project)
- Unlike the HotSpot versions, the Eclipse OpenJ9 and OMR projects do not have separate versions for each major OpenJDK release, but the extensions repository does (conditional compilation is used in OpenJ9 for any release differences). Each new OpenJ9 version goes into every JDK release.
- In the run up to a new JDK release or quarterly update the OpenJ9 and OMR `master` is branched to create a release branch named according to the OpenJ9 version for that release, e.g. `v0.17.0-release`.  In general each quarterly update will have a new OpenJ9 version included.
- Before a new release there will typically be two milestone builds which get their own Git tag from a commit in that branch e.g. `openj9-0.17.0-m1`
- This milestone tag is then pulled in by an OpenJDK "extensions" release branch to build an actual JDK binary.
- When it comes to a GA release day, the release branch will be built with the GA OpenJDK source from the extensions repository, and then tested. If this looks good a tag to indicate the GA level is created in the OpenJ9 repository e.g. `openj9-0.17.0`. This tag is picked up by the OpenJDK extensions release branch to build the GA JDK binary. You can see the tags at https://github.com/eclipse-openj9/openj9/tags

### OpenJDK "extensions" repository for OpenJ9 releases

- The openjdk "extensions" repositories e.g. https://github.com/ibmruntimes/openj9-openjdk-jdk11 follows the same branching process as Eclipse OpenJ9 and OMR. When OpenJ9 creates the release branch for the first milestone, a corresponding release branch (based on the `openj9` branch, not `master`) is created, e.g. `openj9-0.17.0`.
- The "extensions" release branch is updated to pull in the correct OpenJ9 and OMR milestone "tags" to build with for each milestone build.
- In the run up to the JDK GA date, the extensions team's OpenJDK auto-merge and acceptance jobs merge any new jdk builds into the `openj9-staging` and `openj9` branches, but NOT the `openj9-0.nn.0` release branch.
- When it comes to the GA date, the auto-merged GA jdk "tag" needs to be merged into the `openj9-0.nn.0` release branch by the extensions team.
- The release branch is also updated to pull in the GA Eclipse OpenJ9 & OMR release tags, and then the GA JDK binary is built.

## OpenJDK Quarterly/New Release Process

1. Wait for Red Hat/Oracle to push the GA code to mercurial and announce availability:
   - jdk8u : https://hg.openjdk.java.net/jdk8u/jdk8u/jdk/
     - Announce: https://mail.openjdk.java.net/pipermail/jdk8u-dev/
   - jdk11u:  https://hg.openjdk.java.net/jdk-updates/jdk11u/
     - Announce: https://mail.openjdk.java.net/pipermail/jdk-updates-dev/
   - jdkNN: https://hg.openjdk.java.net/jdk/jdkNN/
     - Announce: https://mail.openjdk.java.net/pipermail/jdk-dev/

## Extra OpenJ9 prerequisite steps (skip for a HotSpot release)

1. The extensions release branch (e.g. `openj9-0.17.0`) will exist from doing the milestone builds (OpenJ9 milestone process is covered in a later section).
2. Ask the extensions team to run their release-specific merge jobs to ensure they are up to date - this is not done by jobs at Adoptium.
3. Having merged to `openj9-staging` successfully then a job hosted by the extensions team (not at Adoptium) will have automatically been triggered, which will perform "sanity" testing on all platforms for the new `openj9-staging` branch and, if successful, testing will automatically promote the code to the "openj9" branch, acceptance jobs: https://ci.eclipse.org/openj9/
4. OpenJ9 leads (currently [Peter Shipton](https://github.com/pshipton) and [Dan Heidinga](https://github.com/danheidinga)) will now verify the Eclipse OpenJ9 and OMR release branch against the newly merged OpenJDK GA level in `openj9-staging`. If they are happy they will tag their release branches with the release tag, eg. `openj9-0.17.0`, you are then ready to build the release.
5. Get someone in the extensions team to make the following changes in the extensions release branch corresponding to the OpenJ9 version for the release:
   - Merge into the OpenJ9 extensions release branch (e.g. `openj9-0.17.0`) the latest tag merged from OpenJDK (automated jobs merge the tag into `openj9-staging`, but not the release branch so this has to be done manually). eg.:
     - `git checkout openj9-0.18.0`
     - `git merge -m"Merge jdk-11.0.6+10" jdk-11.0.6+10`
     - Resolve any merge conflicts again if necessary.
     - Create a Pull Request and Merge (using a Merge Commit, do not Squash&Merge, otherwise we lose track of history).
   - Update closed/openjdk-tag.gmk with tag just merged. (This is used for the java - version) e.g.:

   ```bash
   OPENJDK_TAG:= jdk-11.0.6+10
   ```

   - Update closed/get_j9_source.sh to pull in Eclipse OpenJ9 and OMR release tag, e.g. `openj9-0.18.0`
   - Update custom-spec.gmk.in in the appropriate branch with the correct `J9JDK_EXT_VERSION` for the release, e.g:
   - For jdk8:

   ```bash
   J9JDK_EXT_VERSION       := $(JDK_MINOR_VERSION).$(JDK_MICRO_VERSION).$(JDK_MOD_VERSION).$(JDK_FIX_VERSION)
   ```
  
   [Sample commit](https://github.com/ibmruntimes/openj9-openjdk-jdk8/commit/7eb1dfe231f40f94117c893adcb0a3e6da63b2a8#diff-828ea264e53560b6d0d572bc5be1693a)

   and update jdk/make/closed/autoconf/openj9ext-version-numbers with the correct MOD & FIX versions
  
   ```bash
   JDK_MOD_VERSION=232
   JDK_FIX_VERSION=0
   ```
  
   - For jdk11+ update custom-spec.gmk.in to set the following [Sample commit](https://github.com/ibmruntimes/openj9-openjdk-jdk11/commit/08085f7ff4d3720530b981a7b59ac19a46363e5a#diff-d6f51dbe595d728e2d1111f036170369)

   ```bash
     J9JDK_EXT_VERSION       := 11.0.5.0
     # J9JDK_EXT_VERSION       := HEAD   <==  !!! Comment out this line
   ```
  
6. Get permission to submit the release pipeline job from the Adoptium PMC members, discussion is via the Adoptium #release channel (https://adoptium.slack.com/messages/CLCFNV2JG).

## Lockdown period

During the week before release we lock down the `openjdk-build` and `ci-jenkins-pipeline` repositories to
only include "critical" fixes (i.e. those which will otherwise cause a build
break or other problem which will prevent shipping the release builds.
This stops last minute changes going in which may destabilise things.

If a change has to go in during this "lockdown" period it should be done by
posting a comment saying "Requesting approval to merge during the lockdown
period. Please thumbs up the comment to approve". If two committers into the
repository express approval then the change can be merged during the
lockdown period.

## Steps for every version

Here are the steps:

1. Disabling nightly testing so the release builds aren't delayed by any nightly test runs (`enableTests : false` in [defaults.json](https://github.com/adoptium/ci-jenkins-pipelines/blob/master/pipelines/defaults.json)). Ensure the build pipeline generator job runs successfully (https://ci.adoptopenjdk.net/job/build-scripts/job/utils/job/build-pipeline-generator/), and that the flag is disabled by bringing up the Build pipeline job and check the "enableTests" flag is disabled.
1. Ensure that the [appropriate mirror job](https://ci.adoptopenjdk.net/view/git-mirrors/job/git-mirrors/job/adoptium/) has completed and that the corresponding repository at https://github.com/adoptium/jdkXX has successfully received the tag for the level you are about to build. If there are any conflicts the can be resolved on the machine where it failed if you have access to the private `adoptium_temurin_bot_ssh_key.gpg` key, or ask someone with push access to the repositories to manually run the mirror job and aresolve the conflicts.
1. If desired, add a banner to the website to indicate that the releases are coming in the near future ([Sample PR](https://github.com/adoptium/adoptium.net/pull/266/files))
1. Build and Test the OpenJDK for "release" at Adoptium using a build pipeline job as follows:
   - Job: https://ci.adoptopenjdk.net/job/build-scripts/job/openjdk8-pipeline/build (Switch `openjdk8` for your version number)
   - `targetConfigurations`: remove all the entries for the variants you don't want to build (e.g. remove the openj9 ones for hotspot releases) or any platforms you don't want to release (Currently that would include OpenJ9 aarch64)
   - `releaseType: Release`
   - [OpenJ9 ONLY] `overridePublishName`: github binaries publish name (NOTE: If you are doing a point release, do NOT adjust this as we don't want the filenames to include the `.x` part), e.g. `jdk8u232-b09_openj9-0.14.0` or `jdk-11.0.5+10_openj9-0.14.0`
   - `adoptBuildNumber`: Leave blank unless you are doing a point release in which case it should be a number starting at `1` for the first point release.
   - [OpenJ9 only] `scmReference`: extensions release branch: e.g. `openj9-0.14.0`
   - `additionalConfigureArgs`: JDK8 automatically adds`--with-milestone=fcs` in `build.sh` so there's no need to provide it here. For JDK11+ use `--without-version-pre --without-version-opt` (for EA releases use: `--with-version-pre=ea --without-version-opt`)
   - `scmReference`: One of the following:
     - For HotSpot, it's the same tag suffixed with `_adopt` e.g. `jdk-13.0.1+9_adopt`
     - For HotSpot (arm32), the tag usually takes the form `jdk8u322-b04-aarch32-xxxxxxxx`
     - NOTE you need to set `overridePublishName` for arm32 to the actual OpenJDK tag (`jdk8u322-b04`)
     - For OpenJ9 (all versions) use the OpenJ9 branch e.g. `openj9-0.15.1`
   - `aqaReference` should be set to the appropriate branch of the `aqa-tests` repository which is appropriate for this release. Generally of the form `vX.Y.Z-release`
   - `enableTests`: tick
   - SUBMIT!!
1. Once the Build and Test pipeline has completed,
   [triage the results](https://github.com/AdoptOpenJDK/openjdk-tests/blob/master/doc/Triage.md)
   ([TRSS](https://trss.adoptopenjdk.net/tests/Test) will probably help!)
   - Find the milestone build row, and click the "Grid" link
   - Check all tests are "Green", and if not "hover" over the icon and follow the Jenkins link to triage the errors...
   - Raise issues either at:
     - [temurin-build](https://github.com/adoptium/temurin-build) or [openjdk-tests](https://github.com/AdoptOpenJDK/openjdk-tests) (for Adopt build or test issues)
     - [ci-jenkins-pipelines](https://github.com/adoptium/ci-jenkins-pipelines) (for jenkins pipelines specific issues)
     - [eclipse/openj9](https://github.com/eclipse-openj9/openj9) (for OpenJ9 issues)
1. Discuss failing tests with [Shelley Lambert](https://github.com/smlambert)
1. Once all AQA tests on all platforms have been signed off, then nightly tests can be re-enabled. See the notes on checking the regeneration job worked in step 1.
1. If "good to publish", then get permission to publish the release from the Adoptium PMC members, discussion is via the Adoptium [#release](https://adoptium.slack.com/messages/CLCFNV2JG) Slack channel.
1. Once permission has been obtained, run the [openjdk_release_tool](https://ci.adoptopenjdk.net/job/build-scripts/job/release/job/refactor_openjdk_release_tool/) to publish the releases to github (restricted access - if you can't see this link, you don't have access). It is *strongly recommended* that you run first with the `DRY_RUN` checkbox enabled and check the output to verify that the correct list of files you expected are picked up.
   - `TAG`: (github binaries published name)  e.g. `jdk-11.0.5+9` or `jdk-11.0.5+9_openj9-0.nn.0` for OpenJ9 releases. If doing a point release, add that into the name e.g. for a `.3` release use something like these (NOTE that for OpenJ9 the point number goes before the openj9 version): `jdk8u232-b09.3` or `jdk-11.0.4+11.3_openj9-0.15.1`
   - `VERSION`: (select version e.g. `jdk11`)
   - `UPSTREAM_JOB_NAME`: (build-scripts/openjdkNN-pipeline)
   - `UPSTREAM_JOB_NUMBER`: (the job number of the build pipeline under build-scripts/openjdkNN-pipeline) e.g. 86
   - `RELEASE`: "ticked"
   - `aqaReference` : The correct [aqa-tests release branch name](https://github.com/adoptium/aqa-tests/branches) to use for this release e.g. `v0.8.0-release`
   - If you need to restrict the platforms or only ship jdks or jres, either use `ARTIFACTS_TO_COPY` e.g. `**/*jdk*mac*` or add an explicit exclusion in `ARTIFACTS_TO_SKIP` e.g. `**/*mac*`. These may be required if you had to re-run some of the platforms under a different pipeline earlier in the process. If you're unsure what the possible names are, look at the artifacts of the appropriate `openjdkNN-pipeline` job. If you are shipping x64_linux ensure that you include the `sources` tar.gz files with the corresponding checksum and json file.
   - `ARTIFACTS_TO_SKIP`: `**/*testimage*`
   - If you need to restrict the platforms, fill in `ARTIFACTS_TO_COPY` and if needed att to `ARTIFACTS_TO_SKIP`. This may also be required if you had to re-run some of the platforms under a different pipeline earlier in the process. I personally tend to find it cleaner to release Linux in one pipeline, Windows+Mac in another, then the others together to keep the patterns simpler. Sample values for `ARTIFACTS_TO_COPY` are as follows (use e.g. `_x64_linux_` to restrict by architecture if required):
     - `**/*_linux_*.tar.gz,**/*_linux_*.sha256.txt,**/*_linux_*.json` (Exclude `**/*alpine_linux*` if you don't really want that to be picked up too)
     - Alternative that wouldn't pick up Alpine: `target/linux/x64/hotspot/**.tar.gz,target/linux/x64/hotspot/target/linux/x64/hotspot/*.sha256.txt`
     - `**/*_mac_*.tar.gz,**/*_mac_*.sha256.txt,**/*_mac_*.json,**/*_mac_*.pkg`
     - `**/*_windows_*.zip,**/*_windows_*.sha256.txt,**/*_windows_*.json,**/*_windows_*.msi`
     - `**/*_aix_*.tar.gz,**/*_aix_*.sha256.txt,**/*_aix_*.json`
     - `**/*_solaris_*.tar.gz,**/*_solaris_*.sha256.txt,**/*_solaris_*.json`
   - SUBMIT!!
1. Once the job completes successfully, check the binaries have uploaded to GitHub at somewhere like https://github.com/adoptium/temurin8-binaries/releases/tag/jdk8u302-b08
1. Within 15 minutes the binaries should be available on the website too at e.g. https://adoptium.net/?variant=openjdk11&jvmVariant=hotspot (NOTE: If it doesn't show up, check whether the API is returning the right thing (e.g. with a link such as [this](https://api.adoptium.net/v3/assets/feature_releases/17/ga?architecture=x64&heap_size=normal&image_type=jre&jvm_impl=hotspot&os=linux&page=0&page_size=10&project=jdk&sort_method=DEFAULT&sort_order=DESC&vendor=eclipse), and that the `.json` metadata files are uploaded correctly)
1. Since you have 15 minutes free, use that time to update https://github.com/adoptium/adoptium.net/blob/master/src/handlebars/support.handlebars which is the source of  https://adoptium.net/support.html and (if required) the supported platforms table at https://github.com/adoptium/adoptium.net/blob/master/src/handlebars/supported_platforms.handlebars which is the source of https://adoptium.net/supported_platforms.html, and also update https://adoptium.net/release_notes.html ([Sample change](https://github.com/adoptium/adoptium.net/pull/675/commits/563d8e2f0d9d26500a7e8d9eca61b491f73f1f37)
1. [Mac only] Once the binaries are available on the website you need to run the [homebrew cask updater](https://github.com/AdoptOpenJDK/homebrew-openjdk/wiki/Running-the-cask-updater) which will create a pull request [here](https://github.com/AdoptOpenJDK/homebrew-openjdk/pulls). Normally George approves these but in principle as long as the CI passes, they should be good to approve. You don't need to wait around and merge the PR's because the Mergify bot will automatically do this for you as long as somebody has approved it.
1. Publicise the Temurin release via slack on Adoptium #release
1. If desired, find someone with the appropriate authority (George, Martijn, Shelley, Stewart) to post a tweet about the new release from the Adoptium twitter account

## [OpenJ9 Only] Milestone Process

The following examples all use `-m1` as an example - this gets replaced with a later number for the second and subsequent milestones as required.

1. Eclipse OpenJ9 creates a new branch for their release branch: e.g. `v0.17.0-release`
2. Eclipse OpenJ9 tag the commit in the "release" branch that they want to be the milestone level as e.g. `openj9-0.17.0-m1`
3. OpenJDK extensions branches the `openj9` branch to create the release branch, called `openj9-0.nn.0`
4. Ask someone in the extensions team to make the following modifications:
   - If this is milestone 2 (m2) then check for new jdk tag to merge into the release branch:
     - Merge into the OpenJ9 extensions release branch (e.g. `openj9-0.17.0`) the latest tag merged from OpenJDK (automated jobs merge the tag into `openj9-staging`, but not the release branch so this has to be done manually). eg.:
       - `git checkout openj9-0.18.0`
       - `git merge -m"Merge jdk-11.0.6+10" jdk-11.0.6+10`
       - Resolve any merge conflicts again if necessary.
     - Create a Pull Request and Merge (using a Merge Commit, do not Squash&Merge, otherwise we lose track of history).
     - Update closed/openjdk-tag.gmk with tag just merged. (This is used for the java - version) e.g.:
  
   ```bash
   OPENJDK_TAG:= jdk-11.0.6+10
   ```
  
   - Update [closed/get_j9_source.sh](https://github.com/ibmruntimes/openj9-openjdk-jdk11/blob/openj9/closed/get_j9_source.sh) (Link is for JDK11, chnage as appropriate!) to pull in Eclipse OpenJ9 & OMR milestone 1 tags e.g. `openj9-0.nn.0-m1`([Sample PR](https://github.com/ibmruntimes/openj9-openjdk-jdk11/commit/4607d33d99c566054261557fdf34bcbfaefc6480))
   - Update custom-spec.gmk.in with correct `J9JDK_EXT_VERSION` for the release, [Sample commit for 8](https://github.com/ibmruntimes/openj9-openjdk-jdk8/commit/8512fe26e568962d4ee08f82f2f59d3bb241bb9d) and [Sample commit for 11](https://github.com/ibmruntimes/openj9-openjdk-jdk11/commit/c7964e29fea19a7803a86bc991de0d0e45547dc8) e.g:
  
   ```bash
   jdk11+ ==> J9JDK_EXT_VERSION       := 11.0.5.0-m1
   jdk8     ==>  J9JDK_EXT_VERSION       := $(JDK_MINOR_VERSION).$(JDK_MICRO_VERSION).$(JDK_MOD_VERSION).$(JDK_FIX_VERSION)-m1
   # J9JDK_EXT_VERSION       := HEAD   <==  !!! Comment out this line
   JDK_MOD_VERSION=232
   JDK_FIX_VERSION=0
   ```

5. Build and Test the OpenJDK for OpenJ9 "release" at Adoptium using a "Weekly" releaseType so it runs the extended tests. Submit the Build pipeline job as follows https://ci.adoptopenjdk.net/job/build-scripts/job/openjdkNN-pipeline/build?delay=0sec
   - `targetConfigurations`: remove all "hotspot" entries
   - `releaseType`: `Weekly`
   - `overridePublishName`: github binaries publish name, e.g. `jdk8u232-b09_openj9-0.17.0-m1` or `jdk-11.0.5+10_openj9-0.17.0-m1`
   (Note: Everything before the underscore should be copied from the OPENJDK_TAG value inside <extensions_repo_url>/closed/openjdk-tag.gmk)
   - `scmReference`: extensions release branch: e.g. `openj9-0.17.0`
   - `additionalConfigureArgs`: JDK8 automatically adds`--with-milestone=fcs` in `build.sh` so there's no need to provide it here. JDK11+: `--without-version-pre --without-version-opt` (for EA releases use: `--with-version-pre=ea --without-version-opt`)
   - `enableTests`: "ticked"
   - SUBMIT!!
6. Triage the results and publish as required with using the publish name from `overridePublishName` in the previous step but with `RELEASE` UNCHECKED as this is not a full release build.

### OpenJDK "New" Release

- The refers to a "new" major (Short or Long Term) OpenJDK Release (e.g. jdk13, jdk14, jdk15, ...)
- Oracle and contributors work on releases in the "head" OpenJDK stream: https://hg.openjdk.java.net/jdk/jdk
- 3 months prior to the GA date, the `head` stream is branched into a new release stream for development rampdown e.g. https://hg.openjdk.java.net/jdk/jdk14
- Regular builds are tagged every week or so in a format such as `jdk-13+21`
- Eventually after rampdown and final phase testing the GA build is tagged and released, e.g. the `jdk-13-ga` code level is tagged along side the actual release build tag.
- When a new release occurs, we must also update one of our job generators to match the new jdk versions and remove old STR that are no longer needed. The full details on what these are in the [regeneration README.md](https://github.com/adoptium/ci-jenkins-pipelines/blob/master/pipelines/build/regeneration/README.md) but for a quick run down on how to update them when we want to build a new release, follow the steps below:

  1. Update the Job Folder - https://ci.adoptopenjdk.net/job/build-scripts/job/utils/: The jobs themselves you are looking for are called `pipeline_jobs_generator_jdkxx` (`pipeline_jobs_generator_jdk` for HEAD). Firstly, ensure that the job description of each generator (and it's parameter's descriptions) are up to date. Then, follow these steps:
  
  - If you are ADDING a JDK version:
    - Ensure that JDK N-1 is available as build JDK on the builders. For example in order to build JDK 15, JDK 14 needs to be installed on the build machines. As a temporary measure, [code](./build-farm/platform-specific-configurations/linux.sh#L110) so as to download the JDK to the builder via the API has been added. NOTE: For the transition period shortly after a new JDK has been branched, there might not yet exist a generally available release of JDK N-1.
    - Ensure that JDK sources are being mirrored. Example [infrastructure request](https://github.com/AdoptOpenJDK/openjdk-infrastructure/issues/1096)
    - Ensure that a repository which contains the binary releases exists. Example [temurin15-binaries](https://github.com/adoptium/temurin15-binaries)
    - Add build scripts for the new JDK release. Example for [JDK 14](https://github.com/adoptium/temurin-build/commit/808b08fe2aefc005cf53f6cc1deb28a9b323ff)
    - Regenerate build jobs:
      - Create a New Item in the folder linked above that copies the `pipeline_jobs_generator_jdk` job. Call it `pipeline_jobs_generator_jdk<new-version-number>`.
      - Change the `Script Path` setting of the new job to `pipelines/build/regeneration/jdk<new-version-number>_regeneration_pipeline.groovy`. Don't worry if this currently doesn't exist in this repo, you'll add it in step 3.
      - Update the `Script Path` setting of the JDK-HEAD job (`pipeline_jobs_generator_jdk`) to whatever the new JDK HEAD is. I.e. if the new head is JDK16, change `Script Path` to `pipelines/build/regeneration/jdk16_regeneration_pipeline.groovy`
  - If you are REMOVING a JDK version:
    - Delete the job `pipeline_jobs_generator_jdk<version-you-want-to-delete>`

  1. Create the new build configurations for the release - https://github.com/adoptium/ci-jenkins-pipelines/tree/master/pipelines/jobs/configurations:

  - Create a new `jdk<new-version-number>_pipeline_config.groovy` file with the desired `buildConfigurations` for the new pipeline. 99% of the time, copy and pasting the configs from the previous version is acceptable. Ensure that the classname and instance of it is changed to `Config<new-version-number>`. Don't remove any old version configs.
  - Furthermore, you will also need to create another config file to state what jobs will be run with any new versions. If it doesn't currently exist, add a `jdkxx.groovy` file to [configurations/](https://github.com/adoptium/ci-jenkins-pipelines/tree/master/pipelines/jobs/configurations). [Example on how to do this](https://github.com/adoptium/temurin-build/pull/1815/files). Note, some files will need to be named `jdkxxu.groovy` depending on whether the version is maintained in an update repo or not. These will be the ONLY os/archs/variants that are regenerated using the job regenerators as described in the [regeneration readme](https://github.com/adoptium/ci-jenkins-pipelines/blob/master/pipelines/build/regeneration/README.md).
  
  1. Create a new Regeneration Pipeline for the downstream jobs - https://github.com/adoptium/ci-jenkins-pipelines/blob/master/pipelines/build/regeneration:
  
  Create a new `jdk<new-version-number>_regeneration_pipeline.groovy`. Ensure that the `javaVersion`, `targetConfigurations` and `buildConfigurations` variables are what they should be for the new version. Don't remove any old version configs. While you're here, make sure all of the current releases have a `regeneration_pipeline.groovy` file (including head). If they don't, create one using the same technique as above.
  
  1. Build the `pipeline_jobs_generator` that you just made. Ensure the equivalent `openjdkxx_pipeline` to the generator exists or this will fail. If the job fails or is unstable, search the console log for `WARNING` or `ERROR` messages for why. Once it has completed successfully, the [pipeline](https://ci.adoptopenjdk.net/job/build-scripts/) is ready to go!

  1. Update the view for the [build and test pipeline calendar](https://ci.adoptopenjdk.net/view/Build%20and%20Test%20Pipeline%20Calendar) to include the new version.

### Update Repository

At some point in a java version's lifecycle, the JDK version will be maintained in an update repository. The first notification of this will be via mail list in one of two places:

- [jdk-dev](https://mail.openjdk.java.net/mailman/listinfo/jdk-dev)
- [jdk-updates-dev](https://mail.openjdk.java.net/mailman/listinfo/jdk-updates-dev)
When this occurs, usually a TSC member will create the `jdk<version>u` update repo ([example of the JDK11u one](https://github.com/adopium/openjdk-jdk11u)) via our Skara mirroring jobs that pull in the commit and tag info from the Mercurial repository. To find out more about Skara and our other mirroring jobs, see https://github.com/adoptium/mirror-scripts.

*New Adopt mirror repo creation, by an Adoptium github Admin:*

1. Create a new empty repo adoptium/openjdk-jdkNNu
2. Rename mirror job from https://ci.adoptopenjdk.net/view/git-mirrors/job/git-mirrors/job/git-skara-jdkNN to https://ci.adoptopenjdk.net/view/git-mirrors/job/git-mirrors/job/git-skara-jdkNNu
3. Update mirror job "Execute shell" to pass jdkNNu as parameter to bash ./skaraMirror.sh jdkNNu
4. Run the renamed job twice, first one will fail due to empty repo, 2nd run should succeed.
5. Add the Adoptium.md "marker" text file to both branches "dev" and "release".

When the repo has been created, a few changes to the codebase will be necessary where the code references a jdk version but not it's new update version. I.e. `jdk11` became `jdk11u` when it was moved to an update repository.

*If a product is to be moved to an update repo, follow these steps in chronological order to ensure our builds continue to function:*

1. ci-jenkins-pipelines: Update the [configurations](https://github.com/adoptium/ci-jenkins-pipelines/tree/master/pipelines/jobs/configurations)
Rename the nightly build targets file (it will be named `jdkxx.groovy`, [example here](https://github.com/adoptium/ci-jenkins-pipelines/blob/master/pipelines/jobs/configurations/jdk15u.groovy)) to be `jdkxxu.groovy`. Do the same for the pipeline config file (named `jdkxx_pipeline_config.groovy`, [example here](https://github.com/adoptium/ci-jenkins-pipelines/blob/master/pipelines/jobs/configurations/jdk15u_pipeline_config.groovy)).

2. ci-jenkins-pipelines: Update version from `jdkxx` to `jdkxxu` inside [docs/generateBuildMatrix.sh](https://github.com/adoptium/ci-jenkins-pipelines/blob/master/docs/generateBuildMatrix.sh)

3. ci-jenkins-pipelines: Run on "linux" platform your updated docs/generateBuildMatrix.sh script to generate the updated README.md table to be updated at the end of [README.md](https://github.com/adoptium/ci-jenkins-pipelines/blob/master/README.md#build-status)

4. openjdk-build: Update the `JDKXX_VERSION` from `jdkxx` to `jdkxxu` inside the [build script constants](https://github.com/adoptium/temurin-build/blob/master/sbin/common/constants.sh) that is being shifted to an update repository.

5. openjdk-build: Update the version from `jdkxx` to `jdkxxu` inside [.github/workflows/build.yml](https://github.com/adoptium/temurin-build/blob/master/.github/workflows/build.yml)

6. Merge both ci-jenkins-pipelines and openjdk-build Pull Requests.

7. Cancel jdkxx job regenerator that will have just been triggered: [job regenerator](https://ci.adoptopenjdk.net/job/build-scripts/job/utils/)

8. Rename the jenkins pipeline jobs regenerator [job regenerator](https://ci.adoptopenjdk.net/job/build-scripts/job/utils/) from `pipeline_jobs_generator_jdkxx` to `pipeline_jobs_generator_jdkxxu`. Then manually re-build.

9. Check the regenerator has created all the new jdkxxu build jobs successfully: [build jobs](https://ci.adoptopenjdk.net/job/build-scripts/job/jobs/)

10. Delete the old jdkxx build jobs folder: https://ci.adoptopenjdk.net/job/build-scripts/job/jobs/jdkxx: [build jobs](https://ci.adoptopenjdk.net/job/build-scripts/job/jobs/)

11. Submit a test [pipeline build](https://ci.adoptopenjdk.net/job/build-scripts/)

### Post Release Tasks

Once all the release binaries have been published the following tasks should be completed:

1. Reset the "weekly_release_scmReferences" (change to "") for the weekend release test build so it is using HEAD streams: https://github.com/adoptium/ci-jenkins-pipelines/tree/master/pipelines/jobs/configurations
2. Re-enable "Tests" for Nightly pipelines, eg.https://github.com/adoptium/temurin-build/pull/2401/files . After merging, check the build-pipeline-generator runs successfully: https://ci.adoptopenjdk.net/job/build-scripts/job/utils/job/build-pipeline-generator . It's possible the script change may require "Script Approval" by a Jenkins Administrator (https://ci.adoptopenjdk.net/scriptApproval/).
3. If the latest version just released has come to the end of its non-LTS lifecycle (2 CPU updates, eg.jdk-15.0.2), then disable and retire that version form the Nightly pipeline builds:
   - eg.https://github.com/adoptium/temurin-build/pull/2403/files

## Summary on point releases

Occasionally we may have to do an out-of-band release that does not align with a quarterly release from the upstream OpenJDK project. This may occur if there has been a problem with our build process that we missed at GA time, to fix a critical issue, or when a project outside OpenJDK (e.g. OpenJ9) needs to do an interim release. In order to do such a release, follow the steps included in the process above which I'll repeat here for clarity:

1. When triggering the pipeline, set `AdoptBuildNumber` to a unique number for the point release
2. If you used a custom entry in `overridePublishName` when kicking off the GA pipeline, keep it the same as for the GA release - we DO NOT want the filenames changed to include the point number
3. When running the publish job, you need to use a custom `TAG` in order to publish it to the website with a separate name from what you had initially e.g.  `jdk-11.0.5+10.1_openj9-0.17.1` (Note the position of the `.1` for OpenJ9 releases in that example - it's after the openj9 version but before the OpenJ9 version.
