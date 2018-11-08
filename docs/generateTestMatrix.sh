#!/bin/bash

# Generates markdown table of build and test job status

echo "{| class=\"wikitable\""
echo "|-"
echo "! Platform !! externaltest !! systemtest !! openjdktest !! RELEASE"

rm "/tmp/build.txt" 2>&1 > /dev/null
for i in "11";
do
    curl -s "https://ci.adoptopenjdk.net/job/build-scripts/job/jobs/job/jdk${i}/" | egrep -o "job/jdk${i}u?-[^\/]+" >> "/tmp/build.txt"
done

cat "/tmp/build.txt" | cut -d'/' -f2 | sed -r 's/jdk[0-9]+u?\-//g' | sort | uniq | while read buildName;
do
    type="hs"
    if [[ "${buildName}" =~ "openj9" ]]
    then
        type="j9"
    fi

    typeFull=$(echo "${buildName}" | cut -d "-" -f 3)

    buildArch=$(echo "${buildName}" | cut -d "-" -f 2)
    arch=$buildArch
    if [ "$arch" == "x64" ]; then
        arch="x86-64"
    fi

    buildOs=$(echo "${buildName}" | cut -d "-" -f 1)
    os=$buildOs
    if [ "$os" == "mac" ]; then
        os="macos";
    fi

    if [ "$type" == "hs" ]; then

      echo "|- |"
      echo "[https://ci.adoptopenjdk.net/job/build-scripts/job/jobs/job/jdk${i}/job/jdk${i}-${buildName}/ ${buildName}] ||"

      for version in "11";
      do
          for testName in "externaltest"	"systemtest"	"openjdktest";
          do
            url="https://ci.adoptopenjdk.net/job/openjdk${version}_${type}_${testName}_${arch}_${os}"
            code=$(curl -s -o /dev/null -w "%{http_code}" "${url}")
            if [ $code != 404 ]; then
                echo "[${url} <img src='https://ci.adoptopenjdk.net/buildStatus/icon?job=openjdk${version}_${type}_${testName}_${arch}_${os}'>] ||"
            else
                echo "N/A ||"
            fi
          done
          echo "[https://ci.adoptopenjdk.net/job/build-scripts/job/jobs/job/jdk${version}/job/jdk${version}-${buildOs}-${buildArch}-${typeFull}/ <img src='https://ci.adoptopenjdk.net/buildStatus/icon?job=build-scripts/jobs/jdk${version}/jdk${version}-${buildOs}-${buildArch}-${typeFull}'>]"
      done
      echo ""
      echo ""
      echo ""
    fi

done

echo "|}"