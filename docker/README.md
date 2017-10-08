# OpenJDK and Docker
Dockerfiles and build scripts for generating various Docker Images building
OpenJDK 

# License
The Dockerfiles and associated scripts found in this project are licensed under
the [Apache License 2.0.](http://www.apache.org/licenses/LICENSE-2.0.html).

# Steps to build

1. Checkout the source code into <path to source>
2. Run the docker image (as below)
3. Take a look at the results in the build directory

# Hints & Tips

 - Build (from build/docker dir):
	`docker build -t dockeropenjdk .`

 - Run:
	`docker run -it -v <path to source>:/openjdk/build dockeropenjdk`

 - Debug (to shell):
	`docker run -it -v <path to source>:/openjdk/build --entrypoint /bin/bash dockeropenjdk`

