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

    String getResult() {}

    Integer getNumber() {}

    String sh(String s) {}

    String sh(Map s) {}

    String cleanWs(Map s) {}

    String withEnv(List l, Closure c) {}

    String checkout(String s) {}

    String checkout(Map<String, ?> s) {}

    String writeFile(Map s) {}

    Configuration load(String s) {}

    String readFile(String s) {}

    String ws(String s, Closure) {}
}
