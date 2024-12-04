#!/bin/bash
# shellcheck disable=SC1091
# ********************************************************************************
# Copyright (c) 2023 Contributors to the Eclipse Foundation
#
# See the NOTICE file(s) with this work for additional
# information regarding copyright ownership.
#
# This program and the accompanying materials are made
# available under the terms of the Apache Software License 2.0
# which is available at https://www.apache.org/licenses/LICENSE-2.0.
#
# SPDX-License-Identifier: Apache-2.0
# ********************************************************************************

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
declare -a arrayOfPipelinesToTriage

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
temurinPlatforms+=("linux-arm");            platformStart+=(8);  platformEnd+=(20)
temurinPlatforms+=("linux-ppc64le");        platformStart+=(8);  platformEnd+=(99)
temurinPlatforms+=("linux-riscv64");        platformStart+=(21); platformEnd+=(99)
temurinPlatforms+=("linux-s390x");          platformStart+=(11); platformEnd+=(99)
temurinPlatforms+=("linux-x64");            platformStart+=(8);  platformEnd+=(99)
temurinPlatforms+=("mac-aarch64");          platformStart+=(11); platformEnd+=(99)
temurinPlatforms+=("mac-x64");              platformStart+=(8);  platformEnd+=(99)
temurinPlatforms+=("solaris-sparcv9");      platformStart+=(8);  platformEnd+=(8)
temurinPlatforms+=("solaris-x64");          platformStart+=(8);  platformEnd+=(8)
temurinPlatforms+=("windows-aarch64");      platformStart+=(21); platformEnd+=(99)
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

