# Solaris "proxy" jobs in jenkins

From [Jenkins 2.463](https://www.jenkins.io/blog/2024/06/11/require-java-17/)
the jenkins server requires the agents to be running Java 17 or later. There
is no JVM which is available for running the agents on Solaris 10 (x64 and
SPARC) and therefore separate jobs have been created in jenkins for running
the builds and tests on that platform. The work for this has been covered
under
[temurin-build#4098](https://github.com/adoptium/temurin-build/issues/4098)
for builds and
[temurin-build#4099](https://github.com/adoptium/temurin-build/issues/4099) based on [a whiteboard session](https://github.com/adoptium/infrastructure/issues/3742#issuecomment-2478948681)
last year. This document covers what they do and how to analyse and debug
the results.

## Build jobs

In the previous case - and for all other platforms we have a platform
specific pipeline such as
[jdk8u-linux-x64-temurin](https://ci.adoptium.net/job/build-scripts/job/jobs/job/jdk8u/job/jdk8u-linux-x64-temurin/)
which performs the build and then initiates the test jobs.

### New top level pipeline

For the new world on Solaris, we use:

- [jdk8u-solaris-x64-temurin-simplepipe](https://ci.adoptium.net/job/build-scripts/job/jobs/job/jdk8u/job/jdk8u-solaris-x64-temurin-simplepipe/) which calls:
  - [jdk8u-solaris-x64-temurin-simple](https://ci.adoptium.net/job/build-scripts/job/jobs/job/jdk8u/job/jdk8u-solaris-x64-temurin-simple) to perform the build
  - [jdk8u-solaris-x64-temurin-simpletest](https://ci.adoptium.net/job/build-scripts/job/jobs/job/jdk8u/job/jdk8u-solaris-x64-temurin-simpletest/) to run all of the tests (all suites in one job)

Similar to the top level `openjdkXX-pipelines` in the past, the `-simplepipe`
pipelines take a cope of the artifacts from the `-simple` build job. At
present the `-simplepipe` uses an inline pipeline script which is not under
version control and has stages similer to the main platform specific
pipelines:

- build (Invokes the `-simple` build job)
- sign_sbom_jsf
- sign_temurin_gpg (Same job used in the traditional pipelines)
- test (Invokes the `-simpletest` job
- release (Same job used in the traditional pipelines)

### Build job (Not a pipeline)

The `-simple` build job runs on a machine with label `solaris&&buildproxy`.
From an infrastructure perspective, this is running on one of the xLinux
machines in an account `solarisbuild` which is set up with the ability to
ssh into the Solaris x64 and SPARC systems.

At the time of writing the xLinux agent that does this is
[dockerhost-azure-solarisproxy](https://ci.adoptium.net/computer/dockerhost%2Dazure%2Dsolarisproxy/)
and it is launched by connecting it to the jenkins server, not the other way
around.

The build job has a function `createMetaDataFile()`
[ref](https://github.com/adoptium/temurin-build/issues/4098#issuecomment-2654047953)
(required by the SBOM generation, and usually done by the pipeline scripts,
NOT in the build shell scripts so we have replicated it here).  It then sets
some variables and makes an `ssh` connection into the target machine to
clone temurin-build and run `make-adopt-build-farm.sh`.

One that is done, it uses `scp` to copy the contents of `workspace/target`
back to the proxy machine, creates the sha256.txt and the metadata file so
that jenkins can archive those artifacts without directly accessing the
Solaris build machine. It also creates a `filenames.txt` file of all the
filenames that it produces (required by the `-simpletest` job to identify
the filenames)

### Diagnosing build runs

In general the builds logs will look similar as before other than the
initial work to set the environment and connect to the target machine. The
bulk of the work is using the `make-adopt-build-scripts.sh` so diagnosis is
the same as before for anything in the main part of the build.

## Test job

The test job is quite different from the build job as it does not use any of
the pipelines that the traditional test jobs (the ones prefixed with `Test_` or
`Grinder`).

The new jobs are effectively just running the underlying AQA runs using
simple shell scripts to clone the AQA material and run the commands, similar
to how they are described in the
[infrastructure FAQ](https://github.com/adoptium/infrastructure/blob/master/FAQ.md#how-do-i-replicate-a-test-failure).
Note that while the `-simpletest` jobs have `SUITE` and `SUBSUITE`
parameters, these are not used and the job only runs the full set of tests.

Similer to the build job, the `-simpletest` job runs on a machine with the
label `solaris&&testproxy`. At the time of writing this is satisfied by the
single agent
[dockerhost-azure-solaristestproxy](https://ci.adoptium.net/computer/dockerhost%2Dazure%2Dsolaristestproxy/)
which is running as the user account `solaris` and runs ssh commands to the
target Solaris machines to run the tests.

The `-simpletest` job copies `/home/solaris/dotests.sh` onto the target
Solaris machine, runs the set of tests defined in the `TESTS` part of the
inline shell script in the job, and then copies the output back to the proxy
machine for archiving by jenkins.  The `dotests.sh` script is not currently
under version control.  The master copy of it lies on the machine in the
location from the previous paragraph.

The dotests.sh job acquires the appropriate tarballs from the build job by
downloading (with `curl`) the `filenames.txt` artifact, and then extracting
the filenames for the appropriate tarballs then downloading and extracting
them to a suitable location.

### Diagnosing test runs

While the jobs perform all suites together in sequence, they write the
output to a different directory under `aqa-tests/TKG/output_*` so they can
be analysed separately from the archived results.

The best way to get a quick view of the failures is to run an awk command
against the console output for the job e.g.

`curl -s https://ci.adoptium.net/job/build-scripts/job/jobs/job/jdk8u/job/jdk8u-solaris-x64-temurin-simpletest/91/consoleText | awk '/FAILED test targets:/,/TOTAL:/'`

which should give output similar to this:

```text
12:42:00  PASSED test targets:
12:42:00        jdk_lang_0 - Test results: passed: 474 
12:42:00  
12:42:00  FAILED test targets:
12:42:00        jdk_security3_0 - Test results: passed: 606; failed: 1 
12:42:00                Failed test cases: 
12:42:00                        TEST: sun/security/ssl/X509TrustManagerImpl/Entrust/Distrust.java
12:42:00
12:42:00        jdk_util_0 - Test results: passed: 675; failed: 2 
12:42:00                Failed test cases: 
12:42:00                        TEST: java/util/Currency/ValidateISO4217.java
12:42:00          TEST: java/util/TimeZone/AssureTzdataVersion.java
```

From there, the problems can be diagnosed as usual, albeit without the
assitance of the Grinder job.

### Further enhancements:

1. Put the build script, currently inlines into the `-simple` job, under version control.
2. Put the [dotests.sh script](https://github.com/adoptium/temurin-build/issues/4099#issuecomment-2622211222) under version control and pull it directly onto the target machine.
3. Enable the `SUITE` and `SUBSUITE` options on the `-simpletest` job so you don't have to run everything.
4. Perhaps have a way of executing a smaller target, similar to Grinder. At the moment to do that you have to have someone log into the machine and run it themself.
5. Currently the normal and release jobs are not separated. The release jobs should be separated.
