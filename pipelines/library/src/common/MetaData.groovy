package common

class MetaData {
    final String WARNING = "THIS METADATA FILE IS STILL IN ALPHA DO NOT USE ME"
    final String os
    final String arch
    final String variant
    final VersionInfo version
    final String scmRef
    final String version_data
    final String full_version_output
    final String configure_arguments
    String binary_type
    String sha256

    MetaData(
        String os,
        String scmRef,
        VersionInfo version,
        String version_data,
        String variant,
        String arch,
        String full_version_output,
        String configure_arguments
    ) {
        this.os = os
        this.scmRef = scmRef
        this.version = version
        this.version_data = version_data
        this.variant = variant
        this.arch = arch
        this.full_version_output = full_version_output
        this.configure_arguments = configure_arguments
    }

    Map asMap() {
        return [
                WARNING     : WARNING,
                os          : os,
                arch        : arch,
                variant     : variant,
                version     : version,
                scmRef      : scmRef,
                version_data: version_data,
                binary_type : binary_type,
                sha256      : sha256,
                full_version_output : full_version_output,
                configure_arguments : configure_arguments
        ]
    }
}