# OpenJDK and Docker
Dockerfiles and build scripts for generating various Docker Images building OpenJDK 

**WARN: As of 23rd March 2018 these instructions do not work, there are several issues that need resolving** 

# License
The Dockerfiles and associated scripts found in this project are licensed under
the [Apache License 2.0](https://www.apache.org/licenses/LICENSE-2.0.html).

# Steps to build

1. **Checkout the OpenJDK source code** - e.g. `git clone git@github.com:AdoptOpenJDK/openjdk-jdk8u.git ~/AdoptOpenJDK/openjdk-jdk8u`
1. **Choose the version platform** - e.g. `cd jdk8/x86_64/ubuntu/`
1. **Create the docker image** - e.g. `docker build -t dockeropenjdk .` 
1. **Run the build** - `docker run -it -v <path to source>:/openjdk/build dockeropenjdk`. 
1. **See the results** - Take a look at the results in the build directory

Optionally you can run with Debug (to shell): 

`docker run -it -v <path to source>:/openjdk/build --entrypoint /bin/bash dockeropenjdk`

# Building a JDK, using Docker containers with buildDocker.sh

This script will automatically build a JDK inside a docker container.
There are several options that the script can take :

| Option | Description            | Example                                          |
|--------|------------------------|--------------------------------------------------|
| -v     | JDK version choice     | `./buildDocker.sh -v jdk8`                       |
| -a     | Test all JDK versions  | `./buildDocker.sh -a`                            |
| -j9    | Build JDK with OpenJ9  | `./buildDocker.sh -v jdk8u -j9`                  |
| -J     | Set JDK Boot directory | `./buildDocker.sh -v jdk8u -J /path/to/boot/jdk` |

When not specified, the JDK will be built with Hotspot and attempt to detect the boot jdk directory.
