<!-- textlint-disable terminology -->
# Repository for code and instructions for building OpenJDK binaries, defaulting to Eclipse Temurin™

These scripts can be used to build OpenJDK anywhere but are primarily used by Eclipse Adoptium members (vendors) to build binaries. The scripts default to the use case of building Eclipse Temurin binaries which occurs on the build farm at <https://ci.adoptium.net>. Those binaries are then made available for consumption at <https://adoptium.net> and via the API <https://api.adoptium.net>.

**NOTE** In the future, adoptium.net will transition to being a marketplace for other qualifying vendors as well Eclipse Temurin.

## Where can I find the release status of Eclipse Temurin™ binaries?

Go to the [Eclipse Adoptium Top Level Project repository](https://www.github.com/adoptium/adoptium/issues) for release tracking.

## TL;DR: I want to build a JDK NOW

### Build jdk natively on your system

To do this you will need to have your machine set up with a suitable
compiler and various other tools available. We set up our machines using
ansible playbooks from the [openjdk-infrastructure](https://github.com/adoptopenjdk/openjdk-infrastructure) repository.
You can also look at the [dockerfile generator](https://github.com/adoptium/temurin-build/blob/master/docker/dockerfile-generator.sh) for a list of required packages for Ubuntu.

Once you've got all of the prerequisites installed, clone this openjdk-build
repository (`git clone https://github.com/adoptium/temurin-build` and
kick off a build a follows with this script. The `-J` parameter specifies
the "boot JDK" which should generally be one major version prior to the one
you are building (although one of the same major version will also work).
Note that the build variant defaults to HotSpot if omitted which builds from the same repositories as Temurin.

If you're using wsl, use the `--wsl` flag (ie: `./makejdk-any-platform.sh -J /usr/lib/jvm/java-21-openjdk-amd64 --wsl --create-sbom jdk21`).

```bash
./makejdk-any-platform.sh (-J /usr/lib/jvm/jdk-xx) (--build-variant <hotspot|openj9|corretto|SapMachine|dragonwell|bisheng>) <jdk8u|jdk11u|jdk16u|jdk>
```

e.g.

```bash
./makejdk-any-platform.sh -J /usr/lib/jvm/jdk-10.0.2 --build-variant hotspot jdk11u
```

## How do I build OpenJDK in a docker image?

If you do not want to set up your machine with all the prerequisites for
building OpenJDK, you can use our docker images under the [docker]
directory as follows (first version builds HotSpot, second builds J9 - the
final parameter can be adjusted to build whichever version you want as long
as we can generate valid dockerfile for it):

```bash
./makejdk-any-platform.sh --docker --clean-docker-build jdk8u
./makejdk-any-platform.sh --podman --clean-docker-build --build-variant openj9 jdk11u
```

We test these dockerfiles on a regular basis in the
[Dockerfilecheck](https://ci.adoptium.net/job/DockerfileCheck/) job
to ensure they continue to work in a stable fashion.

## Repository contents

This repository contains several useful scripts in order to build OpenJDK
personally or at build farm scale.

1. The `build-farm` folder contains shell scripts for multi configuration Jenkins
build jobs used for building Adoptium OpenJDK binaries.
1. The `docker` folder contains tools for generating dockerfiles which can be used as part of building
OpenJDK inside a Docker container.
1. The `git-hg` folder has now been moved to it's own separate repository. See [openjdk-mirror-scripts](https://github.com/adoptium/mirror-scripts).
1. The `pipelines` folder has now been moved to a separate repo: <https://github.com/adoptium/ci-jenkins-pipelines>.
1. The `sbin` folder contains the scripts that actually build (Temurin).
`build.sh` is the entry point which can be used stand alone but is typically
called by the `native-build.sh` or `docker-build.sh` scripts (which themselves
are typically called by `makejdk-any-platform.sh`).
1. The `security` folder contains a script and `cacerts` file that is bundled
with the JDK and used when building OpenJDK: the `cacerts` file is an important
file that's used to enable SSL connections.

## The makejdk-any-platform.sh script

`makejdk-any-platform.sh` is the entry point for building (Adoptium) OpenJDK binaries.
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

```bash
USAGE

./makejdk-any-platform [options] version

Please visit https://www.adoptium.net for further support.

VERSIONS

jdk8u - Build Java 8, defaults to https://github.com/adoptium/jdk8u
jdk11u - Build Java 11, defaults to https://github.com/adoptium/jdk11u
jdk16u - Build Java 16, defaults to https://github.com/adoptium/jdk16u
jdk - Build Latest Java (Alpha/Beta), defaults to https://github.com/adoptium/jdk

OPTIONS

-b, --branch <branch>
specify a custom branch to build from, e.g. dev.
For reference, Adoptium GitHub source repositories default to the dev
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
specify any custom user configuration arguments, using
temporary_speech_mark_placeholder in the place of any speech marks.

--clean-git-repo
clean out any 'bad' local git repository you already have.

--create-debug-image
create a debug-image archive with the debug symbols.

--create-jre-image
create the legacy JRE image in addition to the JDK image.

--create-sbom
create the CycloneDX System Bill of Materials (JSON artifact).

-d, --destination <path>
specify the location for the built binary, e.g. /path/.
This is typically used in conjunction with -T to create a custom path
/ file name for the resulting binary.

-D, --docker, --podman
build OpenJDK in a docker/podman container. -D will autodetect, using podman if found, docker otherwise.

--cross-compile
use this if you are cross compiling - it will skip the java -version checks at the end

--debug-docker
debug OpenJDK build script in a docker container. Only valid if -D is selected.

--disable-shallow-git-clone
disable the default fB--depth=1 shallow cloning of git repo(s).

-f, --freetype-dir
specify the location of an existing FreeType library.
This is typically used in conjunction with -F.

--freetype-build-param <parameter>
specify any special freetype build parameters (required for some Operating Systems).

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

--local-dependency-cache-dir <Local dependency cache directory>
specify the location of a local cache of required build dependency jars. If not specified
the following default locations are searched
Windows: c:/dependency_cache
MacOS: ${HOME}/dependency_cache
Unix: /usr/local/dependency_cache

--make-exploded-image
creates an exploded image (useful for codesigning jmods). Use --assemble-exploded-image once you have signed the jmods to complete the packaging steps.

--custom-cacerts <true|false>
If true (default), a custom cacerts file will be generated based on the Mozilla list of CA certificates (see folder security/). If false, the file shipped by OpenJDK will be used.

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

--use-adoptium-devkit <Adoptium DevKit release tag>
Download and use the given DevKit from https://github.com/adoptium/devkit-binaries/releases.
The DevKit is downloaded and unpacked to WORKSPACE_DIR/WORKING_DIR/devkit
and will add the configure arg --with-devkit=WORKSPACE_DIR/WORKING_DIR/devkit.

--use-jep319-certs
Use certs defined in JEP319 in Java 8/9. Deprecated, has no effect.

--user-openjdk-build-root-directory <openjdk build root path>
Use a user specified openjdk build root directory, rather than the OpenJDK git source directory.
The directory must be empty, or not exist (in which case it gets created).

-v, --version
specify the OpenJDK version to build e.g. jdk8u.  Left for backwards compatibility.

-V, --jvm-variant <jvm_variant>
specify the JVM variant (server or client), defaults to server.

Example usage:

./makejdk-any-platform -D jdk8u
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

- Configuration phase is primarily performed by [configureBuild.sh](https://github.com/adoptium/temurin-build/blob/master/configureBuild.sh) and [makejdk-any-platform.sh](https://github.com/adoptium/temurin-build/blob/master/makejdk-any-platform.sh).
- If a docker container is required it is built by [docker-build.sh](https://github.com/adoptium/temurin-build/blob/master/docker-build.sh) otherwise [native-build.sh](https://github.com/adoptium/temurin-build/blob/master/native-build.sh).
- In the build phase [sbin/build.sh](https://github.com/adoptium/temurin-build/blob/master/sbin/build.sh) is invoked either natively or inside the docker container.
`sbin/build.sh` invokes [sbin/prepareWorkspace.sh](https://github.com/adoptium/temurin-build/blob/master/sbin/prepareWorkspace.sh) to download dependencies, source and perform
general preparation.
- Rest of the build and packaging is then handled from `sbin/build.sh`

## Building OpenJDK from other locations

### Building OpenJDK from a non-Adoptium repository

These scripts default to using Adoptium as the OpenJDK source repository to build
from, but you can override this with the `-r` flag. If you want to run from a
non-default branch you can also specify -b e.g.

```bash
./makejdk-any-platform.sh -r https://github.com/sxa/openjdk-jdk8u -b main -J /usr/lib/jvm/java-1.7.0 jdk8u
```

### Building in a custom directory

Example Usage

```bash
./makejdk-any-platform.sh -J /usr/lib/jvm/jdk-10.0.2 -s $HOME/openjdk-jdk11u/src -d $HOME/openjdk-jdk11u/build -T MyOpenJDK11.tar.gz jdk11u
```

This would clone OpenJDK source from <https://github.com/adoptium/openjdk-jdk11u>
to `$HOME/openjdk-jdk11u/src`, configure the build with sensible defaults according
to your local platform and then build OpenJDK and place the result in
`/home/openjdk/target/MyOpenJDK11.tar.gz`.

## Metadata

Alongside the built assets a metadata file will be created with info about the build. This will be a JSON document of the form:

```json
{
    "vendor": "Eclipse Adoptium",
    "os": "mac",
    "arch": "x64",
    "variant": "openj9",
    "variant_version": {
        "major": "0",
        "minor": "22",
        "security": "0",
        "tags": "m2"
    },
    "version": {
        "minor": 0,
        "security": 0,
        "pre": null,
        "adopt_build_number": 0,
        "major": 15,
        "version": "15+29-202007070926",
        "semver": "15.0.0+29.0.202007070926",
        "build": 29,
        "opt": "202007070926"
    },
    "scmRef": "<output of git describe OR buildConfig.SCM_REF>",
    "buildRef": "<build-repo-name/build-commit-sha>",
    "version_data": "jdk15",
    "binary_type": "debugimage",
    "sha256": "<shasum>",
    "full_version_output": "<output of java --version>",
    "configure_arguments": "<output of bash configure>"
}
```

The Metadata class is contained in the [Metadata.groovy](https://github.com/adoptium/ci-jenkins-pipelines/blob/master/pipelines/library/src/common/MetaData.groovy) file and the Json is constructed and written in the [openjdk_build_pipeline.groovy](https://github.com/adoptium/ci-jenkins-pipelines/blob/master/pipelines/build/common/openjdk_build_pipeline.groovy) file.

It is worth noting the additional tags on the SemVer is the build number.

Below are all of the keys contained in the metadata file and some example values that can be present.

----

- `vendor:`
Example values: [`Eclipse Adoptium`, `Alibaba`]

This tag is used to identify the vendor of the JDK being built, this value is set in the [build.sh](https://github.com/adoptium/temurin-build/blob/805e76acbb8a994abc1fb4b7d582486d48117ee8/sbin/build.sh#L183) file and defaults to "Adoptium".

----

- `os:`
Example values: [`windows`, `mac`, `linux`, `aix`, `solaris`]

This tag identifies the operating system the JDK has been built on (and should be used on).

----

- `arch:`
Example values: [`aarch64`, `ppc64`, `s390x`, `x64`, `x86-32`, `arm`]

This tag identifies the architecture the JDK has been built on and it intended to run on.

----

- `variant:`
Example values: [`hotspot`, `openj9`, `corretto`, `dragonwell`, `bisheng`]

This tag identifies the JVM being used by the JDK. "dragonwell" and "bisheng" itself are HotSpot based JVMs but are currently considered their own variants for the purposes of build.
WARN: This will be changed at a later date when we split out JVM from vendor.

----

- `variant_version:`

This tag is used to identify a version number of the variant being built, it currently is exclusively used by OpenJ9 and has the following keys:

- `major:`
Example values: [`0`, `1`]

- `minor:`
Example values: [`22`, `23`, `24`]

- `security:`
Example values: [`0`, `1`]

- `tags:`
Example values: [`m1`, `m2`]

----

- `version:`

This tag contains the full version information of the JDK built, it uses the [VersionInfo.groovy](https://github.com/adoptium/temurin-build/blob/master/pipelines/library/src/common/VersionInfo.groovy) class and the [ParseVersion.groovy](https://github.com/adoptium/temurin-build/blob/master/pipelines/library/src/ParseVersion.groovy) class.

It contains the following keys:

- `minor:`
Example values: [`0`]

- `security:`
Example Values: [`0`, `9`, `252` `272`]

- `pre:`
Example values: [`null`]

- `adopt_build_number:`
Example values: [`0`]
If the `ADOPT_BUILD_NUMBER` parameter is used to build te JDK that value will appear here, otherwise a default value of 0 appears.

- `major:`
Example values: [`8`, `11`, `15`, `16`]

- `version:`
Example values: [`1.8.0_272-202010111709-b09`, `11.0.9+10-202010122348`, `14.0.2+11-202007272039`, `16+19-202010120348`]

- `semver:`
Example values: [`8.0.202+8.0.202008210941`, `11.0.9+10.0.202010122348`, `14.0.2+11.0.202007272039`, `16.0.0+19.0.202010120339`]
Formed from the major, minor, security, and build number by the [formSemver()](https://github.com/adoptium/temurin-build/blob/805e76acbb8a994abc1fb4b7d582486d48117ee8/pipelines/library/src/common/VersionInfo.groovy#L123) function.

- `build:`
Example values: [`6`, `9`, `18`]
The OpenJDK build number for the JDK being built.

- `opt:`
Example values: [`202008210941`, `202010120348`, `202007272039`]

----

- `scmRef:`
Example values: [`dragonwell-8.4.4_jdk8u262-b10`, `jdk-16+19_adopt-61198-g59e3baa94ac`, `jdk-11.0.9+10_adopt-197-g11f44f68c5`, `23f997ca1`]

A reference the the base JDK repository being build, usually including a GitHub commit reference, i.e. `jdk-16+19_adopt-61198-g59e3baa94ac` links to `https://github.com/adoptium/openjdk-jdk/commit/59e3baa94ac` via the commit SHA **59e3baa94ac**.

Values that only contain a commit reference such as `23f997ca1` are OpenJ9 commits on their respective JDK repositories, for example **23f997ca1** links to the commit `https://github.com/ibmruntimes/openj9-openjdk-jdk14/commit/23f997ca1.`

----

- `buildRef:`
Example values: [`openjdk-build/fe0f2dba`, `openjdk-build/f412a523`]
A reference to the build tools repository used to create the JDK, uses the format **repository-name**/**commit-SHA**.

----

- `version_data:`
Example values: [`jdk8u`, `jdk11u`, `jdk14u`, `jdk`]

----

- `binary_type:`
Example values: [`jdk`, `jre`, `debugimage`, `testimage`]

----

- `sha256:`
Example values: [`20278aa9459e7636f6237e85fcd68deec1f42fa90c6c541a2dfa127f4156d3e2`, `2f9700bd75a807614d6d525fbd8d016c609a9ea71bf1ffd5d4839f3c1c8e4b8e`]
A SHA to verify the contents of the JDK.

----

- `full_version_output:`
Example values:

```java
openjdk version \"1.8.0_252\"\nOpenJDK Runtime Environment (Alibaba Dragonwell 8.4.4) (build 1.8.0_252-202010111720-b06)\nOpenJDK 64-Bit Server VM (Alibaba Dragonwell 8.4.4) (build 25.252-b06, mixed mode)\n`
```

The full output of the command `java -version` for the JDK.

----

- `configure_arguments:`
The full output generated by `configure.sh` for the JDK built.
