# PR Testers

openjdk-build is an open source project, therefore, we need to ensure the the code that is being deployed to our master branch doesn't break any existing code and actually works as expected. To achieve this level of testing, we use two jobs to compile the code and run demo pipelines in a controlled sandbox environment (colloquially known as "the PR tester").

## When they're used

Every new pull request to this repository should have the PR tester run on it at least once to verify the changes don't break anything significant (documentation changes being excluded from this rule). The two jobs will appear as as [GitHub Status Checks](https://docs.github.com/en/github/administering-a-repository/about-required-status-checks) at the bottom on the PR being tested:
![Image of PR Tester Checks](./images/pr_tester_checks.png)

## How they're used

The PR testers have their own admin and white lists attached to them on Jenkins.
If you are on the whitelist or admin list, the PR tester will run against your PR whenever you make one and it will also allow you access to various commands you can run on your own PR or on someone else's:

### `run tests`

- Executes new [openjdk-build-compile-groovy](#openjdk-build-compile-groovy) and [openjdk-build-pr-tester](#openjdk-build-pr-tester) jobs against this PR. These jobs will populate the GitHub status checks field as described above. Please be patient as the [tester does not run concurrently yet](https://github.com/AdoptOpenJDK/openjdk-build/issues/2053) so it may take some time to execute the jobs if there is a long job queue. You can track the progress of it in [Jenkins](https://ci.adoptopenjdk.net/job/build-scripts-pr-tester/) OR look at the status check message:

  - Example of a PR that is in the queue:
  ![Image of queued tester](./images/pr_tester_queued.png)
  - One that is at the front of the queue and currently being tested:
  ![Image of building tester](./images/pr_tester_building.png)

- When the tester is done, it will return a response comment to the PR with feedback on the testing similar to the following:
![Image of test result](./images/pr_tester_result.png)

- The message will vary depending on the result of the test. Please remember however, that failed tests may be due to existing problems in the nightly builds. If you're unsure if the tests failed because of your changes or not, check our [issue board](https://github.com/AdoptOpenJDK/openjdk-build/issues) and our [triage doc](https://docs.google.com/document/d/1vcZgHJeR8rW8U8OD23Uob7A1dbLrtkURZUkinUp7f_w/edit?usp=sharing) for the existing error. If your job was aborted, check the log to see who aborted it.

  - 🟢**SUCCESS** 🟢 All the tests and jobs passed, congratulations!
  - 🟠**FAILURE** 🟠 Some of the tests or jobs failed OR the job was aborted. Check the link in the field at the bottom of the PR for the job link to see exactly where it went wrong.
  - 🔴**ERROR** 🔴 Something more serious went wrong with the tester itself. Please raise an issue with a link to the job, the error encountered and your PR that caused it (again, you can use the link at the bottom to see exactly what happened).

- NOTE: [openjdk-build-compile-groovy](#openjdk-build-compile-groovy) does not produce these status messages for the reasons stated in [this issue](https://github.com/AdoptOpenJDK/openjdk-build/issues/2055#issuecomment-688802783).

### `add to whitelist`

- **ADMIN COMMAND ONLY**
- This command adds a new user to the whitelist but not to the admin list. As of typing this, there is [currently no way to check if you have the correct permissions](https://github.com/AdoptOpenJDK/openjdk-build/issues/2055#issuecomment-688801090).
- Should you want to be promoted to the whitelist, please contact one of the admins through [#infrastructure](https://adoptopenjdk.slack.com/archives/C53GHCXL4) in Slack.
- Should you want the up to date admin or white list, check the configuration of the [openjdk-build-pr-tester](https://ci.adoptopenjdk.net/job/build-scripts-pr-tester/job/openjdk-build-pr-tester/) job. If you don't have the permissions to view the configuration, then try out the `add to whitelist` and `run tests` commands on a test PR to see if they work.

## What they are

### openjdk-build-compile-groovy

**Seen in the PR Status Checks as `Compile Groovy`, the job is located [here](https://ci.adoptopenjdk.net/job/build-scripts-pr-tester/job/openjdk-build-compile-groovy/).**

- A relatively small job, this runs our groovy compiler, checking over the repository to ensure any new code successfully runs. Should you encounter a compile error that is caused by a missing function or error similar to the one below, then you should update our [test doubles & stubs](https://github.com/AdoptOpenJDK/openjdk-build/tree/master/pipelines/src/main/groovy) that we use to run these tests and emulate a live jenkins environment ([link to example](https://github.com/AdoptOpenJDK/openjdk-build/commit/27064de6cb4818a8a958476784d2d9b5cb92c55d#diff-c6a79675da9c67a69aa3ee6e26748793)).

```groovy
    prTester/pr_test_pipeline.groovy: 99: [Static type checking] - Cannot find matching method PullRequestTestPipeline#downstreamCommitStatus(groovy.lang.Closure). Please check if the declared type is correct and if the method exists.
     @ line 99, column 33.
                                       downstreamCommitStatus {
```

- The job also runs our [groovy testing suite](https://github.com/AdoptOpenJDK/openjdk-build/tree/master/pipelines/src/test/groovy). The various tests in this directory ensure that our jenkins library classes return the correct information.

- **If you are making any changes to any of the following classes, we strongly recommended you update the tests to conform to your changes (adding new ones if needs be!):**

  - [ParseVersion.groovy](https://github.com/AdoptOpenJDK/openjdk-build/blob/master/pipelines/library/src/ParseVersion.groovy)
  - [IndividualBuildConfig.groovy](https://github.com/AdoptOpenJDK/openjdk-build/blob/master/pipelines/library/src/common/IndividualBuildConfig.groovy)
  - [MetaData.groovy](https://github.com/AdoptOpenJDK/openjdk-build/blob/master/pipelines/library/src/common/MetaData.groovy)
  - [VersionInfo.groovy](https://github.com/AdoptOpenJDK/openjdk-build/blob/master/pipelines/library/src/common/VersionInfo.groovy)

- As an example of this in action, the output of [one such test](https://github.com/AdoptOpenJDK/openjdk-build/blob/master/pipelines/src/test/groovy/VersionParsingTest.groovy#L60-L68) can be seen below:

```groovy
VersionParsingTest > parsesJava11NightlyString() STANDARD_OUT
    =JAVA VERSION OUTPUT=
    openjdk version "11.0.3" 2019-04-16
    OpenJDK Runtime Environment AdoptOpenJDK (build 11.0.3+9-201903122221)
    OpenJDK 64-Bit Server VM AdoptOpenJDK (build 11.0.3+9-201903122221, mixed mode)
    =/JAVA VERSION OUTPUT=
    matched
    11.0.3+9-201903122221
```

### openjdk-build-pr-tester

- **Seen in the PR Status Checks as `pipeline-build-check`, the job is located [here](https://ci.adoptopenjdk.net/job/build-scripts-pr-tester/job/openjdk-build-pr-tester/)**

- This job runs the a set of [sandbox pipelines](https://ci.adoptopenjdk.net/job/build-scripts-pr-tester/job/build-test/) to test the changes that you have made to our codebase. It's executed by a custom groovy script from the job itself:

```groovy
node("master") {
    //String ghprbPullId = "953"
    //String branch = "pull/${ghprbPullId}"

    //String ghprbActualCommit = "e309f0c8c10df9515770d5d8ec37daeddbbe7a15"
    String branch = "${ghprbActualCommit}"
    String url = 'https://github.com/AdoptOpenJDK/openjdk-build'

    checkout([$class: 'GitSCM', branches: [[name: branch]], userRemoteConfigs: [[refspec: " +refs/pull/*/head:refs/remotes/origin/pr/*/head +refs/heads/master:refs/remotes/origin/master +refs/heads/*:refs/remotes/origin/*",
    url: url]]])

    Closure prTest = load "pipelines/build/prTester/pr_test_pipeline.groovy"

    prTest(
        branch,
        currentBuild,
        this,
        url
        ).runTests()
}
```

- That groovy script executes our [pr_test_pipeline](https://github.com/AdoptOpenJDK/openjdk-build/blob/master/pipelines/build/prTester/pr_test_pipeline.groovy) which is the main base file for this job.
