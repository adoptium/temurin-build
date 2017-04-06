# OpenJDK - Source

## Branches

**IMPORTANT**

* main - Is the branch which is a direct clone of the corresponding mercurial forest
* dev - Is the branch that AdoptOpenJDK has made changes from main in order to build it within the build farm at http://ci.adoptopenjdk.net

End users using this repo directly should **carefully** choose the branch they are working on

## Simple Build Instructions

  1. Get the necessary system software/packages installed on your system, see
     http://hg.openjdk.java.net/jdk8/jdk8/raw-file/tip/README-builds.html

  1. If you don't have a jdk7u7 or newer jdk, download and install it from
     http://java.sun.com/javase/downloads/index.jsp
     Add the /bin directory of this installation to your PATH environment
     variable.

  2. Configure the build:
       `bash ./configure`

  3. Build the OpenJDK:
       `make all`

where make is GNU make 3.81 or newer, /usr/bin/make on Linux usually
is 3.81 or newer. Note that on Solaris, GNU make is called "gmake".

The resulting JDK image should be found in build/*/images/j2sdk-image
