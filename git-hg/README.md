# git-hg

These scripts are run at https://ci.adoptopenjdk.net/view/git-hg/ and are responsible for updating the AdoptOpenJDK clones of the various OpenJDK mecurial forests that we are interested in building.

## For developers

OpenJDK Source Control repositories are managed using Mercurial. The scripts within this project mirror those Mercurial repositories
to github.com/AdoptOpenJDK/openjdk-jdk\<NN\>u , which then serves as a mirror for AdoptOpenJDK to build the Hotspot variants, as well as providing branches for adding any AdoptOpenJDK vendor "patches" needed.

The OpenJDK Mercurial repositories fall under three categories:
```
- JDK8 Update Repositories   : hg.openjdk.java.net/jdk8u/jdk8u/(corba|hotspot|jaxp|jaxws|nashorn|jdk|langtools)
- JDK11+ Update Repositories : hg.openjdk.java.net/jdk-updates/jdk<NN>u
- JDK "next" Repository      : hg.openjdk.java.net/jdk/jdk
```

# JDK8 Update Repositories
jdk8u/... scripts

TBD

# JDK11+ Update, JDK "next" Repositories
The **mercurialToGit.sh** script mirrors and merges the corresponding Mercurial repository into the matching AdoptOpenJDK mirror:
```
hg.openjdk.java.net/jdk-updates/jdk<NN>u     --->    github.com/AdoptOpenJDK/openjdk-jdk<NN>u (master)
hg.openjdk.java.net/jdk/jdk                  --->    github.com/AdoptOpenJDK/openjdk-jdku (master)
```
This mirroring utilizes the "git-remote-hg" Mercurial fast importer plugin (https://github.com/felipec/git-remote-hg), and mirrors
the Mercurial "default" branch to the "master" branch in the git repo.

The AdoptOpenJDK mirrors also have two vendor branches for AdoptOpenJDK to apply any extra patches needed:
  - "dev"      = "master"(HEAD) + "AdoptOpenJDK Patches"
  - "release"  = "master"(latest build tag) + "AdoptOpenJDK Patches"

**Note For Developers:** Any AdoptOpenJDK Patches must be done on the "release" branch, they will be auto-merged nightly into "dev".

The script merges the appropriate latest merged "master" branch code into both "dev" and "release", it also ensures all the
"AdoptOpenJDK Patches" from the "release" branch are merged into the "dev" branch.

The flow for the merge process is:
```
"Mercurial(default)" ---> "github.com(master)" -BuildTag-> "release" ---> "dev"
                                               -HEAD-> "dev"
```

