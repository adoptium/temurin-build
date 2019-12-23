# Build OpenJDK on Azure DevOps

## Support Platforms and Versions

Support Versions/Platforms:

| JDK Version    | macOS x64 | Windows x64 | Windows x86-32 |
| -------------- | --------- | ----------- | -------------- |
| jdk8u hotspot  | ✔️        | ✔️          | ✔️             |
| jdk11u hotspot | ✔️        | ✔️          | ✔️             |
| jdk13u hotspot | ✔️        | ✔️          | ✔️             |
| jdk hotspot    | ✔️        | ✔️          | 🟡             |


*: failure may occure when build **jdk hotspot**


## Requirements

1. Azure DevOps Account

If you don't have an Azure DevOps organization, you can start from
[here][azdo_main]

2. Required Pipeline Variables:

    1. `JAVA_TO_BUILD`: jdk8u | jdk11u | jdk13u | jdk

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

The pipeline works out of the box and you have little things need to be configured.
However, it is possible that you want to add or replace certain tasks.
And The rule of thumb is:

1. Find out where the task belong.
   If it is shared by all the pipelines then `shared` folder is the place to go.

2. To prevent merge conflict when you pull the latest changes from the upstream.
   It is recommended to create another YAML step templates, and find a proper place to place it.
   
   Here is an example. If you need to override the default output file name. You have two options.

   First, you can edit the task inside the `build/shared/pre.ymal` file directly.
   But you may have to spend some time down the road if the upstream changes.

   Second, you can create another YAML step template, and save it to `build/shared/set_filename.yml`.
   And just need to add it to the `build.yml` file.

   ```
   steps:
      - template: ./steps/shared/pre.yml
      - template: ./steps/shared/set_filename.yml
      - template: ./steps/windows/pre.yml
      - template: ./steps/windows/build_hotspot.yml
      - template: ./steps/shared/post.yml
   ```

   By doing this you will not get any merge conflic when you pull the changes from upstream.

<!--- 
Links.
--->
[azdo_main]: https://azure.microsoft.com/en-ca/services/devops/
[azdo_make_project_public]: https://docs.microsoft.com/en-us/azure/devops/organizations/public/make-project-public