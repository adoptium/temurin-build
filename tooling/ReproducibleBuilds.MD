<!-- textlint-disable terminology -->

# Temurin tools and utilities for Reproducible and Comparable OpenJDK Builds

The tooling provided under [tooling](https://github.com/adoptium/temurin-build/tree/master/tooling) enables
support for temurin Reproducible and Comparable Builds. The tools fall into two categories:

1. Reproducible Builds : Tools for helping perform "identical" reproducible builds of Temurin OpenJDK.

2. Comparable Builds : Tools that can help perform "comparison" of different Vendors "identical" builds of OpenJDK
as long as those two builds were built from the identical source, but only differed by vendor string branding.

## Reproducible Build Tools

1. linux_repro_build_compare.sh : Takes as parameters "SBOM URL" of Temurin JDK to be rebuilt, and the official "Temurin JDK.tar.gz".
It will then:

- Setup the identical environment from the properties within the SBOM
- Build the JDK locally
- Download the official "Temurin JDK.tar.gz"
- Compare the locally built JDK with the official Temurin JDK

2. linux_repro_compare.sh : Compares two linux JDK folders:

- linux_repro_compare.sh (temurin|openjdk) JDK_DIR1 (temurin|openjdk) JDK_DIR2
- Calls linux_repro_process.sh to pre-process the folder before comparison. This expands zips and jmods.

3. windows_repro_compare.sh : Compares two windows JDK folders:

- windows_repro_compare.sh (temurin|openjdk) JDK_DIR1 (temurin|openjdk) JDK_DIR2 temp_selfcert_file temp selfcert_pwd
- Calls windows_repro_process.sh to pre-process the folder before comparison. This expands zips and jmods, then deterministically
remove any Signatures from the executeables.

4. mac_repro_compare.sh : Compares two mac JDK folders:

- mac_repro_compare.sh (temurin|openjdk) JDK_DIR1 (temurin|openjdk) JDK_DIR2 temp_selfcert temp selfcert_pwd
- Calls mac_repro_process.sh to pre-process the folder before comparison. This expands zips and jmods, then deterministically
remove any Signatures from the executeables.

## Comparable Build Tools

comparable_patch.sh : Patches a JDK folder to enable "Comparable" comparison of two different Vendor JDK builds.
The patching process involves:

- Expanding all zips and jmods, so executeables can be processed to remove signatures prior to comaprison.
- Removing Signatures (Windows & MacOS).
- Neutralise VS_VERSION_INFO Vendor strings (Windows).
- Remove non-comparable CRC generated uuid values, which are binary values based on the hash of the content (Windows & MacOS).
- Remove Vendor strings embedded in executables, classes and text files.
- Remove module-info differences due to "hash" of Signed module executables
- Remove any non-deterministic build process artifact strings, like Manifest Created-By stamps.

### How to setup and run comparable_patch.sh on Windows

#### Tooling setup:

1. The comparable patch tools, (Windows only) [tooling/src/c/WindowsUpdateVsVersionInfo.c](https://github.com/adoptium/temurin-build/blob/master/tooling/src/c/WindowsUpdateVsVersionInfo.c) and
[src/java/temurin/tools/BinRepl.java](https://github.com/adoptium/temurin-build/blob/master/tooling/src/java/temurin/tools/BinRepl.java) need compiling
before the comparable_patch.sh can be run.

2. Compile [tooling/src/c/WindowsUpdateVsVersionInfo.c](https://github.com/adoptium/temurin-build/blob/master/tooling/src/c/WindowsUpdateVsVersionInfo.c) (Windows only):

- Ensure VS2022 SDK is installed and on PATH
- Compile:
  - cd tooling/src/c
  - cl WindowsUpdateVsVersionInfo.c version.lib

3. Compile [src/java/temurin/tools/BinRepl.java](https://github.com/adoptium/temurin-build/blob/master/tooling/src/java/temurin/tools/BinRepl.java) :

- Ensure suitable JDK on PATH
- cd tooling/src/java
- javac temurin/tools/BinRepl.java

4. Setting environment within a shell :

- [Windows only] For WindowsUpdateVsVersionInfo.exe : export PATH=<temurin-build>/tooling/src/c:$PATH
- [Windows only] For dumpbin.exe MSVC tool : export PATH=/cygdrive/c/progra\~1/micros\~2/2022/Community/VC/Tools/MSVC/14.37.32822/bin/Hostx64/x64:$PATH
- For BinRepl : export CLASSPATH=<temurin-build>/tooling/src/java:$CLASSPATH
- A JDK for running BinRepl java : export PATH=<jdk>/bin:$PATH

#### Running comparable_patch.sh:

1. Unzip your JDK archive into a directory (eg.jdk1)

2. Run comparable_patch.sh

```bash
bash comparable_patch.sh --jdk-dir "<jdk_home_dir>" --version-string "<version_str>" --vendor-name "<vendor_name>" --vendor_url "<vendor_url>" --vendor-bug-url "<vendor_bug_url>" --vendor-vm-bug-url "<vendor_vm_bug_url>" [--patch-vs-version-info]
```

The Vendor strings and urls can be found by running your jdk's "java -XshowSettings":

```java
java -XshowSettings:
...
    java.vendor = Eclipse Adoptium
    java.vendor.url = https://adoptium.net/
    java.vendor.url.bug = https://github.com/adoptium/adoptium-support/issues
    java.vendor.version = Temurin-21.0.1+12
...
```

eg.

```bash
bash ./comparable_patch.sh --jdk-dir "jdk1/jdk-21.0.1+12" --version-string "Temurin-21.0.1+12" --vendor-name "Eclipse Adoptium" --vendor_url "https://adoptium.net/" --vendor-bug-url "https://github.com/adoptium/adoptium-support/issues" --vendor-vm-bug-url "https://github.com/adoptium/adoptium-support/issues"
```

3. Unzip the other Vendor JDK to compare with, say into "jdk2", and run a similar comparable_patch.sh
for that Vendor branding

4. Diff recursively the now Vendor neutralized jdk directories

```bash
diff -r jdk1 jdk2
```

The diff should be "identical" if the two Vendor JDK's are "Comparable", ie."Identical except for the Vendor Branding"
