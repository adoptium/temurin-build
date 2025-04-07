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

2. windows_repro_build_compare.sh : Takes as parameters "SBOM URL" of Temurin JDK to be rebuilt, and the official Temurin Windows JDK Zip file.
It will then:

- Setup the identical environment from the properties within the SBOM
- Build the JDK locally
- Download the official Temurin Windows JDK Zip file
- Compare the locally built JDK with the official Temurin JDK

3. repro_compare.sh : Compares two JDK folders:

   - repro_compare.sh (temurin|openjdk) JDK_DIR1 (temurin|openjdk) JDK_DIR2 OS
   - Calls repro_process.sh to pre-process the folder before comparison. This expands zips and jmods.
     - On Windows and MacOS it also deterministically removes any signatures from the executables.

4. windows_build_as_temurin.sh : Builds an identical Windows Temurin binary without directly using temurin-build scripts.

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
- Zero out CRC in .gnu_debuglink ELF sections to eliminate .debuginfo-induced differences.

**warning:** If you run `comparable_patch.sh`, do not use `repro_compare.sh` for final comparison. You would get false negatives. Run plain `diff jdk1 jdk2` with any switches you need, or use `PREPROCESS=no repro_compare.sh` with the flag `PREPROCESS=no`. Any other value then `no` would lead again to preprocessing, and thus false negatives.

### How to setup and run comparable_patch.sh on Windows

#### Tooling setup:

1. The comparable patch tools, (Windows only) [tooling/src/c/WindowsUpdateVsVersionInfo.c](https://github.com/adoptium/temurin-build/blob/master/tooling/src/c/WindowsUpdateVsVersionInfo.c) and
[src/java/temurin/tools/BinRepl.java](https://github.com/adoptium/temurin-build/blob/master/tooling/src/java/temurin/tools/BinRepl.java) need compiling
before the comparable_patch.sh can be run.

2. Compile [tooling/src/c/WindowsUpdateVsVersionInfo.c](https://github.com/adoptium/temurin-build/blob/master/tooling/src/c/WindowsUpdateVsVersionInfo.c) (Windows only):

- Ensure VS2022 SDK is installed and on PATH
- Compile:
  - cd tooling/src/c
  - run vcvarsall.bat as your arch needs. Eg: vcvars64.bat on x64 windows
    - You can set up INCLUDES manually but it is not worthy
    - vcvarsall.bat creates a subshell, if you do not want it to create a subshell, use `call` eg `call vcvars64.bat` instead of the direct execution.
  - cl WindowsUpdateVsVersionInfo.c version.lib

3. Compile [src/java/temurin/tools/BinRepl.java](https://github.com/adoptium/temurin-build/blob/master/tooling/src/java/temurin/tools/BinRepl.java) :

- Ensure suitable JDK on PATH
  - **do not** use JDK you are just patching, as that JDK gets **broken** by the process of patching
- cd tooling/src/java
- javac temurin/tools/BinRepl.java

4. Setting environment within a shell :

- [Windows only] For WindowsUpdateVsVersionInfo.exe : export PATH=<temurin-build>/tooling/src/c:$PATH
- [Windows only] For dumpbin.exe MSVC tool : export PATH=/cygdrive/c/progra\~1/micros\~2/2022/Community/VC/Tools/MSVC/14.37.32822/bin/Hostx64/x64:$PATH
- [Windows only] For signtool.exe MSVS tool : export PATH=/cygdrive/c/progra\~2/wi3cf2\~1/10/bin/10.0.22621.0/x64:$PATH
- For BinRepl.class : export CLASSPATH=<temurin-build>/tooling/src/java:$CLASSPATH
- A JDK for running BinRepl java : export PATH=<jdk>/bin:$PATH

##### Cygwin treacherousness

- It is extremely difficult (maybe impossible) to invoke `vcvarsall.bat+cl` in cygwin directly
- Thus, it is recommended to launch this via `cmd -c` or preferably by an executable `.bat` file such as:

```bash
 pushd "$MSVSC/BUILD/TOOLS"
    rm -f WindowsUpdateVsVersionInfo.obj
    echo "
      call vcvars64.bat
      cl $(cygpath -m $YOUR_WORKDIR/temurin-build/tooling/src/c/WindowsUpdateVsVersionInfo.c) version.lib
    " > setupEnvAndCompile.bat
    chmod 755 setupEnvAndCompile.bat
    ./setupEnvAndCompile.bat
    # copy it to any dir on path or add this dir to path
    mv WindowsUpdateVsVersionInfo.exe  "$FUTURE_PATH_ADDITIONS"
    rm WindowsUpdateVsVersionInfo.obj setupEnvAndCompile.bat
  popd
```

- NOTE: The default paths should work fine. In Cygwin, they are usually at:
  - MSVSC cl/bat files in `/cygdrive/c/Program Files/Microsoft Visual Studio/` under `Hostx64/x64` (or similar) and `Auxiliary/Build` dirs
  - the signtool.exe then in `/cygdrive/c/Program Files (x86)/Windows Kits`. Again in arch-specific dir like `x64`

- NOTE: Using `cygpath` is sometimes necessary. However, Java *binaries* can have issues with it:
  - e.g., Use `cygpath` for `$CLASSPATH`,
  - or javac it is mandatory:

```bash
      ftureDir="$(pwd)/classes"
      if uname | grep CYGWIN ; then
        ftureDir=$(cygpath -m "${ftureDir}")
      fi
      $AQA_DIR/$jdkName/bin/javac -d "${ftureDir}" "../../tooling/src/java/temurin/tools/BinRepl.java"
```

#### Running comparable_patch.sh:

1. Unzip your JDK archive into a directory (eg.jdk1)
   - Note, that jdk will be modified, so the location must be writable
   - if it is in admin/root location, `cp -rL` it to some temp directory.

2. Run comparable_patch.sh

```bash
bash comparable_patch.sh --jdk-dir "<jdk_home_dir>" --version-string "<version_str>" --vendor-name "<vendor_name>" --vendor_url "<vendor_url>" --vendor-bug-url "<vendor_bug_url>" --vendor-vm-bug-url "<vendor_vm_bug_url>" [--patch-vs-version-info]
```

The Vendor strings and URLs can be found by running your jdk's "java -XshowSettings":

```java
java -XshowSettings:
...
    java.vendor = Eclipse Adoptium
    java.vendor.url = https://adoptium.net/
    java.vendor.url.bug = https://github.com/adoptium/adoptium-support/issues
    java.vendor.version = Temurin-21.0.1+12
...
```

In cygwin, you must handle the trailing `\r` otherwise it will fail later. sed `\r`  away as eg: `sed 's/\r.*//'` is usually enough.

e.g.,:

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
