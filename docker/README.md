# OpenJDK and Docker
Scripts to build dockerfiles and generate various Docker images building OpenJDK

# License
The Dockerfiles generated and associated scripts found in this project are licensed under
the [Apache License 2.0](https://www.apache.org/licenses/LICENSE-2.0.html).

# Steps to build

1. **Checkout the OpenJDK source code** - e.g. `git clone git@github.com:AdoptOpenJDK/openjdk-jdk8u.git ~/AdoptOpenJDK/openjdk-jdk8u`
1. **Run the dockerfile_generator.sh script with the --build flag** - e.g. `./dockerfile_generator.sh --jdk 8 --build`
1. **Run the command printed on screen within the container** - e.g. `/openjdk/build/openjdk-build/makejdk-any-platform.sh -v jdk8`
1. **See the results** - Take a look at the results in the build directory

# Generating Dockerfiles

This script generates dockerfiles that are able to build each specific JDK.
The script takes several options :

| Option                  | Description                                                                      | Example                                                 |
|-------------------------|----------------------------------------------------------------------------------|---------------------------------------------------------|
| -h \| --help            | Prints help for the script option                                                | `./dockerfile_generator.sh --help`                      |
| --build                 | Build the docker image from the generated file & create an interactive container | `./dockerfile_generator.sh --build`                     |
| --clean                 | Removes all dockerfiles from '--path'                                            | `./dockerfile_generator.sh --clean`                     |
| --comments              | Prints comments into the dockerfile                                              | `./dockerfile_generator.sh --comments`                  |
| --path \<FILEPATH\>     | Specify where to save the Dockerfile (defaults to $PWD)                          | `./dockerfile_generator.sh --path /home/user/Documents` |
| --print                 | Print the dockerfile to screen once generated                                    | `./dockerfile_generator.sh --print`                     |
| --openj9                | Make the image able to build a JDK w/ OpenJ9 JIT                                 | `./dockerfile_generator.sh --openj9`                    |
| -v \| --version \<JDK\> | Specify which JDK the image is able to build (defaults to jdk8)                  | `./dockerfile_generator.sh --v jdk11`                   |

By default, the script will generate a Dockerfile to create an image able to build JDK with Hotspot, in the current directory.

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
