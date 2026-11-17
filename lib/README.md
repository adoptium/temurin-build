## Build Library

This folder contains the function library for the build repository.

This includes a functionLibrary.sh that can be included in your scripts,
giving people the ability to download files, compare shas, etc, without
wasting the time needed to write code tocover all the edge cases 
(can the file be downloaded, does it match the sha, etc).

The tests folder contains testing for the function library, and will be
run against the function library script whenever any file in lib is changed
(see the github action \"function-lib-checker.yml\" for details)