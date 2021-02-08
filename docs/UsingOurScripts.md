# Custom environment setting up guide

Adopt have setup their build scripts so that you can plug in configuration files and scripts you have changed while not having to duplicate and maintain Adopt's entire codebase separately. This may seem complicated at first but it's pretty simple once you get the hang of the process.

## defaults.json

This file contains the default constants and paths used in the build scripts for whichever repository it is located in. As an example, Adopt's `defaults.json` file is located [here](https://github.com/AdoptOpenJDK/openjdk-build/blob/master/pipelines/defaults.json). If you're unsure of any of the fields, see Adopt's example map below:

```json
{
    // Git repository details
    "repository"             : {
        // Git Url of the current repository.
        "url"                : "https://github.com/AdoptOpenJDK/openjdk-build.git",
        // Git branch you wish to use when running the scripts
        "branch"             : "master"
    },
    // Jenkins server details
    "jenkinsDetails"         : {
        // The base URL of the server, usually this is where you would end up if you opened your server from a webpage
        "rootUrl"            : "https://ci.adoptopenjdk.net",
        // Jenkins directory where jobs will be generated and run
        "rootDirectory"      : "build-scripts"
    },
    // Jenkins job dsl template paths (relative to this repository root)
    "templateDirectories" : {
        // Downstream job template (e.g. jdk8u-linux-x64-hotspot)
        "downstream"         : "pipelines/build/common/create_job_from_template.groovy",
        // Upstream job template (e.g. openjdk8-pipeline)
        "upstream"           : "pipelines/jobs/pipeline_job_template.groovy",
        // Weekly job template (e.g. weekly-openjdk8-pipeline)
        "weekly"             : "pipelines/jobs/weekly_release_pipeline_job_template.groovy"
    },
    // Job configuration file paths (relative to this repository root)
    "configDirectories"      : {
        // Build configs directory containing node details, os, arch, testlists, etc
        "build"              : "pipelines/jobs/configurations",
        // Nightly configs directory containing execution frequency, weekly tags, platforms to build.
        "nightly"            : "pipelines/jobs/configurations",
        // Bash platform script directory containing jdk downloading and toolchain setups.
        "platform"           : "build-farm/platform-specific-configurations"
    },
    // Job script paths (relative to this repository root)
    "scriptDirectories"      : {
        // Upstream scripts directory containing the 1st files that are executed by the openjdkx-pipeline jobs.
        "upstream"           : "pipelines/build",
        // Upstream script file containing the 1st script that is executed by the weekly-openjdk8-pipeline jobs.
        "weekly"             : "pipelines/build/common/weekly_release_pipeline.groovy",
        // Downstream script file containing the 1st script that is executed by the jdkx-platform-arch-variant jobs.
        "downstream"         : "pipelines/build/common/kick_off_build.groovy",
        // Base script file containing the 2nd script that is executed by the pipeline_jobs_generator_jdkxx jobs
        "regeneration"       : "pipelines/build/common/config_regeneration.groovy",
        // Base PR tester file script file containing the 2nd script that is executed by the pipeline_jobs_generator_jdkxx jobs
        "tester"             : "pipelines/build/prTester/pr_test_pipeline.groovy"
    },
    // Job base file (the main file which is called after the 1st setup script file) paths (relative to this repository root)
    "baseFileDirectories": {
        // Upstream pipeline file script containing the 2nd script that is executed by the openjdkx-pipeline jobs
        "upstream"           : "pipelines/build/common/build_base_file.groovy",
        // Upstream pipeline file script containing the 2nd script that is executed by the jdkx-platform-arch-variant jobs
        "downstream"         : "pipelines/build/common/openjdk_build_pipeline.groovy"
    },
    // Script to import the adopt groovy class library (relative to this repository root)
    "importLibraryScript"    : "pipelines/build/common/import_lib.groovy"
}
```

### How do I know which parameter the jenkins job will use?

The scripts have been designed with a set hierarchy in mind when choosing which parameter to use:

```md
1. JENKINS PARAMETERS (highest priority, args entered here will be what the build scripts use over everything else)
2. USER JSON (medium priority, args entered here will be used when a jenkins parameter isn't entered)
3. ADOPT JSON (final priority, when jenkins parameters AND a user json arg can't be validated, the script will checkout to this repository and use Adopt's defaults json (linked above))
```

The `ADOPT JSON` level is only used for files and directories. Other parameters (`JOB_ROOT`, `JENKINS_BUILD_ROOT`, etc) only use the first two levels.

