package testDoubles

import JobHelper
import NodeHelper

// Stub to fix compilation

class ContextStub {
    NodeHelper NodeHelper;
    JobHelper JobHelper

    class Configuration {
        Map<String, ?> targetConfigurations;
    }

    class CustomScript {
        void regenerate() {}
    }

    String scm

    ContextStub string(Map s) {}

    ContextStub bool(Map s) {}

    ContextStub echo(String s) {}

    ContextStub error(String s) {}

    ContextStub catchError(Closure s) {}

    ContextStub node(String s, Closure) {}

    ContextStub stage(String s, Closure) {}

    ContextStub build(Map s) {}

    ContextStub jobDsl(Map) {}

    ContextStub copyArtifacts(Map) {}

    ContextStub archiveArtifacts(Map) {}

    ContextStub parallel(Map) {}

    ContextStub specific(String) {}

    ContextStub library(Map) {}

    ContextStub docker

    ContextStub inside(Closure c) {}

    ContextStub image(String) {}

    ContextStub build(String s, Closure) {}

    ContextStub pull() {}

    String minus(String s) {}

    String split(String s) {}

    String getResult() {}

    Integer getNumber() {}

    String sh(String s) {}

    String sh(Map s) {}

    String cleanWs(Map s) {}

    String withEnv(List l, Closure c) {}

    String checkout(String s) {}

    String step(Map<String, ?> s) {}

    String checkout(Map<String, ?> s) {}

    String writeFile(Map s) {}

    Closure<CustomScript> load(String s) {}

    String readFile(String file) {}

    Map<String, ?> readJSON(String file) {}

    String entrySet() {}

    String remove() {}

    String ws(String s, Closure) {}

    String getAbsoluteUrl() {}

    String WORKSPACE

    ContextStub timestamps(Closure ignore) {}

    ContextStub timeout(Map, Closure) {}

    ContextStub sleep(Map) {}

    String overrideScmref() {}
}
