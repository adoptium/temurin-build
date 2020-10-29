# openjdk-build FAQ

This document covers cover how to perform various repeatable tasks in the
repository that might not otherwise be obvious from just looking at the
repository.

## Access control in this repository

The GitHub teams relevant to this repository are as follows (Note, you
won't necessarily have access to see these links):

- [GetOpenJDK](https://github.com/orgs/AdoptOpenJDK/teams/getopenjdk) - `Triage` level of access which lets you assign issues to people
- [build](https://github.com/orgs/AdoptOpenJDK/teams/build) - `Write` access which lets you approve and merge PRs and run and configure most Jenkins jobs
- [release](https://github.com/orgs/AdoptOpenJDK/teams/build) - Allows you to run the release jobs in Jenkins

## How do I find my way around AdoptOpenJDK's build automation scripts?

I wrote this diagram partially for my own benefit in [issue 957](https://github.com/AdoptOpenJDK/openjdk-build/issues/957) that lists the Jenkins jobs (`J`), Groovy scripts from GitHub (`G`), shell scripts (`S`) and environment scripts (`E`). I think it would be useful to incorporate this into the documentation (potentially annotated with a bit more info) so people can find their way around the myriad of script levels that we now have.
Note that the "end-user" scripts start at `makejdk-any-platform.sh` and a
diagram of those relationships can be seen [here](https://github.com/AdoptOpenJDK/openjdk-build/blob/master/docs/images/AdoptOpenJDK_Build_Script_Relationships.png)

```markdown
J - build-scripts/job/utils/job/build-pipeline-generator
G   - Create openjdk*-pipeline jobs from pipelines/jobs/pipeline_job_template.groovy
J   - openjdk11-pipeline
G     - pipelines/build/openjdk*_pipeline.groovy
G       - pipelines/build/common/build_base_file.groovy
G         - create_job_from_template.groovy (Generates e.g. jdk11u-linux-x64-hotspot)
G       - configureBuild()
G         - .doBuild() (common/build_base_file.groovy)
J           - context.build job: downstreamJobName (e.g. jdk11u/job/jdk11u-linux-x64-hotspot)
J             (Provides JAVA_TO_BUILD, ARCHITECTURE, VARIANT, TARGET_OS + tests)
G             - openjdk_build_pipeline.groovy
G               - context.sh make-adopt-build-farm.sh
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

- The upstream OpenJDK build requirements are at https://wiki.openjdk.java.net/display/Build/Supported+Build+Platforms
- The AdoptOpenJDK levels we build on are at https://github.com/AdoptOpenJDK/openjdk-build/wiki/%5BWIP%5D-Minimum-OS-levels
  although anything with comparable equivalent or later C libraries should work ok (in particular we have built on most current Linux distros without issues)

In terms of compilers, these are what we currently use for each release:

| Version | OS      | Compiler |
|---------|---------|----------|
| JDK8    | Linux   | GCC 4.8 (HotSpot) GCC 7.6 (OpenJ9)                |
| JDK11+  | Linux   | GCC 7.5                                           |
| JDK8    | Windows | VS2013 (12.0) (HotSpot) or VS2010 (10.0) (OpenJ9) |
| JDK11+  | Windows | VS2017                                            |
| JDK8/11 | AIX     | xlC/C++ 13.1.3                                    |
| JDK13+  | AIX     | xlC/C++ 16.1.0                                    |
| JDK8    | macos   | GCC 4.2.1 (LLVM 2336.11.00                        |
| JDK11   | macos   | clang-700.1.81                                    |
| JDK13+  | macos   | clang-900.0.39.2                                  |

All machines at AdoptOpenJDK are set up using the ansible playbooks from the
[infrastructure](https://github.com/adoptopenjdk/openjdk-infrastructure) repository.

## Adding a new major release to be built

1. Create the new release repository under GitHub.com/adoptopenjdk (generally `openjdk-jdkxx`)
2. Add the release to the list at [pipeline file](https://github.com/AdoptOpenJDK/openjdk-build/tree/master/pipelines/build)
3. Adjust the PR testing pipeline [Example](https://github.com/AdoptOpenJDK/openjdk-build/pull/1394) to use the new release

## Removing a major release once you've added a new one

Unless the last release was an LTS one, you will generally want to remove one of the old versions after creating a new one. This can be done with `disableJob = true` in the release configuration files

[Example](https://github.com/AdoptOpenJDK/openjdk-build/pull/1303/files)

## How to enable/disable a particular build configuration

1. Add/Remove it from the configuration files in https://github.com/AdoptOpenJDK/openjdk-build/tree/master/pipelines/jobs/configurations
2. if you're removing one and it's not just temporarily, you may want to delete the specific job from Jenkins too

[Example PR - removing aarch64 OpenJ9 builds](https://github.com/AdoptOpenJDK/openjdk-build/pull/1452)

## How to add a new build variant

We perform different builds such as the based openjdk (hotspot), builds from the Eclipse OpenJ9 codebase as well as others such as Corretto and SAPMachine. These alternatives are referred to as build variants.

First you will need to add support into the [pipeline files](https://github.com/AdoptOpenJDK/openjdk-build/tree/master/pipelines/build) as well as any environment-specific changes you need to make in the [platform files](https://github.com/AdoptOpenJDK/openjdk-build/tree/master/build-farm/platform-specific-configurations)
For an example, see [this PR where Dragonwell was added](https://github.com/AdoptOpenJDK/openjdk-build/pull/2051/files)
For more information on other changes required, see [this document](https://github.com/AdoptOpenJDK/TSC/wiki/Adding-a-new-build-variant)

## How do I change the parameters, such as configure flags, for a Jenkins build

Either:

- Modify the environment files in [platform-specific-configurations](https://github.com/AdoptOpenJDK/openjdk-build/tree/master/build-farm/platform-specific-configurations)
- Modify the [pipeline files](https://github.com/AdoptOpenJDK/openjdk-build/tree/master/pipelines/build), although this is normally only done for configuration differences such as OpenJ9 Large Heap builds

[Example PR - Adding a new configure flag for OpenJ9](https://github.com/AdoptOpenJDK/openjdk-build/pull/1442/files)

## How to do a new release build

Since it's quite long, this is covered in a separate [RELEASING.md](RELEASING.md) document

## I've modified the build scripts - how can I test my changes?

If you're making changes ensure you follow the contribution guidelines in
[CONTRIBUTING.md](CONTRIBUTING.md) including running `./shellcheck.sh` if you're modifying
the shell scripts.

In order to test whether your changes work use the [test-build-script-pull-request](https://ci.adoptopenjdk.net/job/build-scripts-pr-tester/job/test-build-script-pull-request/) job!
Pass it your fork name (e.g. https://github.com/sxa555/openjdk-build) and the name of the branch and it will run a build using your updated scripts.
For more information, see the [PR testing documentation](./pipelines/build/prTester/README.md).

## Which OS levels do we build on?

The operating systems/distributions which we build or are documented in the
[openjdk-build wiki](https://github.com/AdoptOpenJDK/openjdk-build/wiki/%5BWIP%5D-Minimum-OS-levels).
Runtime platforms are in our [supported platforms page](https://adoptopenjdk.net/supported_platforms.html).