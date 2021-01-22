package common

import java.nio.file.NoSuchFileException
import groovy.json.JsonSlurper

class RepoHandler {
    private final def context
    private final Map configs
    private Map USER_DEFAULTS_JSON
    private final Map ADOPT_DEFAULTS_JSON

    // TODO: Change me
    private final String ADOPT_DEFAULTS_FILE_URL = "https://raw.githubusercontent.com/M-Davies/openjdk-build/parameterised_everything/pipelines/defaults.json"

    /*
    Constructor
    */
    RepoHandler (def context, Map<String, ?> configs) {
        this.context = context
        this.configs = configs

        def get = new URL(ADOPT_DEFAULTS_FILE_URL).openConnection()
        this.ADOPT_DEFAULTS_JSON = new JsonSlurper().parseText(get.getInputStream().getText()) as Map
    }

    /*
    Getter to retrieve user's git remote config
    */
    public Map<String, ?> getUserRemoteConfigs() {
        return configs
    }

    /*
    Getter to retrieve adopt's defaults
    */
    public Map<String, ?> getAdoptDefaultsJson() {
        return ADOPT_DEFAULTS_JSON
    }

    /*
    Getter to retrieve adopt's defaults
    */
    public Map<String, ?> getUserDefaultsJson() {
        return USER_DEFAULTS_JSON
    }

    /*
    Setter to retrieve and save a user defaults json inside the object
    */
    public Map<String, ?> setUserDefaultsJson(String url) {
        def get = new URL(url).openConnection()
        this.USER_DEFAULTS_JSON = new JsonSlurper().parseText(get.getInputStream().getText()) as Map
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