package common

class MetaData {
    final String vendor
    final String os
    final String arch
    final String variant
    final Map variant_version
    final VersionInfo version
    final String scmRef
    final String buildRef
    final String version_data
    final String full_version_output
    final String configure_arguments
    String binary_type
    String sha256

    MetaData(
        String vendor,
        String os,
        String scmRef,
        String buildRef,
        VersionInfo version,
        String version_data,
        String variant,
        Map variant_version,
        String arch,
        String full_version_output,
        String configure_arguments
    ) {
        this.vendor = vendor
        this.os = os
        this.scmRef = scmRef
        this.buildRef = buildRef
        this.version = version
        this.version_data = version_data
        this.variant = variant
        this.variant_version = variant_version
        this.arch = arch
        this.full_version_output = full_version_output
        this.configure_arguments = configure_arguments
    }

    Map asMap() {
        if (variant_version){
            return [
                vendor      : vendor,
                os          : os,
                arch        : arch,
                variant     : variant,
                variant_version : variant_version,
                version     : version,
                scmRef      : scmRef,
                buildRef    : buildRef,
                version_data: version_data,
                binary_type : binary_type,
                sha256      : sha256,
                full_version_output : full_version_output,
                configure_arguments : configure_arguments
            ]
        } else {
            return [
                vendor      : vendor,
                os          : os,
                arch        : arch,
                variant     : variant,
                version     : version,
                scmRef      : scmRef,
                buildRef    : buildRef,
                version_data: version_data,
                binary_type : binary_type,
                sha256      : sha256,
                full_version_output : full_version_output,
                configure_arguments : configure_arguments
            ]
        }
    }
}