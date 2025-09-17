#!/bin/bash
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
# This script produces arrays of regular expressions that match a type of failure
# that can be searched for in the output of an Eclipse Temurin build of OpenJDK.
# 
# Each regular expression comes paired with metadata (providing useful information)
#
################################################################################

# Regular expressions to match a single line of jenkins job console output.
declare -a arrayOfRegexes
# A short description of the sort of error we're dealing with. Can contain URLs. Markdown format.
declare -a arrayOfRegexMetadata
# 0 = This issue was preventable, and 1 = This issue was not preventable.
declare -a arrayOfRegexPreventability
# 0 = This issue was probably a build failure, and 1 = This issue was probably a test failure.
declare -a arrayOfFailureSources

storeInArrays() {
  arrayOfRegexes+=("${1}")
  arrayOfRegexMetadata+=("${2}")
  arrayOfRegexPreventability+=("${3}")
  arrayOfFailureSources+=("${4}")
}

echo "Generating regex arrays to match against failures."

r="(SIGSEGV|Segmentation\sfault)"
m="Segmentation error."
p="1"
s="0"
storeInArrays "${r}" "${m}" "${p}" "${s}"

r="No.space.left.on.device"
m="Out of disk space."
p="0"
s="0"
storeInArrays "${r}" "${m}" "${p}" "${s}"

r="(insufficient.memory|Out.of.system.resources|Out.?of.?Memory.?Error)"
m="Out of memory."
p="1"
s="0"
storeInArrays "${r}" "${m}" "${p}" "${s}"

r="Read\-only\sfile\ssystem"
m="Read-only file system."
p="0"
s="0"
storeInArrays "${r}" "${m}" "${p}" "${s}"

r="(was.marked.offline\:.Connection.was.broken|Unexpected.termination.of.the.channel)"
m="Lost connection to machine."
p="1"
s="0"
storeInArrays "${r}" "${m}" "${p}" "${s}"

r="(Failed.to.connect.to.github\.com|archive.is.not.a.ZIP.archive)"
m="Download failed."
p="1"
s="0"
storeInArrays "${r}" "${m}" "${p}" "${s}"

r="(Program.*timed.out|Agent.[0-9]+.timed.out.with.a.timeout.of)"
m="Timeout."
p="1"
s="0"
storeInArrays "${r}" "${m}" "${p}" "${s}"

r="there.are.rogue.processes.kicking.about"
m="ProcessCatch found something."
p="1"
s="0"
storeInArrays "${r}" "${m}" "${p}" "${s}"

r="No.such.device"
m="No such device."
p="0"
s="0"
storeInArrays "${r}" "${m}" "${p}" "${s}"

r="Build.Test_openjdk.*completed\:.(FAILURE|ABORTED)"
m="Post-build AQATest subjob failed."
p="1"
s="1"
storeInArrays "${r}" "${m}" "${p}" "${s}"

r="Build.*SmokeTests.*completed\:.(FAILURE|ABORTED)"
m="Smoke test failed."
p="1"
s="1"
storeInArrays "${r}" "${m}" "${p}" "${s}"

r="Build.*create_installer.*\#[0-9]+.completed\:.(FAILURE|ABORTED)"
m="Installer subjob failed."
p="1"
s="0"
storeInArrays "${r}" "${m}" "${p}" "${s}"

r="Build.*sign\_.*.\#[0-9].completed\:.(FAILURE|ABORTED)"
m="Signing subjob failed."
p="1"
s="0"
storeInArrays "${r}" "${m}" "${p}" "${s}"

r="Build.*\#[0-9]+.completed\:.(FAILURE|ABORTED)"
m="Subjob failed. It was not a test, installer, or signing job."
p="1"
s="0"
storeInArrays "${r}" "${m}" "${p}" "${s}"

r="(permission.denied|AccessDeniedException)"
m="AccessDeniedException or Permission Denied"
p="0"
s="0"
storeInArrays "${r}" "${m}" "${p}" "${s}"

r="Error.creating.temporary.file"
m="Error creating temporary file."
p="0"
s="0"
storeInArrays "${r}" "${m}" "${p}" "${s}"

r="(Unable.to.delete|Could.not.create.(file|directory))"
m="Error creating/deleting a file"
p="0"
s="0"
storeInArrays "${r}" "${m}" "${p}" "${s}"

r="return\scode\s[1-9]+"
m="Process return code indicates error."
p="1"
s="0"
storeInArrays "${r}" "${m}" "${p}" "${s}"

r="ERROR\:\s[a-z]+\.jck[a-z\.,]*\snot\ssuccessful,\ssetting\sstage\sresult\sto\:\s(FAILURE|ABORTED)"
m="JCK tests failed."
p="1"
s="1"
storeInArrays "${r}" "${m}" "${p}" "${s}"

r="Failed\sto\scopy\sartifacts"
m="Artifacts could not be transferred between jobs. May require a jenkins restart if other causes are not apparent."
p="1"
s="0"
storeInArrays "${r}" "${m}" "${p}" "${s}"

r="ERROR\:\sTest_Job_Auto_Gen\s\#[0-9]+ was deleted"
m="The test job generator job was deleted."
p="1"
s="0"
storeInArrays "${r}" "${m}" "${p}" "${s}"

r="(Error\:\s|Exception\:\s)"
m="Error/exception found."
p="1"
s="0"
storeInArrays "${r}" "${m}" "${p}" "${s}"

echo "Regex arrays ready."
