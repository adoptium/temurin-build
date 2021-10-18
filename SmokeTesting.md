# General steps to follow for producing Smoke Tests

These are the general steps to produce Smoke Test on your local machine. TestKitGen, a thin veneer used to standardize the diverse set of test frameworks employed by the underlying tests.

1. Ensure test machine is set up with test [prereqs](https://github.com/eclipse-openj9/openj9/blob/master/test/docs/Prerequisites.md)
2. Build or download/unpack the SDK you want to test to /someLocation
3. export TEST_JDK_HOME=/someLocation // set test JDK home. On windows, the windows path format is expected. (i.e., TEST_JDK_HOME=C:\someLocation )
4. git clone [https://github.com/adoptium/aqa-tests.git](https://github.com/adoptium/aqa-tests) to /testLocation
5. cd aqa-tests
6. ./get.sh
7. cd TKG
8. Export environment variables suitable for the SDK under test (i.e., export BUILD_LIST=functional )
9. make compile // fetches test material and compiles it, based on build.xml files in the test directories
10. make _extended.functional // executes the test target (can be test group, level, level.group or specific test). i.e., openjdk (all tests in openjdk group), sanity.functional (all functional tests labelled at sanity level), or in the case of smoke tests which are all tagged to belong to level=extended and group=functional, we use _extended.functional and because we have limited BUILD_LIST to the directory where the smoke test material lives, we will only run tests from that directory tagged as extended.functional.