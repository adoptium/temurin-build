# Contributing to temurin-build

Thanks for your interest in this project.
You can contribute to this project in many different ways.  **We appreciate all kinds of help, so thank you!**

## Project description

temurin-build is a project that contains the shell build scripts to produce Temurin binaries

* https://github.com/adoptium/temurin-build

## Developer resources

The project maintains the following source code repositories

* https://github.com/adoptium/temurin-build

## Eclipse Contributor Agreement

Before your contribution can be accepted by the project team contributors must
electronically sign the Eclipse Contributor Agreement (ECA).

* http://www.eclipse.org/legal/ECA.php

Commits that are provided by non-committers must have a Signed-off-by field in
the footer indicating that the author is aware of the terms by which the
contribution has been provided to the project. The non-committer must
additionally have an Eclipse Foundation account and must have a signed Eclipse
Contributor Agreement (ECA) on file.

For more information, please see the Eclipse Committer Handbook:
https://www.eclipse.org/projects/handbook/#resources-commit

## Contact

Contact the Eclipse Foundation Webdev team via webdev@eclipse-foundation.org.

## Issues and Enhancements

Please let us know via our [issue tracker](https://github.com/adoptium/temurin-build/issues) if you find a problem, even if you don't have a fix for it.  The ideal issue report should be descriptive, and where possible include the steps we can take to reproduce the problem for ourselves.

If you have a proposed fix for an issue, or an enhancement you would like to make to the code please describe it in an issue, then send us the code as a [Github pull request](https://help.github.com/articles/about-pull-requests) as described below.

## Pull requests

We use GitHub's pull requests (PRs) as the primary way to accept contributions to the project.  That means we assume you have followed the usual procedure and forked the project repository, cloned your fork, created a new branch for your contribution, and pushed one or more commits to your branch.  There are many [on-line guides](https://guides.github.com/activities/forking/) that will help you with these steps.

Consider whether the project documentation or tests also need updating as part of your change, and make that part of the same logical issue and PR.  Open your PR against the master branch of the project.

To keep track of [the pull requests we are managing](https://github.com/adoptium/temurin-build/pulls) we ask that you follow these guidelines for structuring the pull request title and comment.

### Pull request title

Use a descriptive title, and if it relates to an issue in our tracker please reference which one.  If the PR is not intended to be merged you should prefix the title with "[WIP]" which indicates it is still Work In Progress.  For example, you may wish to send the PR in for an early review as you work through it.

### Pull request comment

The PR comment should be formed by a one-line subject, followed by one line of white space, and one or more descriptive paragraphs, each separated by one line of white space. All of them should be finished by a dot.

Where your PR fixes an issue, it should include a reference to the issue's identifier in the first line of the commit comment.  The comment should provide enough information for a reviewer to understand the changes and their relation to the rest of the code.

### Licensing and Developer certificate of origin

When you submit any copyrighted material to the project via a pull request, issue tracker, or any other means, you agree to license the material under [the project's open source license](https://github.com/adoptium/temurin-build/blob/master/LICENSE), and warrant that you have the legal authority to do so, whether or not you state this explicitly.

We ask that you include a line similar to the following as part of your pull request comment or individual commit comments:

```git
DCO 1.1 Signed-off-by: Random J Developer
```

“DCO” stands for “Developer Certificate of Origin,” and refers to [the same text used in the Linux Kernel community](https://elinux.org/Developer_Certificate_Of_Origin).  Of course, you should replace "Random J Developer" by your own real name.

By adding this simple comment, you are telling the community that you wrote the code you are contributing, or you have the right to pass on the code that you are contributing.

> Tip: You can use `git commit -s ...` or configure a git `commit.template` to include the sign-off statement in your commit messages automatically.

### Source file headers

All the project's source files must start with a comment, as near to the top of the file as practical, that includes a reference to [the project license](https://github.com/adoptium/temurin-build/blob/master/LICENSE).  Take a look at some existing files to see how we do that, and if there are any questions just ask. In some cases, such as small, trivial files, or source files generated by tooling we don't reference the license again, but it still applies wherever the file contains copyrightable material.

We don't place explicit copyright statements in the project source files.  The project comprises many distinct pieces of code, spread across numerous source files, and authored by a variety of individuals.  Managing copyright statements is unproductive and [can lead to confusion and contention around the edge cases](https://opensource.com/law/14/n2/copyright-statements-source-files).  Rather we utilize [the NOTICE file](https://github.com/adoptium/temurin-build/blob/master/NOTICE) mechanism as a way to acknowledge copyright broadly where there is a valid reason to do so.

Finally, for similar reasons to avoiding individual copyright statements, we don't maintain `@author` tags in source files.  There are good arguments to suggest that [author tags discourage open contribution](https://producingoss.com/en/managing-volunteers.html#territoriality), and we depend upon Git to maintain that information for the project.

### Ensuring high quality

If you're changing a shellscript, please make sure you run [shellcheck](https://github.com/koalaman/shellcheck) before submitting your PR. This will also run in a GitHub check titled `Linter` to ensure you comply to our coding style guidelines (alongside a lot of other linters for different formats).

After we receive your pull request our [GitHub Checks](https://github.com/adoptium/temurin-build/tree/master/.github/workflows) will test your changes.
If you're making any changes to our groovy files, you'll be more interested in our [pr-tester](https://ci.adoptopenjdk.net/view/build-tester/job/build-scripts-pr-tester/job/openjdk-build-pr-tester/) jenkins job which executes a set of test pipelines in a semi-live environment. Watch for the results posted as a comment to the PR, investigate and fix any failures.
Please see the [Testing.md](Testing.md) for more information on any of this.

Fixes can simply be pushed to the same branch from which you opened your pull request. GitHub will automatically re-test when new commits are pushed and update the results.

### Reviews and merge conflicts

After your PR has passed the automated testing it will be reviewed by other developers.  Comments on the changes and suggested modifications are encouraged from anybody, especially committers.  Please keep all comments focused, polite, and technical.

You may consider seeking explicit feedback from a contributor who has already worked on the code being changed.

> Tip: Use git's blame function to see who changed the code last, then ask them to be a reviewer.

Any reviewer can indicate that a change looks suitable for merging with a comment such as: “I think this patch looks good” or "this fixes the issue for me"; and we use the [LGTM](https://en.wiktionary.org/wiki/LGTM) convention for indicating the strongest level of technical sign-off on a PR.  When a committer comments with "LGTM" they specifically mean “I’ve looked at this patch thoroughly and take as much responsibility as if I wrote it myself”.

Sometimes, other changes will be merged ahead of yours which cause a conflict with your pull request’s changes. The PR cannot be merged until the conflict is resolved.  As a PR author it is your responsibility to resolve the conflicts and keep the PR up to date.  To facilitate this, try to be responsive to the review discussion rather than let days pass between replies.

Again, **thank you** for contributing to the project!
