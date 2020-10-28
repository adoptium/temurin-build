# Changelog for openjdk-build scripts (DEPRECATED)

## DEPRECATION NOTES

**THIS DOCUMENT IS NO LONGER POPULATED. PLEASE SEE THE [MASTER COMMIT HISTORY](https://github.com/AdoptOpenJDK/openjdk-build/commits/master) FOR A MORE UP TO DATE LOG**

## Version 1.0.0 (14th May 2018)

See [Commit History](https://github.com/AdoptOpenJDK/openjdk-build/commits/master) 
up until May the 14th 2018.

## Version 2.0.0 (26th Sep 2018)

A major overhaul to split out Docker and Native builds, fix a host of small 
issues and place build jobs into Groovy Pipeline scripts.

### Core Build Changes

1. _configureBuild.sh_ added.  The pre-build configuration logic now resides in 
this script.
1. _native-build.sh_ added.  This script is invoked for building (Adopt) OpenJDK 
binaries natively.
1. _docker-build.sh_ added.  This script is invoked for building (Adopt) OpenJDK 
binaries in a Docker container.
1. _sbin/prepareWorkspace.sh_ added
1. _sbin/colour-codes.sh_ removed to simplify code
1. _makejdk.sh_ removed - please use _makejdk-any-platform.sh_ or (rarely) 
_sbin/build.sh_ instead. 
1. _sbin/common-functions.sh_ removed and its logic split 
1. _sbin/common/common.sh_ added
1. _sbin/common/config_init.sh_ added
1. _sbin/common/constants.sh_ added
1. _sbin/build.template_ added for saving off the configure configuration. 
1. _sbin/signalhandler.sh_ moved to _signalhandler.sh_
1. _sbin/build.sh_ enhanced, now requires a 'saved' build configuration to run. 
This 'saved' build configuration is created by _makejdk-any-platform.sh_ but 
can be generated manually as well.
1. _sign.sh_ added for code signing functionality.


#### _makejdk-any-platform.sh_, _build.sh_, _makejdk.sh_ usage changes

1. More versions added, `jdk8u | jdk9 | jdk10 | jfx | amber` are now all supported
1. `-B` is now used for specifying the build number (long form `--build-number`).
1. `-bv` is removed, (long form `--variant` changes to `--build-variant`).
1. `-c` (long form `--clean-docker-build`) added to build from a clean docker container.
1. `-ca` changes to `-C`, (long form `--configure-args` stays the same).
1. `--clean-git-repos`, added to clean out any 'bad' local git repo you already have.
1. `-D` (long form `--docker`) added for building in a docker container.
1. `-dsgc` is removed, (long form `--disable-shallow-git-clone` stays the same).
1. `-ftd` changes to `-f`, (long form `--freetype-dir` stays the same).
1. `--freetype-build-param`, specify any special freetype build parameters (required for some OS's).
1. `--freetype-version`, specify the version of freetype you are building.
1. `-h` (long form `--help`) added.
1. `-i` (long form `--ignore-container`) added to ignore existing docker container.
1. `-j, --jtreg` and `-js, --jtreg-subsets` are removed as tests should be run via the openjdk-tests repo / project.
1. `-J` (long form `--jdk-boot-dir` added to set JDK boot dir.
1. `-nc` (long form `--no-colour`) is removed.
1. `-p` (long form `--processors`) added to set number of processors in docker build.
1. `-sf` changes to `-F`, (long form `--skip-freetype` stays the same).
1. `--sudo` added to run the docker container as root.
1. `--tmp-space-build` (set a temporary build space if regular workspace is unavailable).
1. `-T` (long form `--target-file-name` added to specify the final name of the binary.
1. `-u` (long form `--update-version`) added to specify the update version.
1. `--use-jep319-certs` added to use certs defined in JEP319 for OpenJDK 8/9 builds.
1. `-V` (long form `--jvm-variant` specify the JVM variant (server or client).

Please see _makejdk-any-platform.1_ man page for full details.

### Test Changes

1. _sbin/jtreg.sh_ removed (superseded by the openjdk-tests project).
1. _sbin/jtreg_prep.sh_ removed (superseded by the openjdk-tests project).

### Docker Support

1. `-D` (long form `--docker`) has been added for building in a docker container.
1. `-c` (long form `--clean-docker-build`) has been added to build from a clean 
docker container.
1. `-i` (long form `--ignore-container`) has been added to ignore existing docker 
container.
1. `-p` (long form `--processors`) added to set number of processors in docker build.
1. `--sudo` added to run the docker container as root.
1. _docker-build.sh_ added.  This script is invoked for building (Adopt) OpenJDK 
binaries in a Docker container.
1. _docker/jdk<X>/x86_64/ubuntu/Dockerfile_ updated for various bug fixes.
1. _docker/jdk<X>/x86_64/ubuntu/dockerConfiguration.sh_ files added.  These 
contain Docker specific environment variables that the build scripts need (as 
opposed to falsely picking up the underlying native env).

### Build Farm Support

1. New _build-farm/make-adopt-build-farm.sh_ added for the new AdoptOpenJDK 
Build Farm jenkins pipeline to build Adopt OpenJDK binaries.  Sets the default 
environment variables that are currently set in individual jobs.  This allows 
us to now track and version these variables.
1. New _build-farm/set-platform-specific-configurations.sh_ added for the new 
AdoptOpenJDK Build Farm jenkins pipeline to build Adopt OpenJDK binaries.  Sets 
the default environment variables that are currently set in individual jobs.  
This allows us to now track and version these variables.
1. New _build-farm/platform-specific-configurations/<platform>.sh added for 
the new AdoptOpenJDK Build Farm jenkins pipeline to build Adopt OpenJDK binaries.  
Sets the default environment variables for specific platforms that are currently 
set in individual jobs.  This allows us to now track and version these variables.
1. New _build-farm/sign-releases.sh added for the new AdoptOpenJDK Build Farm 
jenkins pipeline to code sign Adopt OpenJDK binaries (Mac and Windows for now).
1. _pipelines/build/common/build_base_file.groovy_ added. This co-ordinates the various 
 pipeline builds.
1._pipelines/build/common/create\_job\_from\_template.groovy_ added. This dynamically 
creates jenkins jobs for a particular pipeline run (e.g. All jdk8u jobs).
1. _pipelines/build/common/openjdk\_build\_pipeline.groovy_ added. This forms the base 
pipeline code for each build.
1. _pipelines/build/openjdk\<version\>\_\<variant\>\_\<nightly\|release\>\_pipeline.groovy_ 
files added.  These will eventually replace the existing individual jobs with a 
Pipeline for each version and variant.
1. _pipelines/build/openjdk\<version\>\_pipeline.groovy_ 
files added. These define the configurations for the 
_pipelines/build/common/create\_job\_from\_template.groovy_ to create jobs for a pipeline 
 run.

### Documentation and Misc

1. _README.md_ updated to reflect new scripts.
1. _docs/build.md_ added to describe how the build farm utilises the scripts.
1. _docs/generateBuildMatrix.sh_ added to build a table of build statuses.
1. _docs/generateTestMatrix.sh_ added to build a table of test statuses.
1. _docs/images/AdoptOpenJDK_Build_Script_Relationships.png_ added to show script 
relationship.
1. _docs/images/sequence.svg_ added to show pipeline workflow.
1. _.gitignore_ changed to reflect new `workspace` base directory, please check 
your local .gitignore for the diff.
1. _makejdk-any-platform.1_ man page updated to reflect new script usage.
