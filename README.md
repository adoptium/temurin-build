# Repository for useful files to build OpenJDK

[![Build Status](https://travis-ci.org/AdoptOpenJDK/openjdk-build.svg?branch=master)](https://travis-ci.org/AdoptOpenJDK/openjdk-build)

AdoptOpenJDK makes use of these scripts to provide a build farm at http://ci.adoptopenjdk.net which produces OpenJDK binaries for consumption via http://www.adoptopenjdk.net

## This repository contains three folders and one script you should be calling to build OpenJDK

1. The `ansible` folder contains Ansible playbooks that can be used to quickly configure potentially multiple target machines
2. The `docker` folder contains a Docker file which can be used to create a Docker container for building OpenJDK
3. The `security` folder contains a script and cacerts file that is bundled with the JDK and used when building OpenJDK: the cacerts file is an important file that's used to enable SSL connections

### Got Docker?

```
Usage: ./makejdk-any-platform.sh --version [version] [options]

Versions:
  jdk8u - https://github.com/AdoptOpenJDK/openjdk-jdk8u
  jdk9 - https://github.com/AdoptOpenJDK/openjdk-jdk9

Options:
  -s, --source <path>        specify the location for the source and dependencies to be cloned
  -d, --destination <path>   specify the location for the tarball (eg. /path/ or /path/here.tar.gz)
  -r, --repository <repo>    specify a custom repository (eg. username/openjdk-jdk8u)
  -b, --branch <branch>      specify a custom branch (eg. dev)
  -k, --keep                 reuse docker container (prevents deleting)
  -j, --jtreg                run jtreg after building
  -S, --ssh                  use ssh when cloning git
  --variant <name>           specify a build variant name, e.g. openj9
```

The simplest way to build OpenJDK using our scripts is to run `makejdk-any-platform.sh` and have your user be in the Docker group on the machine (or prefix all of your Docker commands with `sudo`. This script can be used to create a Docker container that will be configured with all of the required dependencies and a base operating system in order to build OpenJDK

By default the docker container is removed each time and your build will be copied from the container to the host

To override this behaviour, specify the `-k` or `--keep` options.

By providing the -d option to `makejdk.sh`, the resulting zipped tarball will be copied to the value for -d, for example:
`makejdk.sh /target/directory` will result in the JDK being built inside of your Docker container and then copied to /target/directory on the host

For help with getting docker follow the instructions [here](https://docs.docker.com/engine/installation/)


### Prefer to use Ansible?

Remember that when using Ansible the changes will be persistent on your local filesystem: the build process includes downloading and configuring a number of dependencies including gcc and various development libraries: see the Ansible playbook itself to see the full listing

### Building in your local enviromment

You can use the `makejdk-any-platform.sh` script by providing two parameters: the "working directory" (which is where files will be downloaded to: this includes a number of libraries used with OpenJDK itself such as FreeType and ALSA) and the "target directory" which will be used to store the final .tar.gz file containing the j2sdk-image

e.g `./makejdk-any-platform.sh -s /path/to/workspace -d /target/directory`

Note: have a look at the usage of `makejdk-any-platform.sh --help`, the exact usage is available for this script as well.

### None of the above?

You can use the `makejdk.sh` script by providing two parameters: the "working directory" (which is where files will be downloaded to: this includes a number of libraries used with OpenJDK itself such as FreeType and ALSA) and the "target directory" which will be used to store the final .tar.gz file containing the j2sdk-image

e.g `./makejdk.sh -s /path/to/workspace -d /target/directory`


#### Configuring Docker

To use the Docker commands without using the sudo prefix, you will need to be in the Docker group which can be achieved with the following three commands (performed as root)

1. `sudo groupadd docker`: creates the Docker group if it doesn't already exist
2. `sudo gpasswd -a yourusernamehere docker`: adds a user to the Docker group
3. `sudo service docker restart`: restarts the Docker service so the above changes can take effect