As an example, take a look at the [build-pipeline-generator](https://ci.adoptopenjdk.net/job/build-scripts/job/utils/job/build-pipeline-generator/) `SCRIPT_FOLDER_PATH` parameter:

![Image of the SCRIPT_FOLDER_PATH parameter in jenkins](images/scriptFolderParam.png)
The script will use whatever has been entered into the parameter field unless it has been left empty, in which case it will use whatever is in the user's `defaults.json['scriptDirectories']['upstream']` attribute.

It will then evaluate the existence of that directory in the user's repository and, if it fails to find one, will checkout to AdoptOpenJDK/openjdk-build and use Adopt's `defaults.json` (the console log will warn the user of this occuring):

```
00:13:31  [WARNING] pipelines/build/common/weekly_release_pipeline.groovy does not exist in your chosen repository. Updating it to use Adopt's instead
```

NOTE: For the defaults that are paths to directories, the scripts will search for files of the same name as Adopt's. Custom named files are not currently supported (so for `defaults.json['configDirectories']['platform']`, all of the filenames in the specified folder need to be the same as [Adopt's](https://github.com/AdoptOpenJDK/openjdk-build/tree/master/build-farm/platform-specific-configurations) or the script will fail to pick up the user's config's and will use Adopt's instead).

### This is great, but how do I add new defaults?

Create a openjdk-build PR that adds the new defaults in for what they would be for Adopt. Don't forget to update Adopt's [RepoHandlerTest.groovy](https://github.com/AdoptOpenJDK/openjdk-build/blob/master/pipelines/src/test/groovy/RepoHandlerTest.groovy) and [fakeDefaults.json](https://github.com/AdoptOpenJDK/openjdk-build/blob/master/pipelines/src/test/groovy/fakeDefaults.json), as well as any jenkins jobs if needs be (if you don't have configuration access, ask in Slack#build for assistance). Then update any scripts that will need to handle the new default, you will likely need to do a bit of searching through the objects mentioned in Adopt's `defaults.json` to find where Adopt's scripts will need changing.

Once it has been approved and merged, update your scripts and/or jenkins jobs to handle the new default and you're done!

## Starting from scratch

1. Create a (preferably) public repository with whatever scripts/configs you have altered. You don't need to place them in the same place as where Adopt's ones are, but they should have the same name. Currently, the list of supported files (replacing `x` with the JDK version number you want to alter, `(u)` is optional) you can modify are:

    - [pipelines/build/regeneration/build_pipeline_generator.groovy](https://github.com/AdoptOpenJDK/openjdk-build/blob/master/pipelines/build/regeneration/build_pipeline_generator.groovy) - Main upstream generator files. This is what the [build-pipeline-generator jenkins job](https://ci.adoptopenjdk.net/job/build-scripts/job/utils/job/build-pipeline-generator/) executes on build, generating the [upstream jobs](https://ci.adoptopenjdk.net/job/build-scripts/).
    - [pipelines/jobs/pipeline_job_template.groovy](https://github.com/AdoptOpenJDK/openjdk-build/blob/master/pipelines/jobs/pipeline_job_template.groovy) - Upstream jobs dsl. This is the dsl job framework of the [openjdkxx-pipeline downstream jobs](https://ci.adoptopenjdk.net/job/build-scripts).
    - [pipelines/jobs/weekly_release_pipeline_job_template.groovy](https://github.com/AdoptOpenJDK/openjdk-build/blob/master/pipelines/jobs/weekly_release_pipeline_job_template.groovy) - Upstream jobs dsl. This is the dsl job framework of the [weekly-openjdkxx-pipeline downstream jobs](https://ci.adoptopenjdk.net/job/build-scripts).
    - [pipelines/build/openjdkx_pipeline.groovy](https://github.com/AdoptOpenJDK/openjdk-build/blob/master/pipelines/build/openjdk8_pipeline.groovy) - Main upstream script files. These are what the [openjdkx-pipeline jenkins jobs](https://ci.adoptopenjdk.net/job/build-scripts/job/openjdk8-pipeline/) execute on build.
    - [pipelines/build/common/import_lib.groovy](https://github.com/AdoptOpenJDK/openjdk-build/blob/master/pipelines/build/common/import_lib.groovy) - Class library import script. This imports [Adopt's classes](https://github.com/AdoptOpenJDK/openjdk-build/tree/master/pipelines/library/src) used in the groovy scripts.
    - [pipelines/build/common/build_base_file.groovy](https://github.com/AdoptOpenJDK/openjdk-build/blob/master/pipelines/build/common/build_base_file.groovy) - Base upstream script file that's called from `pipelines/build/openjdkx_pipeline.groovy`, setting up the [downstream build JSON](https://github.com/AdoptOpenJDK/openjdk-build/blob/master/pipelines/library/src/common/IndividualBuildConfig.groovy) for each downstream job and executing them.
    - [pipelines/jobs/configurations/jdkx(u).groovy](https://github.com/AdoptOpenJDK/openjdk-build/blob/master/pipelines/jobs/configurations/jdk8u.groovy) - Upstream nightly config files. These define the job schedules, what platforms are instantiated on a nightly build and what tags are used on the weekend releases.
    - [pipelines/jobs/configurations/jdkx(u)_pipeline_config.groovy](https://github.com/AdoptOpenJDK/openjdk-build/blob/master/pipelines/jobs/configurations/jdk8u_pipeline_config.groovy) - Downstream build config files, docs for this are [in progress](https://github.com/AdoptOpenJDK/openjdk-build/issues/2129).
    - [pipelines/build/common/kick_off_build.groovy](https://github.com/AdoptOpenJDK/openjdk-build/blob/master/pipelines/build/common/kick_off_build.groovy) - Main downstream scripts file. These are what the [jdkx(u)-os-arch-variant jenkins jobs](https://ci.adoptopenjdk.net/job/build-scripts/job/jobs/job/jdk8u/) execute on build.
    - [pipelines/build/common/openjdk_build_pipeline.groovy](https://github.com/AdoptOpenJDK/openjdk-build/blob/master/pipelines/build/common/openjdk_build_pipeline.groovy) - Base downstream script file. This contains most of the functionality for Adopt's downstream jobs (tests, installers, bash scripts, etc).
    - [pipelines/build/regeneration/jdkx_regeneration_pipeline.groovy](https://github.com/AdoptOpenJDK/openjdk-build/blob/master/pipelines/build/regeneration/jdk8_regeneration_pipeline.groovy) - Main downstream generator files. These are what the [pipeline_jobs_generator_jdk8u jenkins jobs](https://ci.adoptopenjdk.net/job/build-scripts/job/utils/job/pipeline_jobs_generator_jdk8u/) execute on build, generating the [downstream jobs](https://ci.adoptopenjdk.net/job/build-scripts/job/jobs/) via `pipelines/build/common/config_regeneration.groovy` (see below).
    - [pipelines/build/common/config_regeneration.groovy](https://github.com/AdoptOpenJDK/openjdk-build/blob/master/pipelines/build/common/config_regeneration.groovy) - Base downstream script file. These are what the [pipeline_jobs_generator_jdk8u jenkins jobs](https://ci.adoptopenjdk.net/job/build-scripts/job/utils/job/pipeline_jobs_generator_jdk8u/) execute after `jdkx_regeneration_pipeline.groovy`, calling the dsl template `pipelines/build/common/create_job_from_template.groovy`.
    - [pipelines/build/common/create_job_from_template.groovy](https://github.com/AdoptOpenJDK/openjdk-build/blob/master/pipelines/build/common/create_job_from_template.groovy) - Downstream jobs dsl. This is the dsl job framework of the [downstream jobs]((https://ci.adoptopenjdk.net/job/build-scripts/job/jobs/)).
2. Create a User JSON file containing your default constants that the build scripts will use (see [#the defaults.json](#defaults.json)). Delete any of Adopt's files and directories that you have not altered in step 1.
3. Copy the [build-pipeline-generator](https://ci.adoptopenjdk.net/job/build-scripts/job/utils/job/build-pipeline-generator/) and [pipeline_jobs_generator_jdk8u](https://ci.adoptopenjdk.net/job/build-scripts/job/utils/job/pipeline_jobs_generator_jdk8u/) jobs to your Jenkins instance (replace `jdk8u` with whichever version you intend to build, there should be one job for each jdk version).
4. Execute the copied `build-pipeline-generator`. Make sure you have filled in the parameters that are not covered by your `defaults.json` (e.g. `DEFAULTS_URL`, `CHECKOUT_CREDENTIALS`). You should now see that the nightly and weekly pipeline jobs have been successfully created in whatever folder was entered into `JOB_ROOT`
5. Execute the copied `pipeline_jobs_generator_jdkxx` jobs. Again, make sure you have filled in the parameters that are not covered by your `defaults.json`. You should now see that the `jobs/jdkxx-platform-arch-variant` jobs have been successfully created in whatever folder was entered into `JOB_ROOT`

Congratulations! You should now be able to run Adopt's scripts inside your own Jenkins instance.
