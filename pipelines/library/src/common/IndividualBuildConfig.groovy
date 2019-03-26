package common

public class IndividualBuildConfig implements Serializable {
    String ARCHITECTURE
    String TARGET_OS
    String VARIANT
    String JAVA_TO_BUILD
    String TEST_LIST
    String SCM_REF
    String BUILD_ARGS
    String NODE_LABEL
    String CONFIGURE_ARGS
    String OVERRIDE_FILE_NAME_VERSION
    String ADDITIONAL_FILE_NAME_TAG
    String JDK_BOOT_VERSION
    boolean RELEASE
    String PUBLISH_NAME
    String ADOPT_BUILD_NUMBER
    boolean ENABLE_TESTS
    boolean CLEAN_WORKSPACE

    Map<String, ?> toMap() {
        toRawMap().findAll { key, value ->
            value != null
        }
    }

    Map<String, ?> toRawMap() {
        [
                ARCHITECTURE              : ARCHITECTURE,
                TARGET_OS                 : TARGET_OS,
                VARIANT                   : VARIANT,
                JAVA_TO_BUILD             : JAVA_TO_BUILD,
                TEST_LIST                 : TEST_LIST,
                SCM_REF                   : SCM_REF,
                BUILD_ARGS                : BUILD_ARGS,
                NODE_LABEL                : NODE_LABEL,
                CONFIGURE_ARGS            : CONFIGURE_ARGS,
                OVERRIDE_FILE_NAME_VERSION: OVERRIDE_FILE_NAME_VERSION,
                ADDITIONAL_FILE_NAME_TAG  : ADDITIONAL_FILE_NAME_TAG,
                JDK_BOOT_VERSION          : JDK_BOOT_VERSION,
                RELEASE                   : RELEASE,
                PUBLISH_NAME              : PUBLISH_NAME,
                ADOPT_BUILD_NUMBER        : ADOPT_BUILD_NUMBER,
                ENABLE_TESTS              : ENABLE_TESTS,
                CLEAN_WORKSPACE           : CLEAN_WORKSPACE
        ]
    }

    List<?> toBuildParams(def context) {
        def params = toMap()
        List<?> buildParams = []

        buildParams.add(['$class': 'LabelParameterValue', name: 'NODE_LABEL', label: params.get("NODE_LABEL")])
        params
                .findAll { it.key != 'NODE_LABEL' }
                .each({ name, value ->
            if (value != null) {
                switch (value.getClass()) {
                    case String: case Number: buildParams += context.string(name: name, value: value); break
                    case Boolean: buildParams.add(['$class': 'BooleanParameterValue', name: name, value: value]); break
                    default: context.echo("Ignoring config param: " + name + " " + value.getClass())
                }
            }
        })


        return buildParams
    }
}