# OpenJDK and Docker
Dockerfiles and build scripts for generating various Docker Images building OpenJDK 

**WARN: As of 23rd March 2018 these instructions do not work, there are several issues that need resolving** 

# License
The Dockerfiles and associated scripts found in this project are licensed under
the [Apache License 2.0](http://www.apache.org/licenses/LICENSE-2.0.html).

# Steps to build

1. **Checkout the OpenJDK source code** - e.g. `git clone git@github.com:AdoptOpenJDK/openjdk-jdk8u.git ~/AdoptOpenJDK/openjdk-jdk8u`
1. **Choose the version platform** - e.g. `cd jdk8/x86_64/ubuntu/`
1. **Create the docker image** - e.g. `docker build -t dockeropenjdk .` 
1. **Run the build** - `docker run -it -v <path to source>:/openjdk/build dockeropenjdk`. 
1. **See the results** - Take a look at the results in the build directory

Optionally you can run with Debug (to shell): 

`docker run -it -v <path to source>:/openjdk/build --entrypoint /bin/bash dockeropenjdk`
