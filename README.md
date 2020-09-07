# Repository for code and instructions for building OpenJDK

[![Build Status](https://travis-ci.org/AdoptOpenJDK/openjdk-build.svg?branch=master)](https://travis-ci.org/AdoptOpenJDK/openjdk-build) [![Slack](https://slackin-jmnmplfpdu.now.sh/badge.svg)](https://slackin-jmnmplfpdu.now.sh/)

AdoptOpenJDK makes use of these scripts to build binaries on the build farm at
https://ci.adoptopenjdk.net, which produces OpenJDK binaries for consumption via
https://www.adoptopenjdk.net and https://api.adoptopenjdk.net.

## TL;DR: I want to build a JDK NOW!

##### Build jdk natively on your system

To do this you will need to have your machine set up with a suitable
compiler and various other tools available. We set up our machines using
ansible playbooks from
the https://github.com/adoptopenjdk/openjdk-infrastructure repository
although you can also look at the [dockerfile generator](https://github.com/AdoptOpenJDK/openjdk-build/blob/master/docker/dockerfile-generator.sh) for a list of
required packages for Ubuntu.

Once you've got all of the prerequisites installed, clone this openjdk-build
repository (`git clone https://github.com/AdoptOpenJDK/openjdk-build` and
kick off a build a follows with this script. The `-J` parameter specifies
the "boot JDK" which should generally be one major version prior to the one
you are building (although one of the same major version will also work).
Note that the build variant default to HotSpot if omitted.

```
./makejdk-any-platform.sh (-J /usr/lib/jvm/jdk-xx) (--build-variant <hotspot|openj9|corretto|SapMachine|dragonwell>) <jdk8u|jdk11u|jdk15u|jdk>
```
e.g.
```
./makejdk-any-platform.sh -J /usr/lib/jvm/jdk-10.0.2 --build-variant hotspot jdk11u
```

## How do I build OpenJDK in a docker image?

If you do not want to set up your machine with all the prerequisites for
building openjdk, you can use our docker images under the [docker]
directory as follows (first version builds HotSpot, second builds J9 - the
final parameter can be adjusted to build whichever version you want as long
as we can generate valid dockerfile for it:

```
./makejdk-any-platform.sh --docker --clean-docker-build jdk8u
./makejdk-any-platform.sh --docker --clean-docker-build --build-variant openj9 jdk11u
```

We test these dockerfiles on a regular basis in the
[Dockerfilecheck](https://ci.adoptopenjdk.net/job/DockerfileCheck/) job
to ensure they continue to work in a stable fashion.

## Repository contents

This repository contains several useful scripts in order to build OpenJDK
personally or at build farm scale.

1. The `build-farm` folder contains shell scripts for multi configuration Jenkins
build jobs used for building Adopt OpenJDK binaries.
2. The `docker` folder contains tools for generating dockerfiles which can be used as part of building
OpenJDK inside a Docker container.
3. The `docs` folder contains images and utility scripts to produce up to date
documentation.
4. The `git-hg` folder contains scripts to clone an OpenJDK mercurial forest into
a GitHub repo ()and regularly update it).
5. The `mercurial-tags/java-tool` folder contains scripts for TODO.
6. The `pipelines` folder contains the Groovy pipeline scripts for Jenkins
(e.g. build | test | checksum | release).
7. The `sbin` folder contains the scripts that actually build (AdoptOpenJDK).
`build.sh` is the entry point which can be used stand alone but is typically
called by the `native-build.sh` or `docker-build.sh` scripts (which themselves
are typically called by `makejdk-any-platform.sh`).
8. The `security` folder contains a script and `cacerts` file that is bundled
with the JDK and used when building OpenJDK: the `cacerts` file is an important
file that's used to enable SSL connections.

## The makejdk-any-platform.sh script

`makejdk-any-platform.sh` is the entry point for building (Adopt) OpenJDK binaries.
Building natively or in a docker container are both supported. This script (and
its supporting scripts) have defaults, but you can override these as needed.
The scripts will auto detect the platform and architecture it is running on and
configure the OpenJDK build accordingly.  The supporting scripts will also
download and locally install any required dependencies for the OpenJDK build,
e.g. The ALSA sound and Freetype font libraries.

Many of the configuration options are passed through to the `configure` and
`make` commands that OpenJDK uses to build binaries.  Please see the appropriate
_README-builds.html_ file for the OpenJDK source repository that you are building.

**NOTE:** Usage can be found via `makejdk-any-platform.sh --help`. Here is the
man page re-formatted for convenience.

```
USAGE

./makejdk-any-platform [options] version

Please visit https://www.adoptopenjdk.net for further support.

VERSIONS

jdk8u - Build Java 8, defaults to https://github.com/AdoptOpenJDK/openjdk-jdk8u
jdk9u - Build Java 9, defaults to https://github.com/AdoptOpenJDK/openjdk-jdk9u
jdk10u - Build Java 10, defaults to https://github.com/AdoptOpenJDK/openjdk-jdk10u
jdk11u - Build Java 11, defaults to https://github.com/AdoptOpenJDK/openjdk-jdk11u
jdk12u - Build Java 12, defaults to https://github.com/AdoptOpenJDK/openjdk-jdk12u
jdk13u - Build Java 13, defaults to https://github.com/AdoptOpenJDK/openjdk-jdk13u
jdk - Build Latest Java (Alpha/Beta), defaults to https://github.com/AdoptOpenJDK/openjdk-jdk
jfx - Build OpenJFX, defaults to https://github.com/AdoptOpenJDK/openjdk-jfx
amber - Build Project Amber, defaults to https://github.com/AdoptOpenJDK/openjdk-amber

OPTIONS

-b, --branch <branch>
specify a custom branch to build from, e.g. dev.
For reference, AdoptOpenJDK GitHub source repos default to the dev
branch which may contain a very small diff set to the master branch
(which is a clone from the OpenJDK mercurial forest).

-B, --build-number <build_number>
specify the OpenJDK build number to build from, e.g. b12.
For reference, OpenJDK version numbers look like 1.8.0_162-b12 (for Java 8) or
9.0.4+11 (for Java 9+) with the build number being the suffix at the end.

--build-variant <variant_name>
specify a OpenJDK build variant, e.g. openj9.
For reference, the default variant is hotspot and does not need to be specified.

-c, --clean-docker-build
removes the existing docker container and persistent volume before starting
a new docker based build.

-C, --configure-args <args>
specify any custom user configuration arguments.

--clean-git-repo
clean out any 'bad' local git repo you already have.

-d, --destination <path>
specify the location for the built binary, e.g. /path/.
This is typically used in conjunction with -T to create a custom path
/ file name for the resulting binary.

-D, --docker
build OpenJDK in a docker container.

--debug-docker
debug OpenJDK build script in a docker container. Only valid if -D is selected.

--disable-shallow-git-clone
disable the default fB--depth=1 shallow cloning of git repo(s).

-f, --freetype-dir
specify the location of an existing FreeType library.
This is typically used in conjunction with -F.

--freetype-build-param <parameter>
specify any special freetype build parameters (required for some OS's).

--freetype-version <version>
specify the version of freetype you are building.

-F, --skip-freetype
skip building Freetype automatically.
This is typically used in conjunction with -f.

-h, --help
print the man page.

-i, --ignore-container
ignore the existing docker container if you have one already.

-J, --jdk-boot-dir <jdk_boot_dir>
specify the JDK boot dir.
For reference, OpenJDK needs the previous version of a JDK in order to build
itself. You should select the path to a JDK install that is N-1 versions below
the one you are trying to build.

-k, --keep
if using docker, keep the container after the build.

-n, --no-colour
disable colour output.

-p, --processors <args>
specify the number of processors to use for the docker build.

-r, --repository <repository>
specify the repository to clone OpenJDK source from,
e.g. https://github.com/karianna/openjdk-jdk8u.

-s, --source <path>
specify the location to clone the OpenJDK source (and dependencies) to.

-S, --ssh
use ssh when cloning git.
In case of docker build add github.com to ~/.ssh/known_hosts (e.g.: ssh github.com)
if your ssh key has a passphrase, add it to ssh-agent (e.g.: ssh-add ~/.ssh/id_rsa)

--sign
sign the OpenJDK binary that you build.

--sudo
run the docker container as root.

-t, --tag <tag>
specify the repository tag that you want to build OpenJDK from.

-T, --target-file-name <file_name>
specify the final name of the OpenJDK binary.
This is typically used in conjunction with -D to create a custom file
name for the resulting binary.

--tmp-space-build
use the temp directory for performing the build

-u, --update-version <update_version>
specify the update version to build OpenJDK from, e.g. 162.
For reference, OpenJDK version numbers look like 1.8.0_162-b12 (for Java 8) or
9.0.4+11 (for Java 9+) with the update number being the number after the '_'
(162) or the 3rd position in the semVer version string (4).
This is typically used in conjunction with -b.

--use-jep319-certs
Use certs defined in JEP319 in Java 8/9. This will increase the volume of traffic downloaded, however will
provide an upto date ca cert list.

-v, --version
specify the OpenJDK version to build e.g. jdk8u.  Left for backwards compatibility.

-V, --jvm-variant <jvm_variant>
specify the JVM variant (server or client), defaults to server.

Example usage:

./makejdk-any-platform --docker jdk8u
./makejdk-any-platform -T MyOpenJDK10.tar.gz jdk10

```

### Script Relationships

![Build Variant Workflow](docs/images/AdoptOpenJDK_Build_Script_Relationships.png)

The main script to build OpenJDK is `makejdk-any-platform.sh`, which itself uses
and/or calls `configureBuild.sh`, `docker-build.sh` and/or `native-build.sh`.

The structure of a build is:

 1. Configuration phase determines what the configuration of the build is based on your current
platform and and optional arguments provided
 1. Configuration is written out to `config/built_config.cfg`
 1. Build is kicked off by either creating a docker container or running the native build script
 1. Build reads in configuration from `built_config.cfg`
 1. Downloads source, dependencies and prepares build workspace
 1. Invoke OpenJDK build via `make`
 1. Package up built artifacts

- Configuration phase is primarily performed by [configureBuild.sh](https://github.com/AdoptOpenJDK/openjdk-build/blob/master/configureBuild.sh) and [makejdk-any-platform.sh](https://github.com/AdoptOpenJDK/openjdk-build/blob/master/makejdk-any-platform.sh).
- If a docker container is required it is built by [docker-build.sh](https://github.com/AdoptOpenJDK/openjdk-build/blob/master/docker-build.sh) otherwise [native-build.sh](https://github.com/AdoptOpenJDK/openjdk-build/blob/master/native-build.sh).
- In the build phase [sbin/build.sh](https://github.com/AdoptOpenJDK/openjdk-build/blob/master/sbin/build.sh) is invoked either natively or inside the docker container.
`sbin/build.sh` invokes [sbin/prepareWorkspace.sh](https://github.com/AdoptOpenJDK/openjdk-build/blob/master/sbin/prepareWorkspace.sh) to download dependencies, source and perform
general preparation.
- Rest of the build and packaging is then handled from `sbin/build.sh`

## Building OpenJDK from other locations

### Building OpenJDK from a non-AdoptOpenJDK repository

These scripts default to using AdoptOpenJDK as the OpenJDK source repo to build
from, but you can override this with the `-r` flag. If you want to run from a
non-default branch you can also specify -b e.g.

```
./makejdk-any-platform.sh -r https://github.com/sxa/openjdk-jdk8u -b main -J /usr/lib/jvm/java-1.7.0 jdk8u
```

### Building in a custom directory

Example Usage

`./makejdk-any-platform.sh -J /usr/lib/jvm/jdk-10.0.2 -s $HOME/openjdk-jdk11u/src -d $HOME/openjdk-jdk11u/build -T MyOpenJDK11.tar.gz jdk11u`

This would clone OpenJDK source from _https://github.com/AdoptOpenJDK/openjdk-jdk11u_
to `$HOME/openjdk-jdk11u/src`, configure the build with sensible defaults according
to your local platform and then build OpenJDK and place the result in
`/home/openjdk/target/MyOpenJDK11.tar.gz`.

# Metadata
**This is still in alpha do not rely on this yet**
Alongside the built assets a metadata file will be created with info about the build. This will be a JSON document of the form:

```
    {
        "WARNING": "THIS METADATA FILE IS STILL IN ALPHA DO NOT USE ME",
        "os": "linux",
        "arch": "x64",
        "variant": "hotspot",
        "version": "jdk8u",
        "tag": "jdk8u202-b08",
        {
            "adopt_build_number": 2,
            "major": 8,
            "minor": 0,
            "security": 202,
            "build": 8,
            "version": "8u202-b08",
            "semver": "8.0.202+8.2",
        },
        "binary_type": "jdk"
    }
```

It is worth noting the additional tags on the semver is the adopt build number.

# Build status

Table generated with `generateBuildMatrix.sh`

| Platform                  | Java 8 | Java 9 | Java 10 | Java 11 | Java 12 |
| ------------------------- | ------ | ------ | ------- | ------- | ------- |
| aix-ppc64-hotspot | [![Build Status](https://ci.adoptopenjdk.net/buildStatus/icon?job=build-scripts/jobs/jdk8u/jdk8u-aix-ppc64-hotspot)](https://ci.adoptopenjdk.net/job/build-scripts/job/jobs/job/jdk8u/job/jdk8u-aix-ppc64-hotspot) | [![Build Status](https://ci.adoptopenjdk.net/buildStatus/icon?job=build-scripts/jobs/jdk9u/jdk9u-aix-ppc64-hotspot)](https://ci.adoptopenjdk.net/job/build-scripts/job/jobs/job/jdk9u/job/jdk9u-aix-ppc64-hotspot) | [![Build Status](https://ci.adoptopenjdk.net/buildStatus/icon?job=build-scripts/jobs/jdk10u/jdk10u-aix-ppc64-hotspot)](https://ci.adoptopenjdk.net/job/build-scripts/job/jobs/job/jdk10u/job/jdk10u-aix-ppc64-hotspot) | [![Build Status](https://ci.adoptopenjdk.net/buildStatus/icon?job=build-scripts/jobs/jdk11u/jdk11u-aix-ppc64-hotspot)](https://ci.adoptopenjdk.net/job/build-scripts/job/jobs/job/jdk11u/job/jdk11u-aix-ppc64-hotspot) | [![Build Status](https://ci.adoptopenjdk.net/buildStatus/icon?job=build-scripts/jobs/jdk12u/jdk12u-aix-ppc64-hotspot)](https://ci.adoptopenjdk.net/job/build-scripts/job/jobs/job/jdk12u/job/jdk12u-aix-ppc64-hotspot) |
| aix-ppc64-openj9 | [![Build Status](https://ci.adoptopenjdk.net/buildStatus/icon?job=build-scripts/jobs/jdk8u/jdk8u-aix-ppc64-openj9)](https://ci.adoptopenjdk.net/job/build-scripts/job/jobs/job/jdk8u/job/jdk8u-aix-ppc64-openj9) | [![Build Status](https://ci.adoptopenjdk.net/buildStatus/icon?job=build-scripts/jobs/jdk9u/jdk9u-aix-ppc64-openj9)](https://ci.adoptopenjdk.net/job/build-scripts/job/jobs/job/jdk9u/job/jdk9u-aix-ppc64-openj9) | [![Build Status](https://ci.adoptopenjdk.net/buildStatus/icon?job=build-scripts/jobs/jdk10u/jdk10u-aix-ppc64-openj9)](https://ci.adoptopenjdk.net/job/build-scripts/job/jobs/job/jdk10u/job/jdk10u-aix-ppc64-openj9) | [![Build Status](https://ci.adoptopenjdk.net/buildStatus/icon?job=build-scripts/jobs/jdk11u/jdk11u-aix-ppc64-openj9)](https://ci.adoptopenjdk.net/job/build-scripts/job/jobs/job/jdk11u/job/jdk11u-aix-ppc64-openj9) | [![Build Status](https://ci.adoptopenjdk.net/buildStatus/icon?job=build-scripts/jobs/jdk12u/jdk12u-aix-ppc64-openj9)](https://ci.adoptopenjdk.net/job/build-scripts/job/jobs/job/jdk12u/job/jdk12u-aix-ppc64-openj9) |
| linux-aarch64-hotspot | [![Build Status](https://ci.adoptopenjdk.net/buildStatus/icon?job=build-scripts/jobs/jdk8u/jdk8u-linux-aarch64-hotspot)](https://ci.adoptopenjdk.net/job/build-scripts/job/jobs/job/jdk8u/job/jdk8u-linux-aarch64-hotspot) | [![Build Status](https://ci.adoptopenjdk.net/buildStatus/icon?job=build-scripts/jobs/jdk9u/jdk9u-linux-aarch64-hotspot)](https://ci.adoptopenjdk.net/job/build-scripts/job/jobs/job/jdk9u/job/jdk9u-linux-aarch64-hotspot) | [![Build Status](https://ci.adoptopenjdk.net/buildStatus/icon?job=build-scripts/jobs/jdk10u/jdk10u-linux-aarch64-hotspot)](https://ci.adoptopenjdk.net/job/build-scripts/job/jobs/job/jdk10u/job/jdk10u-linux-aarch64-hotspot) | [![Build Status](https://ci.adoptopenjdk.net/buildStatus/icon?job=build-scripts/jobs/jdk11u/jdk11u-linux-aarch64-hotspot)](https://ci.adoptopenjdk.net/job/build-scripts/job/jobs/job/jdk11u/job/jdk11u-linux-aarch64-hotspot) | [![Build Status](https://ci.adoptopenjdk.net/buildStatus/icon?job=build-scripts/jobs/jdk12u/jdk12u-linux-aarch64-hotspot)](https://ci.adoptopenjdk.net/job/build-scripts/job/jobs/job/jdk12u/job/jdk12u-linux-aarch64-hotspot) |
| linux-aarch64-openj9 | [![Build Status](https://ci.adoptopenjdk.net/buildStatus/icon?job=build-scripts/jobs/jdk8u/jdk8u-linux-aarch64-openj9)](https://ci.adoptopenjdk.net/job/build-scripts/job/jobs/job/jdk8u/job/jdk8u-linux-aarch64-openj9) | [![Build Status](https://ci.adoptopenjdk.net/buildStatus/icon?job=build-scripts/jobs/jdk9u/jdk9u-linux-aarch64-openj9)](https://ci.adoptopenjdk.net/job/build-scripts/job/jobs/job/jdk9u/job/jdk9u-linux-aarch64-openj9) | [![Build Status](https://ci.adoptopenjdk.net/buildStatus/icon?job=build-scripts/jobs/jdk10u/jdk10u-linux-aarch64-openj9)](https://ci.adoptopenjdk.net/job/build-scripts/job/jobs/job/jdk10u/job/jdk10u-linux-aarch64-openj9) | [![Build Status](https://ci.adoptopenjdk.net/buildStatus/icon?job=build-scripts/jobs/jdk11u/jdk11u-linux-aarch64-openj9)](https://ci.adoptopenjdk.net/job/build-scripts/job/jobs/job/jdk11u/job/jdk11u-linux-aarch64-openj9) | [![Build Status](https://ci.adoptopenjdk.net/buildStatus/icon?job=build-scripts/jobs/jdk12u/jdk12u-linux-aarch64-openj9)](https://ci.adoptopenjdk.net/job/build-scripts/job/jobs/job/jdk12u/job/jdk12u-linux-aarch64-openj9) |
| linux-arm-hotspot | [![Build Status](https://ci.adoptopenjdk.net/buildStatus/icon?job=build-scripts/jobs/jdk8u/jdk8u-linux-arm-hotspot)](https://ci.adoptopenjdk.net/job/build-scripts/job/jobs/job/jdk8u/job/jdk8u-linux-arm-hotspot) | [![Build Status](https://ci.adoptopenjdk.net/buildStatus/icon?job=build-scripts/jobs/jdk9u/jdk9u-linux-arm-hotspot)](https://ci.adoptopenjdk.net/job/build-scripts/job/jobs/job/jdk9u/job/jdk9u-linux-arm-hotspot) | [![Build Status](https://ci.adoptopenjdk.net/buildStatus/icon?job=build-scripts/jobs/jdk10u/jdk10u-linux-arm-hotspot)](https://ci.adoptopenjdk.net/job/build-scripts/job/jobs/job/jdk10u/job/jdk10u-linux-arm-hotspot) | [![Build Status](https://ci.adoptopenjdk.net/buildStatus/icon?job=build-scripts/jobs/jdk11u/jdk11u-linux-arm-hotspot)](https://ci.adoptopenjdk.net/job/build-scripts/job/jobs/job/jdk11u/job/jdk11u-linux-arm-hotspot) | [![Build Status](https://ci.adoptopenjdk.net/buildStatus/icon?job=build-scripts/jobs/jdk12u/jdk12u-linux-arm-hotspot)](https://ci.adoptopenjdk.net/job/build-scripts/job/jobs/job/jdk12u/job/jdk12u-linux-arm-hotspot) |
| linux-ppc64le-hotspot | [![Build Status](https://ci.adoptopenjdk.net/buildStatus/icon?job=build-scripts/jobs/jdk8u/jdk8u-linux-ppc64le-hotspot)](https://ci.adoptopenjdk.net/job/build-scripts/job/jobs/job/jdk8u/job/jdk8u-linux-ppc64le-hotspot) | [![Build Status](https://ci.adoptopenjdk.net/buildStatus/icon?job=build-scripts/jobs/jdk9u/jdk9u-linux-ppc64le-hotspot)](https://ci.adoptopenjdk.net/job/build-scripts/job/jobs/job/jdk9u/job/jdk9u-linux-ppc64le-hotspot) | [![Build Status](https://ci.adoptopenjdk.net/buildStatus/icon?job=build-scripts/jobs/jdk10u/jdk10u-linux-ppc64le-hotspot)](https://ci.adoptopenjdk.net/job/build-scripts/job/jobs/job/jdk10u/job/jdk10u-linux-ppc64le-hotspot) | [![Build Status](https://ci.adoptopenjdk.net/buildStatus/icon?job=build-scripts/jobs/jdk11u/jdk11u-linux-ppc64le-hotspot)](https://ci.adoptopenjdk.net/job/build-scripts/job/jobs/job/jdk11u/job/jdk11u-linux-ppc64le-hotspot) | [![Build Status](https://ci.adoptopenjdk.net/buildStatus/icon?job=build-scripts/jobs/jdk12u/jdk12u-linux-ppc64le-hotspot)](https://ci.adoptopenjdk.net/job/build-scripts/job/jobs/job/jdk12u/job/jdk12u-linux-ppc64le-hotspot) |
| linux-ppc64le-openj9 | [![Build Status](https://ci.adoptopenjdk.net/buildStatus/icon?job=build-scripts/jobs/jdk8u/jdk8u-linux-ppc64le-openj9)](https://ci.adoptopenjdk.net/job/build-scripts/job/jobs/job/jdk8u/job/jdk8u-linux-ppc64le-openj9) | [![Build Status](https://ci.adoptopenjdk.net/buildStatus/icon?job=build-scripts/jobs/jdk9u/jdk9u-linux-ppc64le-openj9)](https://ci.adoptopenjdk.net/job/build-scripts/job/jobs/job/jdk9u/job/jdk9u-linux-ppc64le-openj9) | [![Build Status](https://ci.adoptopenjdk.net/buildStatus/icon?job=build-scripts/jobs/jdk10u/jdk10u-linux-ppc64le-openj9)](https://ci.adoptopenjdk.net/job/build-scripts/job/jobs/job/jdk10u/job/jdk10u-linux-ppc64le-openj9) | [![Build Status](https://ci.adoptopenjdk.net/buildStatus/icon?job=build-scripts/jobs/jdk11u/jdk11u-linux-ppc64le-openj9)](https://ci.adoptopenjdk.net/job/build-scripts/job/jobs/job/jdk11u/job/jdk11u-linux-ppc64le-openj9) | [![Build Status](https://ci.adoptopenjdk.net/buildStatus/icon?job=build-scripts/jobs/jdk12u/jdk12u-linux-ppc64le-openj9)](https://ci.adoptopenjdk.net/job/build-scripts/job/jobs/job/jdk12u/job/jdk12u-linux-ppc64le-openj9) |
| linux-s390x-hotspot | [![Build Status](https://ci.adoptopenjdk.net/buildStatus/icon?job=build-scripts/jobs/jdk8u/jdk8u-linux-s390x-hotspot)](https://ci.adoptopenjdk.net/job/build-scripts/job/jobs/job/jdk8u/job/jdk8u-linux-s390x-hotspot) | [![Build Status](https://ci.adoptopenjdk.net/buildStatus/icon?job=build-scripts/jobs/jdk9u/jdk9u-linux-s390x-hotspot)](https://ci.adoptopenjdk.net/job/build-scripts/job/jobs/job/jdk9u/job/jdk9u-linux-s390x-hotspot) | [![Build Status](https://ci.adoptopenjdk.net/buildStatus/icon?job=build-scripts/jobs/jdk10u/jdk10u-linux-s390x-hotspot)](https://ci.adoptopenjdk.net/job/build-scripts/job/jobs/job/jdk10u/job/jdk10u-linux-s390x-hotspot) | [![Build Status](https://ci.adoptopenjdk.net/buildStatus/icon?job=build-scripts/jobs/jdk11u/jdk11u-linux-s390x-hotspot)](https://ci.adoptopenjdk.net/job/build-scripts/job/jobs/job/jdk11u/job/jdk11u-linux-s390x-hotspot) | [![Build Status](https://ci.adoptopenjdk.net/buildStatus/icon?job=build-scripts/jobs/jdk12u/jdk12u-linux-s390x-hotspot)](https://ci.adoptopenjdk.net/job/build-scripts/job/jobs/job/jdk12u/job/jdk12u-linux-s390x-hotspot) |
| linux-s390x-openj9 | [![Build Status](https://ci.adoptopenjdk.net/buildStatus/icon?job=build-scripts/jobs/jdk8u/jdk8u-linux-s390x-openj9)](https://ci.adoptopenjdk.net/job/build-scripts/job/jobs/job/jdk8u/job/jdk8u-linux-s390x-openj9) | [![Build Status](https://ci.adoptopenjdk.net/buildStatus/icon?job=build-scripts/jobs/jdk9u/jdk9u-linux-s390x-openj9)](https://ci.adoptopenjdk.net/job/build-scripts/job/jobs/job/jdk9u/job/jdk9u-linux-s390x-openj9) | [![Build Status](https://ci.adoptopenjdk.net/buildStatus/icon?job=build-scripts/jobs/jdk10u/jdk10u-linux-s390x-openj9)](https://ci.adoptopenjdk.net/job/build-scripts/job/jobs/job/jdk10u/job/jdk10u-linux-s390x-openj9) | [![Build Status](https://ci.adoptopenjdk.net/buildStatus/icon?job=build-scripts/jobs/jdk11u/jdk11u-linux-s390x-openj9)](https://ci.adoptopenjdk.net/job/build-scripts/job/jobs/job/jdk11u/job/jdk11u-linux-s390x-openj9) | [![Build Status](https://ci.adoptopenjdk.net/buildStatus/icon?job=build-scripts/jobs/jdk12u/jdk12u-linux-s390x-openj9)](https://ci.adoptopenjdk.net/job/build-scripts/job/jobs/job/jdk12u/job/jdk12u-linux-s390x-openj9) |
| linux-x64-corretto | [![Build Status](https://ci.adoptopenjdk.net/buildStatus/icon?job=build-scripts/jobs/jdk8u/jdk8u-linux-x64-corretto)](https://ci.adoptopenjdk.net/job/build-scripts/job/jobs/job/jdk8u/job/jdk8u-linux-x64-corretto) | [![Build Status](https://ci.adoptopenjdk.net/buildStatus/icon?job=build-scripts/jobs/jdk9u/jdk9u-linux-x64-corretto)](https://ci.adoptopenjdk.net/job/build-scripts/job/jobs/job/jdk9u/job/jdk9u-linux-x64-corretto) | [![Build Status](https://ci.adoptopenjdk.net/buildStatus/icon?job=build-scripts/jobs/jdk10u/jdk10u-linux-x64-corretto)](https://ci.adoptopenjdk.net/job/build-scripts/job/jobs/job/jdk10u/job/jdk10u-linux-x64-corretto) | [![Build Status](https://ci.adoptopenjdk.net/buildStatus/icon?job=build-scripts/jobs/jdk11u/jdk11u-linux-x64-corretto)](https://ci.adoptopenjdk.net/job/build-scripts/job/jobs/job/jdk11u/job/jdk11u-linux-x64-corretto) | [![Build Status](https://ci.adoptopenjdk.net/buildStatus/icon?job=build-scripts/jobs/jdk12u/jdk12u-linux-x64-corretto)](https://ci.adoptopenjdk.net/job/build-scripts/job/jobs/job/jdk12u/job/jdk12u-linux-x64-corretto) |
| linux-x64-hotspot | [![Build Status](https://ci.adoptopenjdk.net/buildStatus/icon?job=build-scripts/jobs/jdk8u/jdk8u-linux-x64-hotspot)](https://ci.adoptopenjdk.net/job/build-scripts/job/jobs/job/jdk8u/job/jdk8u-linux-x64-hotspot) | [![Build Status](https://ci.adoptopenjdk.net/buildStatus/icon?job=build-scripts/jobs/jdk9u/jdk9u-linux-x64-hotspot)](https://ci.adoptopenjdk.net/job/build-scripts/job/jobs/job/jdk9u/job/jdk9u-linux-x64-hotspot) | [![Build Status](https://ci.adoptopenjdk.net/buildStatus/icon?job=build-scripts/jobs/jdk10u/jdk10u-linux-x64-hotspot)](https://ci.adoptopenjdk.net/job/build-scripts/job/jobs/job/jdk10u/job/jdk10u-linux-x64-hotspot) | [![Build Status](https://ci.adoptopenjdk.net/buildStatus/icon?job=build-scripts/jobs/jdk11u/jdk11u-linux-x64-hotspot)](https://ci.adoptopenjdk.net/job/build-scripts/job/jobs/job/jdk11u/job/jdk11u-linux-x64-hotspot) | [![Build Status](https://ci.adoptopenjdk.net/buildStatus/icon?job=build-scripts/jobs/jdk12u/jdk12u-linux-x64-hotspot)](https://ci.adoptopenjdk.net/job/build-scripts/job/jobs/job/jdk12u/job/jdk12u-linux-x64-hotspot) |
| linux-x64-openj9 | [![Build Status](https://ci.adoptopenjdk.net/buildStatus/icon?job=build-scripts/jobs/jdk8u/jdk8u-linux-x64-openj9)](https://ci.adoptopenjdk.net/job/build-scripts/job/jobs/job/jdk8u/job/jdk8u-linux-x64-openj9) | [![Build Status](https://ci.adoptopenjdk.net/buildStatus/icon?job=build-scripts/jobs/jdk9u/jdk9u-linux-x64-openj9)](https://ci.adoptopenjdk.net/job/build-scripts/job/jobs/job/jdk9u/job/jdk9u-linux-x64-openj9) | [![Build Status](https://ci.adoptopenjdk.net/buildStatus/icon?job=build-scripts/jobs/jdk10u/jdk10u-linux-x64-openj9)](https://ci.adoptopenjdk.net/job/build-scripts/job/jobs/job/jdk10u/job/jdk10u-linux-x64-openj9) | [![Build Status](https://ci.adoptopenjdk.net/buildStatus/icon?job=build-scripts/jobs/jdk11u/jdk11u-linux-x64-openj9)](https://ci.adoptopenjdk.net/job/build-scripts/job/jobs/job/jdk11u/job/jdk11u-linux-x64-openj9) | [![Build Status](https://ci.adoptopenjdk.net/buildStatus/icon?job=build-scripts/jobs/jdk12u/jdk12u-linux-x64-openj9)](https://ci.adoptopenjdk.net/job/build-scripts/job/jobs/job/jdk12u/job/jdk12u-linux-x64-openj9) |
| linux-x64-openj9-linuxXL | [![Build Status](https://ci.adoptopenjdk.net/buildStatus/icon?job=build-scripts/jobs/jdk8u/jdk8u-linux-x64-openj9-linuxXL)](https://ci.adoptopenjdk.net/job/build-scripts/job/jobs/job/jdk8u/job/jdk8u-linux-x64-openj9-linuxXL) | [![Build Status](https://ci.adoptopenjdk.net/buildStatus/icon?job=build-scripts/jobs/jdk9u/jdk9u-linux-x64-openj9-linuxXL)](https://ci.adoptopenjdk.net/job/build-scripts/job/jobs/job/jdk9u/job/jdk9u-linux-x64-openj9-linuxXL) | [![Build Status](https://ci.adoptopenjdk.net/buildStatus/icon?job=build-scripts/jobs/jdk10u/jdk10u-linux-x64-openj9-linuxXL)](https://ci.adoptopenjdk.net/job/build-scripts/job/jobs/job/jdk10u/job/jdk10u-linux-x64-openj9-linuxXL) | [![Build Status](https://ci.adoptopenjdk.net/buildStatus/icon?job=build-scripts/jobs/jdk11u/jdk11u-linux-x64-openj9-linuxXL)](https://ci.adoptopenjdk.net/job/build-scripts/job/jobs/job/jdk11u/job/jdk11u-linux-x64-openj9-linuxXL) | [![Build Status](https://ci.adoptopenjdk.net/buildStatus/icon?job=build-scripts/jobs/jdk12u/jdk12u-linux-x64-openj9-linuxXL)](https://ci.adoptopenjdk.net/job/build-scripts/job/jobs/job/jdk12u/job/jdk12u-linux-x64-openj9-linuxXL) |
| mac-x64-corretto | [![Build Status](https://ci.adoptopenjdk.net/buildStatus/icon?job=build-scripts/jobs/jdk8u/jdk8u-mac-x64-corretto)](https://ci.adoptopenjdk.net/job/build-scripts/job/jobs/job/jdk8u/job/jdk8u-mac-x64-corretto) | [![Build Status](https://ci.adoptopenjdk.net/buildStatus/icon?job=build-scripts/jobs/jdk9u/jdk9u-mac-x64-corretto)](https://ci.adoptopenjdk.net/job/build-scripts/job/jobs/job/jdk9u/job/jdk9u-mac-x64-corretto) | [![Build Status](https://ci.adoptopenjdk.net/buildStatus/icon?job=build-scripts/jobs/jdk10u/jdk10u-mac-x64-corretto)](https://ci.adoptopenjdk.net/job/build-scripts/job/jobs/job/jdk10u/job/jdk10u-mac-x64-corretto) | [![Build Status](https://ci.adoptopenjdk.net/buildStatus/icon?job=build-scripts/jobs/jdk11u/jdk11u-mac-x64-corretto)](https://ci.adoptopenjdk.net/job/build-scripts/job/jobs/job/jdk11u/job/jdk11u-mac-x64-corretto) | [![Build Status](https://ci.adoptopenjdk.net/buildStatus/icon?job=build-scripts/jobs/jdk12u/jdk12u-mac-x64-corretto)](https://ci.adoptopenjdk.net/job/build-scripts/job/jobs/job/jdk12u/job/jdk12u-mac-x64-corretto) |
| mac-x64-hotspot | [![Build Status](https://ci.adoptopenjdk.net/buildStatus/icon?job=build-scripts/jobs/jdk8u/jdk8u-mac-x64-hotspot)](https://ci.adoptopenjdk.net/job/build-scripts/job/jobs/job/jdk8u/job/jdk8u-mac-x64-hotspot) | [![Build Status](https://ci.adoptopenjdk.net/buildStatus/icon?job=build-scripts/jobs/jdk9u/jdk9u-mac-x64-hotspot)](https://ci.adoptopenjdk.net/job/build-scripts/job/jobs/job/jdk9u/job/jdk9u-mac-x64-hotspot) | [![Build Status](https://ci.adoptopenjdk.net/buildStatus/icon?job=build-scripts/jobs/jdk10u/jdk10u-mac-x64-hotspot)](https://ci.adoptopenjdk.net/job/build-scripts/job/jobs/job/jdk10u/job/jdk10u-mac-x64-hotspot) | [![Build Status](https://ci.adoptopenjdk.net/buildStatus/icon?job=build-scripts/jobs/jdk11u/jdk11u-mac-x64-hotspot)](https://ci.adoptopenjdk.net/job/build-scripts/job/jobs/job/jdk11u/job/jdk11u-mac-x64-hotspot) | [![Build Status](https://ci.adoptopenjdk.net/buildStatus/icon?job=build-scripts/jobs/jdk12u/jdk12u-mac-x64-hotspot)](https://ci.adoptopenjdk.net/job/build-scripts/job/jobs/job/jdk12u/job/jdk12u-mac-x64-hotspot) |
| mac-x64-openj9 | [![Build Status](https://ci.adoptopenjdk.net/buildStatus/icon?job=build-scripts/jobs/jdk8u/jdk8u-mac-x64-openj9)](https://ci.adoptopenjdk.net/job/build-scripts/job/jobs/job/jdk8u/job/jdk8u-mac-x64-openj9) | [![Build Status](https://ci.adoptopenjdk.net/buildStatus/icon?job=build-scripts/jobs/jdk9u/jdk9u-mac-x64-openj9)](https://ci.adoptopenjdk.net/job/build-scripts/job/jobs/job/jdk9u/job/jdk9u-mac-x64-openj9) | [![Build Status](https://ci.adoptopenjdk.net/buildStatus/icon?job=build-scripts/jobs/jdk10u/jdk10u-mac-x64-openj9)](https://ci.adoptopenjdk.net/job/build-scripts/job/jobs/job/jdk10u/job/jdk10u-mac-x64-openj9) | [![Build Status](https://ci.adoptopenjdk.net/buildStatus/icon?job=build-scripts/jobs/jdk11u/jdk11u-mac-x64-openj9)](https://ci.adoptopenjdk.net/job/build-scripts/job/jobs/job/jdk11u/job/jdk11u-mac-x64-openj9) | [![Build Status](https://ci.adoptopenjdk.net/buildStatus/icon?job=build-scripts/jobs/jdk12u/jdk12u-mac-x64-openj9)](https://ci.adoptopenjdk.net/job/build-scripts/job/jobs/job/jdk12u/job/jdk12u-mac-x64-openj9) |
| mac-x64-openj9-macosXL | [![Build Status](https://ci.adoptopenjdk.net/buildStatus/icon?job=build-scripts/jobs/jdk8u/jdk8u-mac-x64-openj9-macosXL)](https://ci.adoptopenjdk.net/job/build-scripts/job/jobs/job/jdk8u/job/jdk8u-mac-x64-openj9-macosXL) | [![Build Status](https://ci.adoptopenjdk.net/buildStatus/icon?job=build-scripts/jobs/jdk9u/jdk9u-mac-x64-openj9-macosXL)](https://ci.adoptopenjdk.net/job/build-scripts/job/jobs/job/jdk9u/job/jdk9u-mac-x64-openj9-macosXL) | [![Build Status](https://ci.adoptopenjdk.net/buildStatus/icon?job=build-scripts/jobs/jdk10u/jdk10u-mac-x64-openj9-macosXL)](https://ci.adoptopenjdk.net/job/build-scripts/job/jobs/job/jdk10u/job/jdk10u-mac-x64-openj9-macosXL) | [![Build Status](https://ci.adoptopenjdk.net/buildStatus/icon?job=build-scripts/jobs/jdk11u/jdk11u-mac-x64-openj9-macosXL)](https://ci.adoptopenjdk.net/job/build-scripts/job/jobs/job/jdk11u/job/jdk11u-mac-x64-openj9-macosXL) | [![Build Status](https://ci.adoptopenjdk.net/buildStatus/icon?job=build-scripts/jobs/jdk12u/jdk12u-mac-x64-openj9-macosXL)](https://ci.adoptopenjdk.net/job/build-scripts/job/jobs/job/jdk12u/job/jdk12u-mac-x64-openj9-macosXL) |
| solaris-sparcv9-hotspot | [![Build Status](https://ci.adoptopenjdk.net/buildStatus/icon?job=build-scripts/jobs/jdk8u/jdk8u-solaris-sparcv9-hotspot)](https://ci.adoptopenjdk.net/job/build-scripts/job/jobs/job/jdk8u/job/jdk8u-solaris-sparcv9-hotspot) | [![Build Status](https://ci.adoptopenjdk.net/buildStatus/icon?job=build-scripts/jobs/jdk9u/jdk9u-solaris-sparcv9-hotspot)](https://ci.adoptopenjdk.net/job/build-scripts/job/jobs/job/jdk9u/job/jdk9u-solaris-sparcv9-hotspot) | [![Build Status](https://ci.adoptopenjdk.net/buildStatus/icon?job=build-scripts/jobs/jdk10u/jdk10u-solaris-sparcv9-hotspot)](https://ci.adoptopenjdk.net/job/build-scripts/job/jobs/job/jdk10u/job/jdk10u-solaris-sparcv9-hotspot) | [![Build Status](https://ci.adoptopenjdk.net/buildStatus/icon?job=build-scripts/jobs/jdk11u/jdk11u-solaris-sparcv9-hotspot)](https://ci.adoptopenjdk.net/job/build-scripts/job/jobs/job/jdk11u/job/jdk11u-solaris-sparcv9-hotspot) | [![Build Status](https://ci.adoptopenjdk.net/buildStatus/icon?job=build-scripts/jobs/jdk12u/jdk12u-solaris-sparcv9-hotspot)](https://ci.adoptopenjdk.net/job/build-scripts/job/jobs/job/jdk12u/job/jdk12u-solaris-sparcv9-hotspot) |
| solaris-x64-hotspot | [![Build Status](https://ci.adoptopenjdk.net/buildStatus/icon?job=build-scripts/jobs/jdk8u/jdk8u-solaris-x64-hotspot)](https://ci.adoptopenjdk.net/job/build-scripts/job/jobs/job/jdk8u/job/jdk8u-solaris-x64-hotspot) | [![Build Status](https://ci.adoptopenjdk.net/buildStatus/icon?job=build-scripts/jobs/jdk9u/jdk9u-solaris-x64-hotspot)](https://ci.adoptopenjdk.net/job/build-scripts/job/jobs/job/jdk9u/job/jdk9u-solaris-x64-hotspot) | [![Build Status](https://ci.adoptopenjdk.net/buildStatus/icon?job=build-scripts/jobs/jdk10u/jdk10u-solaris-x64-hotspot)](https://ci.adoptopenjdk.net/job/build-scripts/job/jobs/job/jdk10u/job/jdk10u-solaris-x64-hotspot) | [![Build Status](https://ci.adoptopenjdk.net/buildStatus/icon?job=build-scripts/jobs/jdk11u/jdk11u-solaris-x64-hotspot)](https://ci.adoptopenjdk.net/job/build-scripts/job/jobs/job/jdk11u/job/jdk11u-solaris-x64-hotspot) | [![Build Status](https://ci.adoptopenjdk.net/buildStatus/icon?job=build-scripts/jobs/jdk12u/jdk12u-solaris-x64-hotspot)](https://ci.adoptopenjdk.net/job/build-scripts/job/jobs/job/jdk12u/job/jdk12u-solaris-x64-hotspot) |
| windows-x64-corretto | [![Build Status](https://ci.adoptopenjdk.net/buildStatus/icon?job=build-scripts/jobs/jdk8u/jdk8u-windows-x64-corretto)](https://ci.adoptopenjdk.net/job/build-scripts/job/jobs/job/jdk8u/job/jdk8u-windows-x64-corretto) | [![Build Status](https://ci.adoptopenjdk.net/buildStatus/icon?job=build-scripts/jobs/jdk9u/jdk9u-windows-x64-corretto)](https://ci.adoptopenjdk.net/job/build-scripts/job/jobs/job/jdk9u/job/jdk9u-windows-x64-corretto) | [![Build Status](https://ci.adoptopenjdk.net/buildStatus/icon?job=build-scripts/jobs/jdk10u/jdk10u-windows-x64-corretto)](https://ci.adoptopenjdk.net/job/build-scripts/job/jobs/job/jdk10u/job/jdk10u-windows-x64-corretto) | [![Build Status](https://ci.adoptopenjdk.net/buildStatus/icon?job=build-scripts/jobs/jdk11u/jdk11u-windows-x64-corretto)](https://ci.adoptopenjdk.net/job/build-scripts/job/jobs/job/jdk11u/job/jdk11u-windows-x64-corretto) | [![Build Status](https://ci.adoptopenjdk.net/buildStatus/icon?job=build-scripts/jobs/jdk12u/jdk12u-windows-x64-corretto)](https://ci.adoptopenjdk.net/job/build-scripts/job/jobs/job/jdk12u/job/jdk12u-windows-x64-corretto) |
| windows-x64-hotspot | [![Build Status](https://ci.adoptopenjdk.net/buildStatus/icon?job=build-scripts/jobs/jdk8u/jdk8u-windows-x64-hotspot)](https://ci.adoptopenjdk.net/job/build-scripts/job/jobs/job/jdk8u/job/jdk8u-windows-x64-hotspot) | [![Build Status](https://ci.adoptopenjdk.net/buildStatus/icon?job=build-scripts/jobs/jdk9u/jdk9u-windows-x64-hotspot)](https://ci.adoptopenjdk.net/job/build-scripts/job/jobs/job/jdk9u/job/jdk9u-windows-x64-hotspot) | [![Build Status](https://ci.adoptopenjdk.net/buildStatus/icon?job=build-scripts/jobs/jdk10u/jdk10u-windows-x64-hotspot)](https://ci.adoptopenjdk.net/job/build-scripts/job/jobs/job/jdk10u/job/jdk10u-windows-x64-hotspot) | [![Build Status](https://ci.adoptopenjdk.net/buildStatus/icon?job=build-scripts/jobs/jdk11u/jdk11u-windows-x64-hotspot)](https://ci.adoptopenjdk.net/job/build-scripts/job/jobs/job/jdk11u/job/jdk11u-windows-x64-hotspot) | [![Build Status](https://ci.adoptopenjdk.net/buildStatus/icon?job=build-scripts/jobs/jdk12u/jdk12u-windows-x64-hotspot)](https://ci.adoptopenjdk.net/job/build-scripts/job/jobs/job/jdk12u/job/jdk12u-windows-x64-hotspot) |
| windows-x64-openj9 | [![Build Status](https://ci.adoptopenjdk.net/buildStatus/icon?job=build-scripts/jobs/jdk8u/jdk8u-windows-x64-openj9)](https://ci.adoptopenjdk.net/job/build-scripts/job/jobs/job/jdk8u/job/jdk8u-windows-x64-openj9) | [![Build Status](https://ci.adoptopenjdk.net/buildStatus/icon?job=build-scripts/jobs/jdk9u/jdk9u-windows-x64-openj9)](https://ci.adoptopenjdk.net/job/build-scripts/job/jobs/job/jdk9u/job/jdk9u-windows-x64-openj9) | [![Build Status](https://ci.adoptopenjdk.net/buildStatus/icon?job=build-scripts/jobs/jdk10u/jdk10u-windows-x64-openj9)](https://ci.adoptopenjdk.net/job/build-scripts/job/jobs/job/jdk10u/job/jdk10u-windows-x64-openj9) | [![Build Status](https://ci.adoptopenjdk.net/buildStatus/icon?job=build-scripts/jobs/jdk11u/jdk11u-windows-x64-openj9)](https://ci.adoptopenjdk.net/job/build-scripts/job/jobs/job/jdk11u/job/jdk11u-windows-x64-openj9) | [![Build Status](https://ci.adoptopenjdk.net/buildStatus/icon?job=build-scripts/jobs/jdk12u/jdk12u-windows-x64-openj9)](https://ci.adoptopenjdk.net/job/build-scripts/job/jobs/job/jdk12u/job/jdk12u-windows-x64-openj9) |
| windows-x86-32-hotspot | [![Build Status](https://ci.adoptopenjdk.net/buildStatus/icon?job=build-scripts/jobs/jdk8u/jdk8u-windows-x86-32-hotspot)](https://ci.adoptopenjdk.net/job/build-scripts/job/jobs/job/jdk8u/job/jdk8u-windows-x86-32-hotspot) | [![Build Status](https://ci.adoptopenjdk.net/buildStatus/icon?job=build-scripts/jobs/jdk9u/jdk9u-windows-x86-32-hotspot)](https://ci.adoptopenjdk.net/job/build-scripts/job/jobs/job/jdk9u/job/jdk9u-windows-x86-32-hotspot) | [![Build Status](https://ci.adoptopenjdk.net/buildStatus/icon?job=build-scripts/jobs/jdk10u/jdk10u-windows-x86-32-hotspot)](https://ci.adoptopenjdk.net/job/build-scripts/job/jobs/job/jdk10u/job/jdk10u-windows-x86-32-hotspot) | [![Build Status](https://ci.adoptopenjdk.net/buildStatus/icon?job=build-scripts/jobs/jdk11u/jdk11u-windows-x86-32-hotspot)](https://ci.adoptopenjdk.net/job/build-scripts/job/jobs/job/jdk11u/job/jdk11u-windows-x86-32-hotspot) | [![Build Status](https://ci.adoptopenjdk.net/buildStatus/icon?job=build-scripts/jobs/jdk12u/jdk12u-windows-x86-32-hotspot)](https://ci.adoptopenjdk.net/job/build-scripts/job/jobs/job/jdk12u/job/jdk12u-windows-x86-32-hotspot) |
| windows-x86-32-openj9 | [![Build Status](https://ci.adoptopenjdk.net/buildStatus/icon?job=build-scripts/jobs/jdk8u/jdk8u-windows-x86-32-openj9)](https://ci.adoptopenjdk.net/job/build-scripts/job/jobs/job/jdk8u/job/jdk8u-windows-x86-32-openj9) | [![Build Status](https://ci.adoptopenjdk.net/buildStatus/icon?job=build-scripts/jobs/jdk9u/jdk9u-windows-x86-32-openj9)](https://ci.adoptopenjdk.net/job/build-scripts/job/jobs/job/jdk9u/job/jdk9u-windows-x86-32-openj9) | [![Build Status](https://ci.adoptopenjdk.net/buildStatus/icon?job=build-scripts/jobs/jdk10u/jdk10u-windows-x86-32-openj9)](https://ci.adoptopenjdk.net/job/build-scripts/job/jobs/job/jdk10u/job/jdk10u-windows-x86-32-openj9) | [![Build Status](https://ci.adoptopenjdk.net/buildStatus/icon?job=build-scripts/jobs/jdk11u/jdk11u-windows-x86-32-openj9)](https://ci.adoptopenjdk.net/job/build-scripts/job/jobs/job/jdk11u/job/jdk11u-windows-x86-32-openj9) | [![Build Status](https://ci.adoptopenjdk.net/buildStatus/icon?job=build-scripts/jobs/jdk12u/jdk12u-windows-x86-32-openj9)](https://ci.adoptopenjdk.net/job/build-scripts/job/jobs/job/jdk12u/job/jdk12u-windows-x86-32-openj9) |
