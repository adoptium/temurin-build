#!/bin/bash
# shellcheck disable=SC1091
################################################################################
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
################################################################################

################################################################################
#
# This script takes a list of JDK major versions and outputs a list of
# the latest failed attempts to build Temurin at the Eclipse Adoptium project.
# We then use a series of regular expressions to identify the cause of each
# failure, and to output useful information to aid triage.
#
################################################################################

declare -a arrayOfFailedJobs
declare -a arrayOfRegexsForFailedJobs
declare -a arrayOfErrorLinesForFailedJobs
declare -a arrayOfAllJDKVersions
declare -a arrayOfUs
declare -a buildIssues

headJDKVersion=9999

# Imports a series of arrays related to the regular expressions we use to recognise failures:
# arrayOfRegexes, arrayOfRegexMetadata, arrayOfRegexPreventability, and arrayOfFailureSources
. ./tooling/build_autotriage/autotriage_regexes.sh

# All temurin-available platforms.
declare -a temurinPlatforms
# The first jdk major version on that platform. 
declare -a platformStart
# The last jdk major version on that platform ("99" for ongoing).
declare -a platformEnd

totalBuildFailures=0
totalTestFailures=0

temurinPlatforms+=("aix-ppc64");            platformStart+=(8);  platformEnd+=(99)
temurinPlatforms+=("alpine-linux-aarch64"); platformStart+=(21); platformEnd+=(99)
temurinPlatforms+=("alpine-linux-x64");     platformStart+=(8);  platformEnd+=(99)
temurinPlatforms+=("linux-aarch64");        platformStart+=(8);  platformEnd+=(99)
temurinPlatforms+=("linux-arm");            platformStart+=(8);  platformEnd+=(99)
temurinPlatforms+=("linux-ppc64le");        platformStart+=(8);  platformEnd+=(99)
temurinPlatforms+=("linux-s390x");          platformStart+=(11); platformEnd+=(99)
temurinPlatforms+=("linux-x64");            platformStart+=(8);  platformEnd+=(99)
temurinPlatforms+=("mac-aarch64");          platformStart+=(11); platformEnd+=(99)
temurinPlatforms+=("mac-x64");              platformStart+=(8);  platformEnd+=(99)
temurinPlatforms+=("solaris-sparcv9");      platformStart+=(8);  platformEnd+=(8)
temurinPlatforms+=("solaris-x64");          platformStart+=(8);  platformEnd+=(8)
temurinPlatforms+=("windows-x64");          platformStart+=(8);  platformEnd+=(99)
temurinPlatforms+=("windows-x86-32");       platformStart+=(8);  platformEnd+=(17)

# This stores any error messages that did not terminate the triage script altogether.
errorLog() {
  buildIssues+=("$1")
  echo "ERROR FOUND: Issue ${#buildIssues[@]}: $1"
}

