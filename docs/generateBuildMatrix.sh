#!/bin/bash

# Generates markdown table of build job status

echo "| Platform                  | Java 8 | Java 9 | Java 10 | Java 11 |"
echo "| ------------------------- | ------ | ------ | ------- | ------- |"

rm "/tmp/build.txt"
for i in "8u" "9u" "10u" "11";
do
    curl -s "https://ci.adoptopenjdk.net/job/build-scripts/job/jobs/job/jdk${i}/" | egrep -o "job/jdk${i}u?-[^\/]+" >> "/tmp/build.txt"
done



cat "/tmp/build.txt" | cut -d'/' -f2 | sed -r 's/jdk[0-9]+u?\-//g' | sort | uniq  | while read buildName;
do
    echo -n "| ${buildName} | "
    for i in "8u" "9u" "10u" "11";
    do
        code=$(curl -s -o /dev/null -w "%{http_code}" "https://ci.adoptopenjdk.net/buildStatus/icon?job=build-scripts/jobs/jdk${i}/jdk${i}-${buildName}")
        if [ $code = 200 ]; then
            echo -n "[![Build Status](https://ci.adoptopenjdk.net/buildStatus/icon?job=build-scripts/jobs/jdk${i}/jdk${i}-${buildName})](https://ci.adoptopenjdk.net/job/build-scripts/job/jobs/job/jdk${i}/job/jdk${i}-${buildName})"
        else
            echo -n "N/A"
        fi

        echo -n " | "
    done
    echo ""
done