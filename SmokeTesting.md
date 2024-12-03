# General steps to follow for producing Smoke Tests

These are the general steps to execute the Smoke Tests found in[/test/functional/buildAndPackage](https://github.com/adoptium/temurin-build/tree/master/test/functional/buildAndPackage) on your local machine. They are run using the same mechanisms as the AQA test suite, with the TestKitGen ([TKG](https://github.com/adoptium/TKG)) harness that provides a standardized way to deal with these tests under automation.

1. Ensure test machine is set up with test [prereqs](https://github.com/adoptium/aqa-tests/blob/master/doc/Prerequisites.md)
1. Build or download/unpack the SDK you want to test to /someLocation
1. export TEST_JDK_HOME=/someLocation // set test JDK home. On windows, the windows path format is expected. (i.e., TEST_JDK_HOME=C:\someLocation )
1. git clone [https://github.com/adoptium/aqa-tests.git](https://github.com/adoptium/aqa-tests) to /testLocation
1. cd aqa-tests
1. ./get.sh --vendor_repos https://github.com/adoptium/temurin-build --vendor_branches master --vendor_dirs /test/functional
1. ( When running get.sh ensure the vendor parameters are passed correctly, the above example shows how to run the smoke tests contained within the temurin-build repository )
1. cd TKG
1. Export environment variables suitable for the SDK under test and for the test materials being used (i.e., export BUILD_LIST=functional/buildAndPackage, this value details which test material that should be compiled.
1. make compile // fetches test material and compiles it, based on build.xml files in the test directories
1. make _extended.functional // executes the test target (can be test group, level, level.group or specific test). i.e., openjdk (all tests in openjdk group), sanity.functional (all functional tests labelled at sanity level), or in the case of smoke tests which are all tagged to belong to level=extended and group=functional, we use `_extended.functional` and because we have limited BUILD_LIST to the directory where the smoke test material lives, we will only run tests from that directory tagged as extended.functional.