# Parses the arguments to this script.
argumentParser() {
  if [ "$#" -lt 1 ]; then
    echo "Illegal argument/s. You must specify at least one jdk version."
    exit 1
  fi

  while [[ $# -gt 0 ]]
  do
    if [[ ! $1 =~ ^jdk[0-9]+[u]?$ ]]; then
      if [[ ! $1 =~ ^jdk[0-9]+head?$ ]]; then
        echo "Script has failed. Reason: Illegal argument/s (name)."
        echo "Correct argument format is: jdk#[u|head]"
        exit 1
      fi
    fi

    if [[ $1 =~ ^jdk[0-9]+$ ]]; then
      arrayOfAllJDKVersions+=("${1:3}")
      arrayOfUs+=("")
    elif [[ $1 =~ ^jdk[0-9]+head$ ]]; then
      arrayOfAllJDKVersions+=("${1:3:-4}")
      arrayOfUs+=("")
      headJDKVersion="${1:3:-4}"
    else
      arrayOfAllJDKVersions+=("${1:3:-1}")
      arrayOfUs+=("u")
    fi

    echo "JDK version identified: ${1:3}"
    shift
  done
}

# Iterates over the supplied JDK versions and identifies the latest timer-triggered build URLs for each version.
# This function then checks that we're building Eclipse Temurin on every platform we should be, and makes a list
# of all the failing builds.
identifyFailedBuildsInTimerPipelines() {
  # Iterate over jdk versions.
  echo "Iterating over jdk versions."
  for v in "${!arrayOfAllJDKVersions[@]}"
  do
    # First we find the latest timer-initiated pipeline for this JDK version.
    echo "wgetting https://trss.adoptium.net/api/getBuildHistory?buildName=openjdk${arrayOfAllJDKVersions[v]}-pipeline"
    latestTimerPipelineRaw=$(wget -q -O - "https://trss.adoptium.net/api/getBuildHistory?buildName=openjdk${arrayOfAllJDKVersions[v]}-pipeline")
    latestTimerPipelineRaw="${latestTimerPipelineRaw},HereIsTheEndOfAVeryLongFile"
    latestTimerPipeline=""
    latestTimerJenkinsJobID=""
    oldIFS=$IFS
    IFS=","

    # Here we identify the latest pipeline that wasn't run by a user.
    # This is to avoid triaging a pipeline that uses a non-standard framework, and is 
    # therefore not representative of the quality of Temurin pipelines during a release.
    for jsonEntry in $latestTimerPipelineRaw
    do
      if [[ $jsonEntry =~ ^\[\{\"_id\".* ]]; then
        latestTimerPipeline=${jsonEntry:9:-1}
      elif [[ $jsonEntry =~ ^\{\"_id\".* ]]; then
        latestTimerPipeline=${jsonEntry:8:-1}
      fi

      if [[ $jsonEntry =~ ^\"buildNum\"\:[0-9]+$ ]]; then
        latestTimerJenkinsJobID=${jsonEntry:11}
      fi

      if [[ ! $jsonEntry =~ .*user.* ]]; then
        if [[ $jsonEntry =~ ^\"startBy\"\:\"timer\"[\}]?$ ]]; then
          break
        elif [[ $jsonEntry =~ ^\"startBy\"\:\".*build-scripts/weekly-openjdk.* ]]; then
          break
        elif [[ $jsonEntry =~ ^\"startBy\"\:\".*releaseTrigger_[0-9]+ea.* ]]; then
          break
        fi
      fi

      if [[ $jsonEntry =~ ^HereIsTheEndOfAVeryLongFile$ ]]; then
        errorLog "Could not find any timer/ea-tag triggered pipeline jobs for jdk${arrayOfAllJDKVersions[v]}${arrayOfUs[v]}. Skipping to the next jdk version."
        continue 2
      fi
    done

    echo "Found TRSS pipeline id for jdk${arrayOfAllJDKVersions[v]}${arrayOfUs[v]} - ${latestTimerPipeline}"
    echo "Whose URL is: https://ci.adoptium.net/job/build-scripts/job/openjdk${arrayOfAllJDKVersions[v]}-pipeline/${latestTimerJenkinsJobID}/"

    # Now grab a full list of builds launched by this pipeline.
    jdkJenkinsJobVersion="jdk${arrayOfAllJDKVersions[v]}${arrayOfUs[v]}"
    if [[ ${arrayOfAllJDKVersions[v]} -eq headJDKVersion ]]; then
      jdkJenkinsJobVersion="jdk"
    fi
    echo "wgetting https://trss.adoptium.net/api/getAllChildBuilds?parentId=${latestTimerPipeline}&buildNameRegex=^jdk${arrayOfAllJDKVersions[v]}${arrayOfUs[v]}.*temurin$"
    listOfPipelineBuilds=$(wget -q -O - "https://trss.adoptium.net/api/getAllChildBuilds?parentId=${latestTimerPipeline}&buildNameRegex=^${jdkJenkinsJobVersion}\-.*temurin$")
    declare -a listOfBuildNames
    declare -a listOfBuildNums
    declare -a listOfBuildResults

    shorterListOfBuilds=""
    for jsonEntry in $listOfPipelineBuilds
    do
      if [[ $jsonEntry =~ ^\"buildName\"\:.* ]]; then
        listOfBuildNames+=("${jsonEntry:13:-1}")
        shorterListOfBuilds+="${jsonEntry},"
      elif [[ $jsonEntry =~ .*\"buildNum\"\.* ]]; then
        listOfBuildNums+=("${jsonEntry:11}")
      elif [[ $jsonEntry =~ .*\"buildResult\".* ]]; then
        listOfBuildResults+=("${jsonEntry:15:-1}")
        continue
      fi
    done

    echo "That pipeline's builds have been identified. Now validating them."

    IFS=$oldIFS

    # Now iterate over platforms to make sure we're launching every platform we should,
    # and that we're not running builds for any platform we shouldn't be.
    triageThesePlatforms=","
    for p in "${!temurinPlatforms[@]}"
    do
      if [[ $shorterListOfBuilds =~ .*\"buildName\"\:\"${jdkJenkinsJobVersion}\-${temurinPlatforms[p]}\-temurin\".* ]]; then
        if [[ ${arrayOfAllJDKVersions[v]} -lt ${platformStart[p]} ]]; then
          errorLog "Error: Platform ${temurinPlatforms[p]} should not be built for ${jdkJenkinsJobVersion}. Will not triage."
          continue
        fi
        if [[ ${arrayOfAllJDKVersions[v]} -gt ${platformEnd[p]} ]]; then
          errorLog "Error: Platform ${temurinPlatforms[p]} should not be built for ${jdkJenkinsJobVersion}. Will not triage."
          continue
        fi
      else
        if [[ ${arrayOfAllJDKVersions[v]} -ge ${platformStart[p]} ]]; then
          if [[ ${arrayOfAllJDKVersions[v]} -le ${platformEnd[p]} ]]; then
            errorLog "Error: Platform ${temurinPlatforms[p]} should be built for ${jdkJenkinsJobVersion}, but was not launched."
            echo "DEBUG: Looked for this: \"buildName\":\"${jdkJenkinsJobVersion}-${temurinPlatforms[p]}-temurin\""
            echo "DEBUG: In this: $shorterListOfBuilds"
            echo "------"
            continue
          fi
        fi
      fi
      # If we get to this stage of the loop, then this is a platform that was both *meant* to be built, and *was* built (or attempted).
      triageThesePlatforms+="${jdkJenkinsJobVersion}-${temurinPlatforms[p]}-temurin,"
    done

    if [[ ${triageThesePlatforms} = "" ]]; then
      errorLog "Cannot find any valid build platforms launched by jdk ${arrayOfAllJDKVersions[v]}${arrayOfUs[v]} pipeline ${latestTimerJenkinsJobID}. Skipping to the next jdk version."
      continue
    fi
    echo "Platforms validated. Identifying build numbers for these platforms: ${triageThesePlatforms:1:-1}"

    # Iterate over the platforms we need to triage and find the build numbers for 
    # any build that failed or was aborted (includes propagated test failures).
    for b in "${!listOfBuildNames[@]}"
    do
      if [[ $triageThesePlatforms =~ .*,${listOfBuildNames[$b]},.* ]]; then
        if [[ ! ${listOfBuildResults[$b]} =~ ^SUCCESS$ ]]; then
          if [[ ! ${listOfBuildResults[$b]} =~ ^UNSTABLE$ ]]; then
            jdkJenkinsJobVersion="jdk${arrayOfAllJDKVersions[v]}${arrayOfUs[v]}"
            if [[ ${arrayOfAllJDKVersions[v]} -eq headJDKVersion ]]; then
              jdkJenkinsJobVersion="jdk"
            fi
            failedJobLink="https://ci.adoptium.net/job/build-scripts/job/jobs/job/${jdkJenkinsJobVersion}/job/${listOfBuildNames[$b]}/${listOfBuildNums[$b]}/"
            echo "Identified a failed build for triage: ${failedJobLink}"
            arrayOfFailedJobs+=("${failedJobLink}")
          fi
        fi
      fi
    done
    echo "Build numbers found, and failures will be added to the array of builds to be triaged."
  done
}

# Takes a single failed jenkins build job URL as a string, and identifies the source of
# the failure if possible.
# Uses: arrayOfRegexes, arrayOfRegexMetadata, arrayOfRegexPreventability
buildFailureTriager() {
  echo "Triaging jobs now."
  # Iterate over the failures found and triage them against the pending array of regexes.
  for failedJob in "${arrayOfFailedJobs[@]}"; do
    wget -q -O - "${failedJob}/consoleText" > ./jobOutput.txt
    # If the file size is beyond 50m bytes, then report script error and do not triage, for efficiency.
    fileSize=$(wc -c < ./jobOutput.txt)
    if [[ ${fileSize} -gt 52500000 ]]; then
      arrayOfRegexsForFailedJobs+=("Unmatched")
      arrayOfErrorLinesForFailedJobs+=("Output size was ${fileSize} bytes")
      totalBuildFailures=$((totalBuildFailures+1))
      continue
    fi
    while IFS= read -r jobOutputLine; do
      for regexIndex in "${!arrayOfRegexes[@]}"; do
        # When a regex matches, store the id of the regex we matched against, and also the line of output that matched the regex.
        if [[ "$jobOutputLine" =~ ${arrayOfRegexes[regexIndex]} ]]; then
          arrayOfRegexsForFailedJobs+=("$regexIndex")
          arrayOfErrorLinesForFailedJobs+=("$jobOutputLine")
          if [[ ${arrayOfFailureSources[regexIndex]} = 0 ]]; then
            totalBuildFailures=$((totalBuildFailures+1))
          else
            totalTestFailures=$((totalTestFailures+1))
          fi
          continue 3
        fi
      done
    done < ./jobOutput.txt
    # If we reach this line, then we have not matched any of the regexs
    arrayOfRegexsForFailedJobs+=("Unmatched")
    arrayOfErrorLinesForFailedJobs+=("No error found")
    totalBuildFailures=$((totalBuildFailures+1))
  done
    echo "Triage has ended."
}

# Stores everything we've found in a markdown-formatted file.
generateOutputFile() {
  { echo "---";
    echo "name: Build Issue Summary";
    echo "about: For triaging the nightly and weekend build failures";
    echo "title: Build Issue Summary for {{ date | date('YYYY-MM-DD') }}";
    echo "labels: 'weekly-build-triage'";
    echo "---";
    echo "";
    echo "# Summary"
    echo "Build failures: ${totalBuildFailures}"
    echo "Test failures: ${totalTestFailures}"
    echo ""
    if [[ ${#arrayOfFailedJobs[@]} -gt 0 ]]; then
      echo "# Failed Builds"
      for failedJobIndex in "${!arrayOfFailedJobs[@]}"
      do
        regexID="${arrayOfRegexsForFailedJobs[failedJobIndex]}"
        echo "Failure: ${arrayOfFailedJobs[failedJobIndex]}"
        if [[ ${regexID} =~ Unmatched ]]; then
          echo "Cause: ${arrayOfErrorLinesForFailedJobs[failedJobIndex]}"
        else
          echo "Cause: ${arrayOfRegexMetadata[regexID]}"
          preventable="yes"
          if [[ "${arrayOfRegexPreventability[regexID]}" -gt 0 ]]; then
            preventable="no"
          fi
          echo "Preventable: ${preventable}"
          echo "\`\`\`"
          echo "${arrayOfErrorLinesForFailedJobs[failedJobIndex]}"
          echo "\`\`\`"
        fi
        echo ""
      done
      echo "#  End of list"
    else
      echo "All build jobs passed. Huzzah!"
    fi
    if [[ ${#buildIssues[@]} -gt 0 ]]; then
      echo "# Script Issues"
      for issueID in "${!buildIssues[@]}"
      do
        echo "- Issue ${issueID}: ${buildIssues[issueID]}"
      done
      echo "# End of Issues"
    fi
  } >> build_triage_output.md
}

# @@@@@@@@@@@@ Script execution starts here @@@@@@@@@@@@

echo "Build AutoTriage is starting."

argumentParser "$@"

identifyFailedBuildsInTimerPipelines

buildFailureTriager 

generateOutputFile

echo "Build AutoTriage is complete."
