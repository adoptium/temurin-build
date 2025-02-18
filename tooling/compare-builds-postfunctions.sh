#!/bin/bash
# ********************************************************************************
# Copyright (c) 2024 Contributors to the Eclipse Foundation
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

function tapsAndJunits() {
  local diffFileParam="${1}"
  local differencesFile="${2}"
  local totalFile="${3}"
  # six glob al variables to transfer state between  plain, taps and jtregs
  total=4
  passed=0
  failed=0
  totalDiffs=-1
  totalFiles=-1
  totalOnlyIn=-1
  if [ -z "${RFAT:-}" ] ; then
    if [ ! -e run-folder-as-tests ] ; then
      git clone "https://github.com/rh-openjdk/run-folder-as-tests.git"
    fi
    RFAT="$(pwd)/run-folder-as-tests"
  fi
  generateSummUp "${diffFileParam}" "${differencesFile}" "${totalFile}"
  printPlain "${diffFileParam}" "${differencesFile}" "${totalFile}"
  if [ "${DO_TAPS:-}" == "true" ] ; then
    generateTaps "${diffFileParam}" "${differencesFile}" "${totalFile}"
  fi
  if [ "${DO_JUNIT:-}" == "true" ] ; then
    generateJunits "${diffFileParam}" "${differencesFile}" "${totalFile}"
  fi
  set -x
}

function generateSummUp() {
    set +x
    if [ "${GLOBAL_RESULT}" -eq 0 ] ; then
      passed=$(("${passed}"+1))
    else
      failed=$(("${failed}"+1))
    fi
    # warning, this do not work without pipefail
    totalDiffs=$(grep "Number of" "${differencesFile}" | sed "s/[^0-9]\+//" || echo "999999999") # if there is no record we need to fail
    totalFiles=$(grep "Number of" "${totalFile}" | sed "s/[^0-9]\+//" || echo "0") # if there is no record we need to fail
    totalOnlyIn=$(grep "Only in:" "${differencesFile}"| sed "s/[^0-9]\+//" || echo "0") #if there is non, we eant to pass
    if [ "${totalDiffs}" -eq 0 ] ; then
      passed=$(("${passed}"+1))
    else
      failed=$(("${failed}"+1))
    fi
    if [ "${totalFiles}" -ne 0 ] ; then
      passed=$(("${passed}"+1))
    else
      failed=$(("${failed}"+1))
    fi
    if [ "${totalOnlyIn}" -eq 0 ] ; then
      passed=$(("${passed}"+1))
    else
      failed=$(("${failed}"+1))
    fi
    total=$(("${passed}"+"${failed}"))
}

function totalDiffsToPlain() {
    if [ "${totalDiffs}" -eq 0 ] ; then
      echo "-- no differences --"
    else
      echo "-- differences count: ${totalDiffs} --"
    fi
}

function totalFilesToPlain() {
    if [ "${totalFiles}" -ne 0 ] ; then
      echo "-- files compared: ${totalFiles} --"
    else
      echo "-- no files compared --"
    fi
}

function totalOnlyInToPlain() {
    if [ "${totalOnlyIn}" -eq 0 ] ; then
      echo "-- no onlyin files --"
    else
      echo "-- onlyin files count: ${totalOnlyIn} --"
    fi
}

function globalResultToPlain() {
    if [ "${GLOBAL_RESULT}" -eq 0 ] ; then
      echo "-- COMPARABLE --"
    else
      echo "-- MISMATCH --"
    fi
}

function printPlain() {
    local diffFileParam="${1}"
    local differencesFile="${2}"
    local totalFile="${3}"
    #requires generateSummUp to run before
    set +x
    totalDiffsToPlain
    totalFilesToPlain
    totalOnlyInToPlain
    globalResultToPlain
}

function totalDiffsToXml() {
    if [ "${totalDiffs}" -eq 0 ] ; then
      printXmlTest "compare" "differences-count" "1" "" "../artifact/$(basename "${differencesFile}")" >> "${unitFile}"
    else
      printXmlTest "compare" "differences-count" "1" "${differencesFile}" "../artifact/$(basename "${differencesFile}")" >> "${unitFile}"
    fi
}

function totalFilesToXml() {
    if [ "${totalFiles}" -ne 0 ] ; then
      printXmlTest "compare" "compared-files-count" "2" "" "../artifact/$(basename "${totalFile}")" >> "${unitFile}"
    else
      printXmlTest "compare" "compared-files-count" "2" "${totalFile}" "../artifact/$(basename "${totalFile}")" >> "${unitFile}"
    fi
}

