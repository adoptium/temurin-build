# Job Regenerator
To enable concurrent pipeline builds (i.e. submitting two pipelines in parralel), we have implemented a "job regeneration" system for each JDK version. 

# Intro
All of our [pipelines](https://ci.adoptopenjdk.net/job/build-scripts/) make use of [downstream jobs](https://ci.adoptopenjdk.net/job/build-scripts/job/jobs/) to build Adopt's JDK's. In short, the jobs are created in the pipelines with a set of configurations passed down to them. To create these jobs, we utilise a plugin called [job dsl](https://github.com/jenkinsci/job-dsl-plugin) to create a `dsl` file for each downstream job, containing the configurations, node label, etc. 

In the past, we created these dsl's in the [pipeline files](https://github.com/AdoptOpenJDK/openjdk-build/tree/master/pipelines/build). So each time we wanted to create a downstream job, we would create all of the job dsl's that were possible for the pipeline and pick the one that we needed. Not only was this resource intensive and slow, but it also meant that concurrent builds were impossible due to the risk of one build's dsl's overwritting anothers. This is why we have created pipeline job generators to create the dsl's for the pipelines to use, instead of creating them in the pipeline jobs.

The job regenerators are essentially downstream job makers. They pull in all the possible downstream job names from the Jenkins API and build the job DSL's for each downstream jobs. The pipelines can use these job dsl's to create their downstream jobs since they are created in the same node as them (the master one). This way, each of the pipelines has a fresh dsl each time, no matter how many builds are running at once.

# Where are they?
They are stored in the [utils](https://ci.adoptopenjdk.net/job/build-scripts/job/utils/) folder of our jenkins server. As of writing this, read access is restricted to only jenkins admins and those who request access through the jenkins admins. The jobs themselves are called `pipeline_jobs_generator_jdk11u`, `pipeline_jobs_generator_jdk8u`, etc. NOTE: When the JDK HEAD updates, these jobs will need to be updated too (see [RELEASING.md](https://github.com/AdoptOpenJDK/openjdk-build/blob/master/RELEASING.md#steps-for-every-version)) for how to do so.

# How do they work?
There are three stages for each job regenerator. 
- Execute the top level job: 
  - The jobs themselves are executed by Github Push on this repository. Each time there is a commit, all the pipeline regenerators are kicked off. This is so any potential changes to the [buildConfigurations](https://github.com/AdoptOpenJDK/openjdk-build/tree/master/pipelines/jobs/configurations) are taken into account when creating a job dsl for each downstream job.
  - Each of the jobs executes it's corresponding [regeneration](https://github.com/AdoptOpenJDK/openjdk-build/tree/master/pipelines/build/regeneration) file, passing down it's version and specific build configurations to the main [base]([config_regeneration](https://github.com/AdoptOpenJDK/openjdk-build/blob/master/pipelines/build/common/config_regeneration.groovy) file.
- Check if the corresponding pipeline is in progress: 
  - Since we want to potentially avoid overwritting the job dsl's of any pipelines in progress, we use the [jenkins api](https://ci.adoptopenjdk.net/api/) to verify that there are no pipelines of that version queued or running. If there are, the job regenerator sleeps for 15mins and checks again afterwards. If not, it moves onto the next step.
- Regenerate the downstream jobs, one at a time: 
  - The regenerator then pulls all of the downstream job names for it's jdk version from the API. After parsing them and going through various error handling stages, the job name and folder path is constructed which is the bare minimum that the job dsl needs to be created. We only need the bare minimum as the pipelines will overwrite most the configs when they run.
  - The job dsl for that downstream job is constructed and that job is then, successfully regenerated. The result is somewhat similar to this:
```
[INFO] Parsing jdk11u-aix-ppc64-openj9...
[Pipeline] echo
Version: jdk11u
Platform: aix
Architecture: ppc64
Variant: openj9
[Pipeline] echo
[INFO] ppc64Aix is regenerating...
[Pipeline] echo
[INFO] FOUND MATCH! Configuration Key: ppc64Aix and buildConfigurationKey: ppc64Aix
[Pipeline] echo
[INFO] build name: build-scripts/jobs/jdk11u/jdk11u-aix-ppc64-openj9
[Pipeline] jobDsl
Processing DSL script pipelines/build/common/create_job_from_template.groovy
Existing items:
    GeneratedJob{name='build-scripts/jobs/jdk11u'}
    GeneratedJob{name='build-scripts/jobs/jdk11u/jdk11u-aix-ppc64-hotspot'}
    GeneratedJob{name='build-scripts/jobs/jdk11u/jdk11u-aix-ppc64-openj9'}
Unreferenced items:
    GeneratedJob{name='build-scripts/jobs/jdk11u/jdk11u-linux-aarch64-hotspot'}
    GeneratedJob{name='build-scripts/jobs/jdk11u/jdk11u-linux-aarch64-openj9'}
    GeneratedJob{name='build-scripts/jobs/jdk11u/jdk11u-linux-aarch64-openj9-linuxXL'}
    GeneratedJob{name='build-scripts/jobs/jdk11u/jdk11u-linux-arm-hotspot'}
    GeneratedJob{name='build-scripts/jobs/jdk11u/jdk11u-linux-ppc64le-hotspot'}
    GeneratedJob{name='build-scripts/jobs/jdk11u/jdk11u-linux-ppc64le-openj9'}
    GeneratedJob{name='build-scripts/jobs/jdk11u/jdk11u-linux-ppc64le-openj9-linuxXL'}
    GeneratedJob{name='build-scripts/jobs/jdk11u/jdk11u-linux-s390x-hotspot'}
    GeneratedJob{name='build-scripts/jobs/jdk11u/jdk11u-linux-s390x-openj9'}
    GeneratedJob{name='build-scripts/jobs/jdk11u/jdk11u-linux-s390x-openj9-linuxXL'}
    GeneratedJob{name='build-scripts/jobs/jdk11u/jdk11u-linux-x64-corretto'}
    GeneratedJob{name='build-scripts/jobs/jdk11u/jdk11u-linux-x64-hotspot'}
    GeneratedJob{name='build-scripts/jobs/jdk11u/jdk11u-linux-x64-openj9'}
    GeneratedJob{name='build-scripts/jobs/jdk11u/jdk11u-linux-x64-openj9-linuxXL'}
    GeneratedJob{name='build-scripts/jobs/jdk11u/jdk11u-mac-x64-hotspot'}
    GeneratedJob{name='build-scripts/jobs/jdk11u/jdk11u-mac-x64-openj9'}
    GeneratedJob{name='build-scripts/jobs/jdk11u/jdk11u-mac-x64-openj9-macosXL'}
    GeneratedJob{name='build-scripts/jobs/jdk11u/jdk11u-windows-x64-hotspot'}
    GeneratedJob{name='build-scripts/jobs/jdk11u/jdk11u-windows-x64-openj9'}
    GeneratedJob{name='build-scripts/jobs/jdk11u/jdk11u-windows-x64-openj9-windowsXL'}
    GeneratedJob{name='build-scripts/jobs/jdk11u/jdk11u-windows-x86-32-hotspot'}
[Pipeline] echo
[SUCCESS] Regenerated configuration for job build-scripts/jobs/jdk11u/jdk11u-aix-ppc64-openj9
```
  
