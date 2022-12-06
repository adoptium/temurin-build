# temurin-build FAQ

This document covers cover how to perform various repeatable tasks in the
repository that might not otherwise be obvious from just looking at the
repository.

## How do I find my way around Temurin's build automation scripts?

I wrote this diagram partially for my own benefit in [issue 957](https://github.com/adoptium/temurin-build/issues/957) that lists the shell scripts (`S`) and environment scripts (`E`). I think it would be useful to incorporate this into the documentation (potentially annotated with a bit more info) so people can find their way around the myriad of script levels that we now have.
Note that the "end user" scripts start at `makejdk-any-platform.sh` and a
diagram of those relationships can be seen [here](https://github.com/adoptium/temurin-build/blob/master/docs/images/AdoptOpenJDK_Build_Script_Relationships.png)

*See the [ci-jenkins-pipelines FAQ.md](https://github.com/adoptium/ci-jenkins-pipelines/blob/master/FAQ.md#how-do-i-find-my-way-around-adoptopenjdks-build-automation-scripts) for the Jenkins side of the pipeline*

```markdown
G               - make-adopt-build-farm.sh
S                 - set-platform-specific-configurations.sh
E                    - sbin/common/constants.sh (DUPLICATED LATER FROM configureBuild.sh)
E                    - platform-specific-configurations/${OPERATING_SYSTEM}.sh
S                 - makejdk-any-platform.sh
E                   - ${SCRIPT_DIR}/sbin/common/config_init.sh (Parse options)
E                   - ${SCRIPT_DIR}/docker-build.sh (Runs build.sh within container)
E                   - ${SCRIPT_DIR}/native-build.sh (Runs build.sh natively)
E                   - ${SCRIPT_DIR}/configureBuild.sh
E                     - ${SCRIPT_DIR}/sbin/common/constants.sh
E                     - ${SCRIPT_DIR}/sbin/common/common.sh
E                     - ${SCRIPT_DIR}/signalhandler.sh (rm container on SIGINT/SIGTERM)
S                   - {buildOpenJDKViaDocker|buildOpenJDKInNativeEnvironment}
```

There is also some documentation in [CHANGELOG.md](CHANGELOG.md)

## What are the prerequisites for a system used for builds?

- The upstream OpenJDK build requirements are at [Supported Build Platforms](https://wiki.openjdk.java.net/display/Build/Supported+Build+Platforms)
- The Temurin levels we build on are in [Minimum-OS-levels](https://github.com/adoptium/temurin-build/wiki/%5BWIP%5D-Minimum-OS-levels) although anything with comparable equivalent or later C libraries should work OK (in particular we have built on most current Linux distros without issues)

In terms of compilers, these are what we currently use for each release:

| Version | OS      | Compiler |
|---------|---------|----------|
| JDK8/11 | Linux   | GCC 7.5                                           |
| JDK17/18| Linux   | GCC 10.3                                          |
| JDK19+  | Linux   | GCC 11.2                                          |
| All     | Alpine  | GCC 10.3.1                                        |
| JDK8    | Solaris | Sun Studio 12.3                                   |
| JDK8    | Windows | VS2017 (19) (Win64) or VS2013 (12) (Win32 and J9) |
| JDK11+  | Windows | VS2019 (10) (Win64) or VS2017 (19) (Win32)        |
| JDK8    | AIX     | xlC/C++ 13.1.3                                    |
| JDK11+  | AIX     | xlC/C++ 16.1.0                                    |
| JDK8    | macOS   | GCC 4.2.1 (LLVM 2336.11.00                        |
| JDK11   | macOS   | clang-700.1.81                                    |
| JDK13+  | macOS   | clang-900.0.39.2                                  |

All machines at Temurin are set up using the ansible playbooks from the
[infrastructure](https://github.com/adoptopenjdk/openjdk-infrastructure) repository.

## How do I change the parameters, such as configure flags, for a Jenkins build

Where you change them depends on the scope of the parameter or flag:

- *If the parameter will affect all users, regardless of environment or OS/Arch*
  - [build.sh](https://github.com/adoptium/temurin-build/blob/master/sbin/build.sh) OR [makejdk-any-platform.sh](https://github.com/adoptium/temurin-build/blob/master/makejdk-any-platform.sh) depending on how high up in the execution stack it needs to be.
  - [Example PR - Adding a new archival feature for OpenJ9 memory dumps](https://github.com/adoptium/temurin-build/pull/2464)
- *If the parameter will affect all machines of a specific OS OR related to the environment set up by [our ansible scripts](https://github.com/AdoptOpenJDK/openjdk-infrastructure) at the shell script level*
  - Modify the relevant environment files in [platform-specific-configurations](https://github.com/adoptium/temurin-build/tree/master/build-farm/platform-specific-configurations)
  - [Example PR - Adding a new configure flag for OpenJ9 on all AIX machines](https://github.com/adoptium/temurin-build/pull/1442/files)
- *If the parameter will affect only our jenkins environment or jenkins machine environment*
  - Modify the [pipeline files](https://github.com/adoptium/ci-jenkins-pipelines/tree/master/pipelines/build), although this is normally only done for configuration differences such as OpenJ9 Large Heap builds. See [the configuration file documentation](https://github.com/adoptium/ci-jenkins-pipelines#configuration-files) for more information about adding or altering custom jenkins param.
  - [Example PR - Adding Jenkins Support for a Cross Compiled Bisheng Binary](https://github.com/adoptium/ci-jenkins-pipelines/pull/68)

### TL;DR (Quick Reference Table)

| Parameter Location | Impact |
| --- | --- |
| [build.sh](https://github.com/adoptium/temurin-build/blob/master/sbin/build.sh) OR [makejdk-any-platform.sh](https://github.com/adoptium/temurin-build/blob/master/makejdk-any-platform.sh) | Anyone (including end users) who are running [makejdk-any-platform.sh](https://github.com/adoptium/temurin-build/blob/master/makejdk-any-platform.sh) |
| [platform-specific-configurations](https://github.com/adoptium/temurin-build/tree/master/build-farm/platform-specific-configurations) scripts | Those using [build-farm/make-adopt-build-farm.sh](https://github.com/adoptium/temurin-build/blob/master/build-farm/make-adopt-build-farm.sh) (inc. our pipelines) - should be stuff specific to our machines |
| Jenkins resources in [ci-jenkins-pipelines](https://github.com/adoptium/ci-jenkins-pipelines) | Only when run through our jenkins pipelines. See the [configuration file documentation](https://github.com/adoptium/ci-jenkins-pipelines#configuration-files) for more information |

## How to do a new release build

Since it's quite long, this is covered in a separate [RELEASING.md](RELEASING.md) document

## I've modified the build scripts - how can I test my changes?

If you're making changes ensure you follow the contribution guidelines in
[CONTRIBUTING.md](CONTRIBUTING.md) including running [shellcheck](https://github.com/koalaman/shellcheck) if you're modifying the shell scripts.

For more information, see the [PR testing documentation](Testing.md).

## What are smoke tests?

Smoke tests are quick and simple tests to verify that we 'built the right thing'.  They can be found in the [buildAndPackage directory](https://github.com/adoptium/temurin-build/tree/master/test/functional/buildAndPackage)
Smoke tests verify things like:

- the java -version output is correct
- certain features are available in certain builds (checks for shenandoah GC or xxx)
- the right set of modules are included
etc

## How and where are smoke tests run?

They use the same mechanisms and automation used by the AQA test suite.  This means they can be run on the command-line, or as part of a Jenkins job or in a GitHub workflow.  For this repository, they are part of PR testing via the [build.yml](https://github.com/adoptium/temurin-build/blob/master/.github/workflows/build.yml#L151) workflow using the [run-aqa](https://github.com/adoptium/run-aqa) action.

They are also run as part of the Jenkins build pipelines (see the [runSmokeTests()](https://github.com/adoptium/ci-jenkins-pipelines/blob/master/pipelines/build/common/openjdk_build_pipeline.groovy#L264-L301) method in the openjdk_build_pipeline groovy script), triggered after the build is complete and before any AQA tests get run against the build.  If smoke tests fail, it likely indicates we built the 'wrong thing' and there is no point running further testing until we resolve the build issues.

To run them on the command-line, one can follow the same general instructions for running any AQA test on the command-line, with the additional step of exporting variables to indicate where to find test material (VENDOR_TEST_REPOS, VENDOR_TEST_BRANCHES, VENDOR_TEST_DIRS).   See: [SmokeTesting.md](https://github.com/adoptium/temurin-build/blob/master/SmokeTesting.md)

## Which OS levels do we build on?

The operating systems/distributions which we build or are documented in the
[temurin-build wiki](https://github.com/adoptium/temurin-build/wiki/%5BWIP%5D-Minimum-OS-levels).
Runtime platforms are in our [supported platforms page](https://adoptium.net/supported_platforms.html).

## How to add a new build pipeline param and associated job configuration?

[This PR](https://github.com/adoptium/temurin-build/pull/2416) demonstrates changes required to add a new build pipeline param and the associated version/platform job configurations for setting the value when needed  (note, the `pipelines/` dir has since been moved to our [jenkins repository](https://github.com/adoptium/ci-jenkins-pipelines)).

## How do I build from a tag(without docker)

The following are the pre-requisites for the the build to be successful

| Dependency            | Install command(Linux)|
|-----------------------|-----------------------------------------|
| libfontconfig1-dev    | `sudo apt-get install libfontconfig1-dev`|
| libx11-dev libxext-dev libxrender-dev libxrandr-dev libxtst-dev libxt-dev   | `sudo apt-get install libx11-dev libxext-dev libxrender-dev libxrandr-dev libxtst-dev libxt-dev`|
| libasound2-dev     | `sudo apt-get install libasound2-dev`|
| libcups2-dev     | `sudo apt-get install libcups2-dev`|

After installing the above dependencies, run the following commands from the terminal

 Clone temurin-build repository

 `git clone https://github.com/adoptium/temurin-build.git`

 Navigate to the root directory of the project

 `cd temurin-build`

 Set the variant to temurin

 `export VARIANT=temurin`

 `export JAVA_TO_BUILD=jdk`

 The Adoptium build tag you want to build, don't set to build HEAD

 `export SCM_REF=jdk-20+2_adopt`

 Set the build to spin on release

 `export RELEASE=true`

 Bypass the cache completely by calling the real compiler using ccache

 `export CONFIGURE_ARGS=--disable-ccache`

 Trigger the build

 `build-farm/make-adopt-build-farm.sh`

## Build output:

Once the build has successfully completed the built JDK archive artifact will be available in directory:

JDK Archive: `workspace/target/jdk-hotspot.tar.gz`
