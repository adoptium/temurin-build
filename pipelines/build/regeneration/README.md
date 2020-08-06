# Job Regenerator
To enable concurrent pipeline builds (i.e. submitting two pipelines in parralel), we have implemented a "job regeneration" system for each JDK version. 

# Intro
All of our [pipelines](https://ci.adoptopenjdk.net/job/build-scripts/) make use of [downstream jobs](https://ci.adoptopenjdk.net/job/build-scripts/job/jobs/) to build Adopt's JDK's. In short, the jobs are created in the pipelines with a set of configurations passed down to them. To create these jobs, we utilise a plugin called [job dsl](https://github.com/jenkinsci/job-dsl-plugin) to create a `dsl` file for each downstream job, containing the configurations, node label, etc. 

In the past, we created these dsl's in the [pipeline files](https://github.com/AdoptOpenJDK/openjdk-build/tree/master/pipelines/build). So each time we wanted to create a downstream job, we would create all of the job dsl's that were possible for the pipeline and pick the one that we needed. Not only was this resource intensive and slow, but it also meant that concurrent builds were impossible due to the risk of one build's dsl's overwritting anothers. This is why we have created pipeline job generators to create the dsl's for the pipelines to use, instead of creating them in the pipeline jobs.

The job regenerators are essentially downstream job makers. They pull in the [targetConfigurations](https://github.com/AdoptOpenJDK/openjdk-build/tree/master/pipelines/jobs/configurations) and build the job DSL's for each possible downstream job. The pipelines can use these job dsl's to create their downstream jobs since they are created in the same node as them (the master one). This way, each of the pipelines has a fresh dsl each time, no matter how many builds are running at once.

# Where are they?
They are stored in the [utils](https://ci.adoptopenjdk.net/job/build-scripts/job/utils/) folder of our jenkins server. The jobs themselves are called `pipeline_jobs_generator_jdk11u`, `pipeline_jobs_generator_jdk8u`, etc. NOTE: When the JDK HEAD updates, these jobs will need to be updated too (see [RELEASING.md](https://github.com/AdoptOpenJDK/openjdk-build/blob/master/RELEASING.md#steps-for-every-version)) for how to do so.

# How do they work?
There are three stages for each job regenerator. 
- Execute the top level job: 
  - The jobs themselves are executed by Github Push on this repository. Each time there is a commit, all the pipeline regenerators are kicked off. This is so any potential changes to the [buildConfigurations](https://github.com/AdoptOpenJDK/openjdk-build/tree/master/pipelines/jobs/configurations) and [targetConfigurations](https://github.com/AdoptOpenJDK/openjdk-build/tree/master/pipelines/jobs/configurations) are taken into account when creating a job dsl for each downstream job.
  - Each of the jobs executes it's corresponding [regeneration](https://github.com/AdoptOpenJDK/openjdk-build/tree/master/pipelines/build/regeneration) file, passing down it's version, targeted OS/ARCH/VARIANT and specific build configurations to the main [config_regeneration](https://github.com/AdoptOpenJDK/openjdk-build/blob/master/pipelines/build/common/config_regeneration.groovy) file.
- Check if the corresponding pipeline is in progress: 
  - Since we want to potentially avoid overwritting the job dsl's of any pipelines in progress, we use the [jenkins api](https://ci.adoptopenjdk.net/api/) to verify that there are no pipelines of that version queued or running. If there are, the job regenerator sleeps for 15mins and checks again afterwards. If not, it moves onto the next step.
- Regenerate the downstream jobs, one at a time: 
  - The regenerator then iterates through the keys in the `targetConfigurations` (e.g. [jdk11u.groovy](https://github.com/AdoptOpenJDK/openjdk-build/blob/master/pipelines/jobs/configurations/jdk11u.groovy)), which are the same keys used in the `buildConfiguration` file. After parsing each variant in them and going through various error handling stages, the job name and folder path is constructed which is the bare minimum that the job dsl needs to be created. We only need the bare minimum as the pipelines will overwrite most the configs when they run.
  - The job dsl for that downstream job is constructed and that job is then, successfully regenerated. The result is somewhat similar to this:
```
[INFO] Querying adopt api to get the JDK-Head number
[Pipeline] library
Loading library openjdk-jenkins-helper@master
Examining AdoptOpenJDK/openjdk-jenkins-helper
Attempting to resolve master as a branch
Resolved master as branch master at revision 3e6da943be88a2bcdff335cdb93d4baf1a7555a7
using credential 8dfb669c-96d7-4960-aa2d-6059651eea96
 > git rev-parse --is-inside-work-tree # timeout=10
Fetching changes from the remote Git repository
 > git config remote.origin.url https://github.com/AdoptOpenJDK/openjdk-jenkins-helper.git # timeout=10
Fetching without tags
Fetching upstream changes from https://github.com/AdoptOpenJDK/openjdk-jenkins-helper.git
 > git --version # timeout=10
using GIT_ASKPASS to set credentials Github BOT PWD
 > git fetch --no-tags --force --progress -- https://github.com/AdoptOpenJDK/openjdk-jenkins-helper.git +refs/heads/master:refs/remotes/origin/master # timeout=10
Checking out Revision 3e6da943be88a2bcdff335cdb93d4baf1a7555a7 (master)
 > git config core.sparsecheckout # timeout=10
 > git checkout -f 3e6da943be88a2bcdff335cdb93d4baf1a7555a7 # timeout=10
Commit message: "Merge pull request #32 from M-Davies/api_user_agent"
 > git rev-list --no-walk 3e6da943be88a2bcdff335cdb93d4baf1a7555a7 # timeout=10
[Pipeline] echo
[INFO] This IS JDK-HEAD. javaToBuild is jdk.
[Pipeline] echo
[INFO] Regenerating: x64Mac
[Pipeline] echo
[INFO] Regenerating variant x64Mac: hotspot...
[Pipeline] echo
[INFO] FOUND MATCH! buildConfiguration key: x64Mac and config file key: x64Mac
[Pipeline] echo
[INFO] build name: build-scripts/jobs/jdk/jdk-mac-x64-hotspot
[Pipeline] step
Processing DSL script pipelines/build/common/create_job_from_template.groovy
Existing items:
    GeneratedJob{name='build-scripts/jobs/jdk'}
    GeneratedJob{name='build-scripts/jobs/jdk/jdk-mac-x64-hotspot'}
Unreferenced items:
    GeneratedJob{name='build-scripts/jobs/jdk/jdk-aix-ppc64-hotspot'}
    GeneratedJob{name='build-scripts/jobs/jdk/jdk-aix-ppc64-openj9'}
    GeneratedJob{name='build-scripts/jobs/jdk/jdk-linux-aarch64-hotspot'}
    GeneratedJob{name='build-scripts/jobs/jdk/jdk-linux-aarch64-openj9'}
    GeneratedJob{name='build-scripts/jobs/jdk/jdk-linux-ppc64le-hotspot'}
    GeneratedJob{name='build-scripts/jobs/jdk/jdk-linux-ppc64le-openj9'}
    GeneratedJob{name='build-scripts/jobs/jdk/jdk-linux-s390x-hotspot'}
    GeneratedJob{name='build-scripts/jobs/jdk/jdk-linux-s390x-openj9'}
    GeneratedJob{name='build-scripts/jobs/jdk/jdk-linux-x64-hotspot'}
    GeneratedJob{name='build-scripts/jobs/jdk/jdk-linux-x64-openj9'}
    GeneratedJob{name='build-scripts/jobs/jdk/jdk-mac-x64-openj9'}
    GeneratedJob{name='build-scripts/jobs/jdk/jdk-windows-x64-hotspot'}
    GeneratedJob{name='build-scripts/jobs/jdk/jdk-windows-x64-openj9'}
[Pipeline] echo
[SUCCESS] Regenerated configuration for job build-scripts/jobs/jdk/jdk-mac-x64-hotspot
```

# Build Pipeline Generator
This generator generates the [top level](https://ci.adoptopenjdk.net/job/build-scripts/) pipeline jobs. It works by iterating through the config files, defining a job dsl configuration for each version that has a version config file. It then calls [pipeline_job_template.groovy](https://github.com/AdoptOpenJDK/openjdk-build/blob/master/pipelines/jobs/pipeline_job_template.groovy) to finalise the dsl. By default, the [job that runs this file](https://ci.adoptopenjdk.net/job/build-scripts/job/utils/job/build-pipeline-generator/) has restricted read access so you will likely need to contact a jenkins admin to see the results of the job.

# Downstream Test Jobs
The [downstream test jobs](https://ci.adoptopenjdk.net/view/Test_openjdk/) are generated separately from the build ones, via the [Test_Job_Auto_Gen](https://ci.adoptopenjdk.net/view/Test_grinder/job/Test_Job_Auto_Gen/), [testJobTemplate](https://github.com/AdoptOpenJDK/openjdk-tests/blob/master/buildenv/jenkins/testJobTemplate) and [testPipeline](https://github.com/AdoptOpenJDK/openjdk-tests/blob/master/buildenv/jenkins/wip/testpipeline.groovy) resources in the openjdk-tests repository.
