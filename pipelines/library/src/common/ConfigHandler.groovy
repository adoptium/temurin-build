package common

import java.nio.file.NoSuchFileException
import groovy.json.JsonSlurper

class ConfigHandler {
    private final def context
    private final Map<String, ?> configs
    private final Map ADOPT_DEFAULTS_JSON

    // TODO: Change me
    private final String ADOPT_DEFAULTS_FILE_URL = "https://raw.githubusercontent.com/M-Davies/openjdk-build/parameterised_everything/pipelines/defaults.json"

    /*
    Constructor
    */
    ConfigHandler (def context, Map<String, ?> configs) {
        this.context = context
        this.configs = configs

        def get = new URL(ADOPT_DEFAULTS_FILE_URL).openConnection()
        this.ADOPT_DEFAULTS_JSON = new JsonSlurper().parseText(get.getInputStream().getText()) as Map
    }

    /*
    Getter to retrieve adopt's config defaults
    */
    public Map<String, ?> getAdoptDefaultsJson() {
        return ADOPT_DEFAULTS_JSON
    }

    /*
    Changes dir to Adopt's repo
    */
    public void checkoutAdopt () {
        context.checkout([$class: 'GitSCM',
            branches: [ [ name: ADOPT_DEFAULTS_JSON["repository"]["branch"] ] ],
            userRemoteConfigs: [ [ url: ADOPT_DEFAULTS_JSON["repository"]["url"] ] ]
        ])
    }

    /*
    Changes dir to the user's repo
    */
    public void checkoutUser () {
        context.checkout([$class: 'GitSCM',
            branches: [ [ name: configs["branch"] ] ],
            userRemoteConfigs: [ configs["remotes"] ]
        ])
    }

}