function totalOnlyInToXml() {
    if [ "${totalOnlyIn}" -eq 0 ] ; then
      printXmlTest "compare" "onlyin-count" "3" "" "../artifact/$(basename "${differencesFile}")" >> "${unitFile}"
    else
      printXmlTest "compare" "onlyin-count" "3" "${differencesFile}" "../artifact/$(basename "${differencesFile}")" >> "${unitFile}"
    fi
}

function globalResultToXml() {
    if [ "${GLOBAL_RESULT}" -eq 0 ] ; then
      printXmlTest "compare" "comparable-builds" "4" "" "../artifact/$(basename "${diffFileParam}")" >> "${unitFile}"
    else
      printXmlTest "compare" "comparable-builds" "4" "${diffFileParam}" "../artifact/$(basename "${diffFileParam}")" >> "${unitFile}"
    fi
}

function generateJunits() {
    local diffFileParam="${1}"
    local differencesFile="${2}"
    local totalFile="${3}"
    # shellcheck disable=SC1091
    source "${RFAT}/jtreg-shell-xml.sh"
    local unitFile="${WORKDIR}/compare-comparable-builds.jtr.xml"
    local unitFileArchive="$unitFile.tar.xz"
    #requires generateSummUp to run before
    set +x
    echo "writing $unitFile"
    printXmlHeader "${passed}" "${failed}" "${total}" 0 "compare-comparable-builds" > "${unitFile}"
    totalDiffsToXml
    totalFilesToXml
    totalOnlyInToXml
    globalResultToXml
    printXmlFooter >> "${unitFile}"
    echo "writing $unitFileArchive"
    set -x
    tar -cJf "${unitFileArchive}"  "${unitFile}"
}

function totalDiffsToTap() {
    if [ "${totalDiffs}" -eq 0 ] ; then
      tapTestStart "ok" "1" "differences-count" >> "${resultsTapFile}"
    else
      tapTestStart "not ok" "1" "differences-count" >> "${resultsTapFile}"
    fi
    set +e
      tapFromWholeFile "${differencesFile}" "${differencesFile}" >> "${resultsTapFile}"
      tapTestEnd >> "${resultsTapFile}"
    set -e
}

function totalFilesToTap() {
    if [ "${totalFiles}" -ne 0 ] ; then
      tapTestStart "ok" "2" "compared-files-count" >> "${resultsTapFile}"
    else
      tapTestStart "not ok" "2" "compared-files-count" >> "${resultsTapFile}"
    fi
    set +e
      tapFromWholeFile "${totalFile}" "${totalFile}" >> "${resultsTapFile}"
      tapTestEnd >> "${resultsTapFile}"
    set -e
}

function totalOnlyInToTap() {
    if [ "${totalOnlyIn}" -eq 0 ] ; then
      tapTestStart "ok" "3" "onlyin-count" >> "${resultsTapFile}"
    else
      tapTestStart "not ok" "3" "onlyin-count" >> "${resultsTapFile}"
    fi
    set +e
      tapFromWholeFile "${differencesFile}" "${differencesFile}" >> "${resultsTapFile}"
      tapTestEnd >> "${resultsTapFile}"
    set -e
}

function globalResultToTap() {
    if [ "${GLOBAL_RESULT}" -eq 0 ] ; then
      tapTestStart "ok" "4" "comparable-builds" >> "${resultsTapFile}"
    else
      tapTestStart "not ok" "4" "comparable-builds" >> "${resultsTapFile}"
    fi
    set +e
      # shellcheck disable=SC2002
      cat "${diffFileParam}" | sed "s|${WORKDIR}||g" > diffFileCopy || true
      tapFromWholeFile "diffFileCopy" "reprotest.diff" >> "${resultsTapFile}"
      tapTestEnd >> "${resultsTapFile}"
    set -e
}

function generateTaps() {
    local diffFileParam="${1}"
    local differencesFile="${2}"
    local totalFile="${3}"
    # shellcheck disable=SC1091
    source "${RFAT}/tap-shell-tap.sh"
    resultsTapFile="${WORKDIR}/compare-comparable-builds.tap"
    #requires generateSummUp to run before
    set +x
    echo "writing $resultsTapFile"
    tapHeader "${total}"  "$(date)" > "${resultsTapFile}"
    totalDiffsToTap
    totalFilesToTap
    totalOnlyInToTap
    globalResultToTap
}

