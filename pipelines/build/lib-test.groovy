@Library('openjdk-jenkins-helper@master')
import JobHelper
import NodeHelper

println JobHelper
println NodeHelper

println JobHelper.jobIsRunnable("build-scripts/old-stuff/create-build-job")