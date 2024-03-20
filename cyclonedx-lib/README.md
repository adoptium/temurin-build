# CycloneDX support files

## Overview

The Temurin project creates Software Bill of Materials (SBoM) files in the
[CycloneDX](https://cyclonedx.org) format and we use their tooling for doing
so. The files in this directory providers the interface between our build
scripts and the CycloneDX API.

The CycloneDX API which we use is written in java and the documentation for
the API is available at https://cyclonedx.github.io/cyclonedx-core-java

The reference information for the underlying format is available at https://cyclonedx.org/docs/1.5/json/#formulation_items_bom-ref

## Process description

Assuming `--create-sbom` was added the `BUILD_ARGS`, at the end of each
build the build will call `generateSBoM` in
[build.sh](https://github.com/adoptium/temurin-build/blob/master/sbin/build.sh).
This will locate all of the required information, and add it to the SBoM via
helper methods in
[sbom.sh](https://github.com/adoptium/temurin-build/blob/master/sbin/common/sbom.sh).
These functions invoke our
[TemurinGenSBOM](https://github.com/adoptium/temurin-build/blob/master/cyclonedx-lib/src/temurin/sbom/TemurinGenSBOM.java)
java code (this directory) which takes the SBOM file as a parameter as well
as the action to take on that file and adds a suitable section to the SBOM
file.

## Adding a new value

Adding a new entry to the SBoM can either be done by re-using an existing
section, or adding the support for a new section. I'll use the example of a
formulation section (mostly because the author of this added such a section
recently)

1. Check that the version of CycloneDX you are using supports the
    functionality you want. If not, it will need to be updated. To do this
    you need to do two steps:
    - Update the [sha and version files](https://github.com/adoptium/temurin-build/blob/master/cyclonedx-lib/dependency_data) for each jar you plan to change.
    - Ensure [build.getDependency](https://ci.adoptium.net/job/build.getDependency/) is run to pick up the new version
2. If the build and java code does not already have support for the CycloneDX functionality that you need, then follow these steps ([Sample PR](https://github.com/adoptium/temurin-build/pull/3538))
    - Updates to [cyclonedx-lib/TemurinGenSBOM.java](https://github.com/adoptium/temurin-build/blob/master/sbin/common/sbom.sh) to add a new parameter, a new function to implement it, the call to that function from the `switch` functionality in the `main` function
    - Update [cyclonedx-lib/build.xml](https://github.com/adoptium/temurin-build/blob/master/cyclonedx-lib/build.xml) to add tests for the new functionality
    - Add a new function to [sbin/common/sbom.sh](https://github.com/adoptium/temurin-build/blob/master/sbin/common/sbom.sh) to add the fields you need
    - Updates to [sbin/build.sh](https://github.com/adoptium/temurin-build/blob/master/sbin/build.sh) to invoke the new function(s) in sbom.sh
3. Run the build with `--create-sbom` in the `BUILD_ARGS` and check that it produces the desired output.
