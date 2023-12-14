# Readme for Build Auto-Triage Tool

## Summary

This tool generates links to all of the latest build failures for Eclipse Temurin™ at Adoptium.

It also includes the likely cause of each failure, allowing for efficient triage.

## Details

When passed one or more jdk major versions, this script identifies the latest attempts to build Eclipse Temurin™ at
the Adoptium project, and it returns links and triage information for all the failed/aborted-state builds.

Benefits of using this script include:

- The ability to efficiently focus your time on failures that are the most important to you.
- The ability to share a community-wide view of the current build health.
- The ability to quickly identify and resolve failures.
- The ability to spot missing platforms for a specific major version (see the "Script Issues" section in the created issue/file).
- Conversely, the ability to know when you're building platforms you shouldn't be building.
- The ability to quickly identify the latest Temurin pipelines

## Instructions

bash build_autotriage.sh jdk8u jdk11u jdk17u jdk21u jdk22head

## Output

This script generates a file in Markdown format.

The output is designed to be used by a git action to populate a new GitHub issue.

## Developer tips

Developers should add the following temporary code snippet into the build-autotriage.yml file while developing a change:

```YAML
  push:
    paths:
      - '**build-autotriage.yml'
      - '**build_autotriage.sh'
      - '**autotriage_regexes.sh'
```

This should begin at the line immediately after the cron command.

This temporary change will automatically run the GitHub action every time you push a change set, allowing easy testing.

For this to work, you need to have GitHub actions and issues enabled in your repository.

*Make sure to remove this before pushing your change upstream.*

## Associated file breakdown

- build_autotriage.sh: This is the main script, containing most of the logic.
- autotriage_regexes.sh: This contains all of the regular expressions used to identify failures.
- build-autotriage.yml: This is the git action that runs the main script and generates an issue from the output.