# Takes a TRSS pipeline ID and jdk version, and determines if the pipeline was started by a user.
# Returns 0 (false), 1 (true), or 2 (if we couldn't get the information).
# Args: wasPipelineStartedByUser pipelineIDexample jdk[0-9]+u?
wasPipelineStartedByUser() {
  pipelineID=$1
  jenkinsJDK=$2
  sampleBuildName="none"
  sampleBuildNum="none"

  # We fetch the list, but only need the first build's output.
  tempListOfPipelineBuilds=$(wget -q -O - "https://trss.adoptium.net/api/getAllChildBuilds?parentId=${pipelineID}&buildNameRegex=^${jenkinsJDK}\-.*temurin$")

  # Identify a single build.
  for jsonEntry in $tempListOfPipelineBuilds
  do
    if [[ $jsonEntry =~ ^\"buildName\"\:.* ]]; then
      sampleBuildName="${jsonEntry:13:-1}"
    elif [[ $jsonEntry =~ .*\"buildNum\"\.* ]]; then
      sampleBuildNum="${jsonEntry:11}"
    fi
    if [[ ! "${sampleBuildName}_${sampleBuildNum}" =~ none ]]; then
      break
    fi
  done

  # Abort if we can't find a build in this pipeline.
  if [[ "${sampleBuildName}_${sampleBuildNum}" =~ none ]]; then
    return 2
  fi

  # Now we retrieve the build job output, limit to first dozen lines, and check if a user started it.
  failedJob="https://ci.adoptium.net/job/build-scripts/job/jobs/job/${jenkinsJDK}/job/${sampleBuildName}/${sampleBuildNum}/consoleText"

  wget -q -O - "${failedJob}" > ./jobOutput.txt

  # Limit the scan to the first 20 lines. If the line we're looking for exists, it'll be at the very top. Time saving.
  counter=0

  while IFS= read -r jobOutputLine; do
    counter=$((counter+1))
    if [[ "$jobOutputLine" =~ Started.by.user ]]; then
      return 1
    fi
    if [[ ${counter} -gt 20 ]]; then
      return 0
    fi
  done < ./jobOutput.txt

  return 0
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
    latestJdk8Pipelines=("none" "none" "none")
    latestTimerJenkinsJobID=""
    pipelineStatus="unknown"
    jdkJenkinsJobVersion="jdk${arrayOfAllJDKVersions[v]}${arrayOfUs[v]}"
    if [[ ${arrayOfAllJDKVersions[v]} -eq ${headJDKVersion} ]]; then
      jdkJenkinsJobVersion="jdk"
    fi
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

      if [[ $jsonEntry =~ ^\"status\" ]]; then
        pipelineStatus=${jsonEntry:10:-1}
      fi

      # Skip pipelines that are still running.
      if [[ $jsonEntry =~ ^\"startBy\" ]]; then
        if [[ ! $pipelineStatus == "Done" ]]; then
          pipelineStatus="unknown"
          continue
        fi
      fi

      # Expecting 3 pipelines for jdk8, but only 1 for other versions.
      if [[ ${arrayOfAllJDKVersions[v]} -eq 8 ]]; then
        if [[ $jsonEntry =~ ^\"startBy\".*betaTrigger.8ea ]]; then
          if [[ $jsonEntry =~ betaTrigger\_8ea.x64AlpineLinux && ${latestJdk8Pipelines[1]} == "none" ]]; then
            if wasPipelineStartedByUser "$latestTimerPipeline" "${jdkJenkinsJobVersion}"; then
              latestJdk8Pipelines[1]=$latestTimerPipeline
              echo "Found Alpine Linux JDK8 pipeline here: https://ci.adoptium.net/job/build-scripts/job/openjdk8-pipeline/${latestTimerJenkinsJobID}/"
            fi
          elif [[ $jsonEntry =~ betaTrigger\_8ea\_arm32Linux && ${latestJdk8Pipelines[2]} == "none" ]]; then
            if wasPipelineStartedByUser "$latestTimerPipeline" "${jdkJenkinsJobVersion}"; then
              latestJdk8Pipelines[2]=$latestTimerPipeline
              echo "Found Arm32 Linux JDK8 pipeline here: https://ci.adoptium.net/job/build-scripts/job/openjdk8-pipeline/${latestTimerJenkinsJobID}"
            fi
          elif [[ $jsonEntry =~ betaTrigger\_8ea\\\" && ${latestJdk8Pipelines[0]} == "none" ]]; then
            if wasPipelineStartedByUser "$latestTimerPipeline" "${jdkJenkinsJobVersion}"; then
              latestJdk8Pipelines[0]=$latestTimerPipeline
              echo "Found core JDK8 pipeline here: https://ci.adoptium.net/job/build-scripts/job/openjdk8-pipeline/${latestTimerJenkinsJobID}"
            fi
          fi
          if [[ ${latestJdk8Pipelines[0]} != "none" && ${latestJdk8Pipelines[1]} != "none" && ${latestJdk8Pipelines[2]} != "none" ]]; then
            echo "Found all 3 pipelines for JDK8."
            break
          fi
        fi
      else
        if [[ $jsonEntry =~ ^\"startBy\"\:\"timer ]]; then
          if wasPipelineStartedByUser "$latestTimerPipeline" "${jdkJenkinsJobVersion}"; then
            break
          fi
        elif [[ $jsonEntry =~ ^\"startBy\"\:\".*build-scripts/weekly-openjdk ]]; then
          if wasPipelineStartedByUser "$latestTimerPipeline" "${jdkJenkinsJobVersion}"; then
            break
          fi
        elif [[ $jsonEntry =~ ^\"startBy\"\:.*betaTrigger_${arrayOfAllJDKVersions[v]}ea ]]; then
          if wasPipelineStartedByUser "$latestTimerPipeline" "${jdkJenkinsJobVersion}"; then
            break
          fi
        fi
      fi

      if [[ $jsonEntry =~ ^HereIsTheEndOfAVeryLongFile$ ]]; then
        if [[ ${arrayOfAllJDKVersions[v]} -eq 8 ]]; then
          if [[ ${latestJdk8Pipelines[0]} != "none" || ${latestJdk8Pipelines[1]} != "none" || ${latestJdk8Pipelines[2]} != "none" ]]; then
            errorLog "Could not find all three of the pipelines for jdk8. Will triage the pipelines we could find."
            continue 1
          fi
        fi
        errorLog "Could not find any non-user pipeline jobs for ${jdkJenkinsJobVersion}. Skipping to the next jdk version."
        continue 2
      fi
    done

    if [[ ! ${arrayOfAllJDKVersions[v]} -eq 8 ]]; then
      echo "Found TRSS pipeline id for ${jdkJenkinsJobVersion} - ${latestTimerPipeline}"
      echo "Whose URL is: https://ci.adoptium.net/job/build-scripts/job/openjdk${arrayOfAllJDKVersions[v]}-pipeline/${latestTimerJenkinsJobID}/"
      arrayOfPipelinesToTriage+=("JDK${arrayOfAllJDKVersions[v]}: https://trss.adoptium.net/resultSummary?parentId=${latestTimerPipeline}")
    else
      if [[ ${latestJdk8Pipelines[0]} != "none" ]]; then
        arrayOfPipelinesToTriage+=("JDK8: https://trss.adoptium.net/resultSummary?parentId=${latestJdk8Pipelines[0]}")
      fi
      if [[ ${latestJdk8Pipelines[1]} != "none" ]]; then
        arrayOfPipelinesToTriage+=("JDK8 Alpine: https://trss.adoptium.net/resultSummary?parentId=${latestJdk8Pipelines[1]}")
      fi
      if [[ ${latestJdk8Pipelines[2]} != "none" ]]; then
        arrayOfPipelinesToTriage+=("JDK8 Arm32 Linux: https://trss.adoptium.net/resultSummary?parentId=${latestJdk8Pipelines[2]}")
      fi
    fi

    # Now grab a full list of builds launched by this pipeline.
    listOfPipelineBuilds=""
    if [[ ${arrayOfAllJDKVersions[v]} -eq 8 ]]; then
      for jp in "${!latestJdk8Pipelines[@]}"
      do
        if [[ ${latestJdk8Pipelines[jp]} != "none" ]]; then
          echo "wgetting https://trss.adoptium.net/api/getAllChildBuilds?parentId=${latestJdk8Pipelines[jp]}&buildNameRegex=^jdk8u\-.*temurin$"
          listOfPipelineBuilds+=$(wget -q -O - "https://trss.adoptium.net/api/getAllChildBuilds?parentId=${latestJdk8Pipelines[jp]}&buildNameRegex=^jdk8u\-.*temurin$")
        fi
      done
    else
      echo "wgetting https://trss.adoptium.net/api/getAllChildBuilds?parentId=${latestTimerPipeline}&buildNameRegex=^${jdkJenkinsJobVersion}.*temurin$"
      listOfPipelineBuilds=$(wget -q -O - "https://trss.adoptium.net/api/getAllChildBuilds?parentId=${latestTimerPipeline}&buildNameRegex=^${jdkJenkinsJobVersion}\-.*temurin$")
    fi

    declare -a listOfBuildNames
    declare -a listOfBuildNums
    declare -a listOfBuildResults

    shorterListOfBuilds=""

    # Using this single-build tuple to ensure all of the build data lines up in the three arrays.
    sbTuple=("none" "none" "none")

    # Now we identify each build in the pipeline.
    for jsonEntry in $listOfPipelineBuilds
    do
      if [[ $jsonEntry =~ ^\"buildName\"\:.* ]]; then
        sbTuple[0]=${jsonEntry}
      elif [[ $jsonEntry =~ .*\"buildNum\"\.* ]]; then
        sbTuple[1]=${jsonEntry}
      elif [[ $jsonEntry =~ .*\"buildResult\".* ]]; then
        sbTuple[2]=${jsonEntry}
      elif [[ $jsonEntry =~ \"_id\" ]]; then
        sbTuple=("none" "none" "none")
      fi
      if [[ ! "${sbTuple[0]},${sbTuple[1]},${sbTuple[2]}" =~ none ]]; then
        listOfBuildNames+=("${sbTuple[0]:13:-1}")
        listOfBuildNums+=("${sbTuple[1]:11}")
        listOfBuildResults+=("${sbTuple[2]:15:-1}")
        shorterListOfBuilds+="${sbTuple[0]},"
        sbTuple=("none" "none" "none")
      fi
    done

    echo "The builds for those pipelines have been identified. Now validating them."

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
      errorLog "Cannot find any valid build platforms launched by ${jdkJenkinsJobVersion} pipelines. Skipping to the next jdk version."
      continue
    fi
    echo "Platforms validated. Identifying build numbers for these platforms: ${triageThesePlatforms:1:-1}"

    # Iterate over the platforms we need to triage and find the build numbers for 
    # any build that failed or was aborted (includes propagated test failures).
    for b in "${!listOfBuildNames[@]}"
    do
      if [[ $triageThesePlatforms =~ .*,${listOfBuildNames[$b]},.* ]]; then
        if [[ ! ${listOfBuildResults[b]} =~ ^SUCCESS$ ]]; then
          if [[ ! ${listOfBuildResults[b]} =~ ^UNSTABLE$ ]]; then
            failedJobLink="https://ci.adoptium.net/job/build-scripts/job/jobs/job/${jdkJenkinsJobVersion}/job/${listOfBuildNames[b]}/${listOfBuildNums[b]}/"
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
    echo "# TRSS Pipeline Links"
    if [[ ${#arrayOfPipelinesToTriage[@]} -gt 0 ]]; then
      for pipelineTrssLink in "${arrayOfPipelinesToTriage[@]}"
      do
        echo "${pipelineTrssLink}"
      done
    fi
    echo ""
    if [[ ${#arrayOfFailedJobs[@]} -gt 0 ]]; then
      outputForFailedBuilds=""
      outputForFailedTests=""
      for failedJobIndex in "${!arrayOfFailedJobs[@]}"
      do
        regexID="${arrayOfRegexsForFailedJobs[failedJobIndex]}"
        jobTriageOutput="Failure: ${arrayOfFailedJobs[failedJobIndex]}\n"
        if [[ ${regexID} =~ Unmatched ]]; then
          jobTriageOutput+="Cause: ${arrayOfErrorLinesForFailedJobs[failedJobIndex]}\n"
        else
          jobTriageOutput+="Cause: ${arrayOfRegexMetadata[regexID]}\n"
          preventable="yes"
          if [[ "${arrayOfRegexPreventability[regexID]}" -gt 0 ]]; then
            preventable="no"
          fi
          jobTriageOutput+="Preventable: ${preventable}\n"
          jobTriageOutput+="\`\`\`\n"
          jobTriageOutput+="${arrayOfErrorLinesForFailedJobs[failedJobIndex]}\n"
          jobTriageOutput+="\`\`\`\n"
        fi
        jobTriageOutput+="\n"
        if [[ ${arrayOfFailureSources[regexID]} -eq 1 ]]; then
          outputForFailedTests+="${jobTriageOutput}"
        else
          outputForFailedBuilds+="${jobTriageOutput}"
        fi
      done
      echo "# Failed Builds"
      if [[ -n "${outputForFailedBuilds}" ]]; then
        echo -e "${outputForFailedBuilds}"
      else
        echo "None."
      fi
      echo "# Builds with Failed Tests (suspected)"
      if [[ -n "${outputForFailedTests}" ]]; then
          echo -e "${outputForFailedTests}"
        else
          echo "None."
        fi
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
