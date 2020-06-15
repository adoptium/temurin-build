#!/bin/bash

# Generates markdown table of build job status

echo "| Platform                  | Java 8 | Java 9 | Java 10 | Java 11 | Java 12 | Java 13 | Java 14 | Java 15 | Java HEAD |"
echo "| ------------------------- | ------ | ------ | ------- | ------- | ------- | ------- | ------- | ------- | --------- |"

if [[ -f "/tmp/build.txt" ]]; then
  echo "Removing previous /tmp/build.txt file"
  rm "/tmp/build.txt"
fi
for i in "jdk8u" "jdk9u" "jdk10u" "jdk11u" "jdk12u" "jdk13u" "jdk14u" "jdk15" "jdk";
do
    curl -s "https://ci.adoptopenjdk.net/job/build-scripts/job/jobs/job/${i}/" | egrep -o "job/${i}-[^\/]+" >> "/tmp/build.txt"
done

# The sed command fails on Mac OS X, but those users can install gnu-sed
echo "Writing out build status to /tmp/build.txt - take the contents of this file and update README.md with it."
echo "This will take a few minutes to complete."
cat "/tmp/build.txt" | cut -d'/' -f2 | sed -r 's/jdk[0-9]+u?\-//g' | sort | uniq | while read buildName;
do
    # buildName should be of the form: aix-ppc64-hotspot
    echo -n "| ${buildName} | "
    for i in "jdk8u" "jdk9u" "jdk10u" "jdk11u" "jdk12u" "jdk13u" "jdk14u" "jdk15" "jdk";
    do
        code=$(curl -s -o /dev/null -w "%{http_code}" "https://ci.adoptopenjdk.net/buildStatus/icon?job=build-scripts/jobs/${i}/${i}-${buildName}")
        if [[ ${code} = 200 ]]; then
            echo -n "[![Build Status](https://ci.adoptopenjdk.net/buildStatus/icon?job=build-scripts/jobs/${i}/${i}-${buildName})](https://ci.adoptopenjdk.net/job/build-scripts/job/jobs/job/${i}/job/${i}-${buildName})"
        else
            echo -n "N/A"
        fi

        echo -n " | "
    done
    echo ""
done
