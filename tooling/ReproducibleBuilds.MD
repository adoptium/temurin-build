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

1. comparable_patch.sh : Patches a JDK folder to enable "Comparable" comparison of two different Vendor JDK builds.
The patching process involves:

- Expanding all zips and jmods, so executeables can be processed to remove signatures prior to comaprison.
- Removing Signatures (Windows & MacOS).
- Neutralise VS_VERSION_INFO Vendor strings (Windows).
- Remove non-comparable CRC generated uuid values, which are binary values based on the hash of the content (Windows & MacOS).
- Remove Vendor strings embedded in executables, classes and text files.
- Remove any non-deterministic build process artifact strings, like Manifest Created-By stamps.
