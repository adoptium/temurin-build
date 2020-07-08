# Build OpenJDK on Azure DevOps

## Supported Platforms and Versions

Supported Versions/Platforms:

| JDK Version    | macOS x64 | Windows x64 | Windows x86-32 |
| -------------- | --------- | ----------- | -------------- |
| jdk8u hotspot  | ❌        | ✔️          | ✔️            |
| jdk11u hotspot | ✔️        | ✔️          | ✔️            |
| jdk14u hotspot | ✔️        | ✔️          | ✔️            |
| jdk15 hotspot  | ✔️        | ✔️          | ❌            |
| jdk-tip hotspot| ✔️        | ✔️          | ❌            |


## Requirements

1. Azure DevOps Account

If you don't have an Azure DevOps organization, you can start from
[here][azdo_main]

2. Required Pipeline Variables:

    1. `JAVA_TO_BUILD`: jdk8u | jdk11u | jdk14u | jdk15u | jdk

3. Optional Pipeline Variables:

    1. `EXTRA_MAKEJDK_ANY_PLATFORM_OPTIONS`: other options in makejdk-any-platform.sh

## Quick Start

1. Create a new **Project** and you can make it either **Public** or **Private**.
   For Public project you can get 10 free Microsoft-hosted agents.
   [You can aways change the project visiblity later][azdo_make_project_public].

2. Create a new Pipeline by using an **Existing Azure Pipeline YAML file**
   and choose `.azure-devops/pipelines.yml` file.
   
   Plase set the `JAVA_TO_BUILD` variable in the review step.

3. Start the pipeline and you can download the artifacts once the jobs complete.

## Structure

1. `openjdk-pipelines.yml` is the entry point of the pipeline.

2. `build` folder contains all the stages and steps required to build OpenJDK.
   More tasks, signing and testing, etc, will be added in the future.

3. `build/build.yml` file contains all the stages.
   Currently, it contains 3 stages: macOS x64, windows x64, and windows x86-32.

4. Azure DevOps YAML step templates are used inside each steps folder (macOS, shared, windows)
   so the tasks can be **grouped together** and **reused**.

## How To Add Customized Steps

The pipeline is intended to work with minimal configuration required by the end user.
However, it is possible that you want to add or replace certain tasks.
To add a task:

1. Find out where the task belongs.
   Tasks shared by all the pipelines should be placed into the `shared` folder.

2. To prevent merge conflicts when you pull the latest changes from the upstream sources.
   It is recommended to create another YAML step template, and save it in an appropriate folder.

### Example: Overriding file name

If you need to override the default output file name, you have two options:

First, you can edit the task inside the `build/shared/before.yml` file directly.
This may add a maintenance cost over time as upstream changes may conflicts with this.

Second, you can create another YAML step template and save it to `build/shared/set_filename.yml` and add it to the `build.yml` file.

```
steps:
    - template: ./steps/shared/before.yml
    - template: ./steps/shared/set_filename.yml
    - template: ./steps/windows/before.yml
    - template: ./steps/windows/build_hotspot.yml
    - template: ./steps/shared/after.yml
```

By doing this you will not get any merge conflicts when you pull the changes from upstream.

<!--- 
Links.
--->
[azdo_main]: https://azure.microsoft.com/en-ca/services/devops/
[azdo_make_project_public]: https://docs.microsoft.com/en-us/azure/devops/organizations/public/make-project-public