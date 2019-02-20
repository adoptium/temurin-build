import org.codehaus.groovy.transform.stc.GroovyTypeCheckingExtensionSupport

class JenkinsTypeCheckHelperExtension extends GroovyTypeCheckingExtensionSupport.TypeCheckingDSL {

    Object run() {
        unresolvedProperty {
            pexp ->
                if (pexp.propertyAsString.equals("scmVars")) {
                    storeType(var, classNodeFor(ScmVarsStub))
                    handled = true
                }
        }

        unresolvedVariable {
            var ->
                if (var.name.equals("JobHelper")) {
                    storeType(var, classNodeFor(JobHelper))
                    handled = true
                } else if (var.name.equals("NodeHelper")) {
                    storeType(var, classNodeFor(NodeHelper))
                    handled = true
                }
        }
    }
}