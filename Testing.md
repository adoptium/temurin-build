# PR Testers

openjdk-build is an open source project, therefore, we need to ensure the the code that is being deployed to our master branch doesn't break any existing code and actually works as expected.
To achieve this level of testing, we use various jobs to compile, lint and test the code as well as running demo pipelines in a controlled sandbox environment if needs be.
The demo pipelines are colloquially known as "The PR Tester" where the others are generally just referred to as "`checkname` check".

## When they're used

All of the [test groups](#what-they-are) are executed automatically on every PR and are defined inside the [.github/workflows directory](https://github.com/adoptium/temurin-build/tree/master/.github/workflows).
These tests lint & compile the code you have altered, as well as executing full JDK builds using your code.

## What they are

There are two "groups" of tests that can be run on each PR:

- [#Linter](#Linter)
- [#Build](#Build)

The results of these jobs will appear as [GitHub Status Check Results](https://docs.github.com/en/github/administering-a-repository/about-required-status-checks) at the bottom of the PR being tested:
![Image of PR Tester Checks](./images/pr_tester_checks.png)

### Linter

This group consists of [GitHub Status Checks](https://docs.github.com/en/free-pro-team@latest/github/collaborating-with-issues-and-pull-requests/about-status-checks) run inside GitHub itself. They lint / analyse any changes you make to ensure they conform to our writing standards.

#### Super Linter

- This job downloads and runs the [Super Linter Tool](https://github.com/github/super-linter) in order to lint and compile any changes you have made to our bash scripts.
- The job will fail and inform the user in the log if there are any violations of our code or documentation standards. If you feel that some of the standards are too strict or irrelevant to your changes, please raise it in [Slack:#testing](https://adoptium.slack.com/archives/C5219G28G).

### Build

This group is a matrix of [GitHub Status Checks](https://docs.github.com/en/free-pro-team@latest/github/collaborating-with-issues-and-pull-requests/about-status-checks) run inside GitHub itself. They execute a full set of builds to various specifications, mimicking a user running a build locally

- The group collects a varied mix of java versions, operating systems and VM variants that each execute [build-farm/make-adopt-build-farm.sh](https://github.com/adoptium/temurin-build/blob/master/build-farm/make-adopt-build-farm.sh), essentially running a full JDK build as if we were setting up and testing a new Jenkins machine OR as if it was running a build locally on your machine.
- Each job is run inside a Docker container to ensure reliability between each build. For example, Linux builds use our [centos7_build_image](https://hub.docker.com/r/adoptopenjdk/centos7_build_image) Docker container.
- At the end of the build, the finished JDK artifact is archived to GitHub for you to download and peruse at your leisure (see [actions/upload-artifact#usage](https://github.com/actions/upload-artifact#usage) for more info).
- Due to GitHub ratelimiting how many status checks can be run in the space of a few minutes, these checks may take a little while to complete while they're stuck in the queue. Be patient however, as some of your changes may affect one build completely differently to another build.
