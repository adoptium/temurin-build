#!/bin/bash
# ********************************************************************************
# Copyright (c) 2022 Contributors to the Eclipse Foundation
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

# Create a default SBOM json file: sbomJson
createSBOMFile() {
  local javaHome="${1}"
  local classpath="${2}"
  local jsonFile="${3}"
  "${javaHome}"/bin/java -cp "${classpath}" temurin.sbom.TemurinGenSBOM --createNewSBOM --jsonFile "${jsonFile}"
}

signSBOMFile() {
  local javaHome="${1}"
  local classpath="${2}"
  local jsonFile="${3}"
  local privateKeyFile="${4}"
  "${javaHome}"/bin/java -cp "${classpath}" temurin.sbom.TemurinSignSBOM --signSBOM --jsonFile "${jsonFile}" --privateKeyFile "${privateKeyFile}"
}

verifySBOMSignature() {
  local javaHome="${1}"
  local classpath="${2}"
  local jsonFile="${3}"
  local publicKeyFile="${4}"
  "${javaHome}"/bin/java -cp "${classpath}" temurin.sbom.TemurinSignSBOM --verifySBOMSignature --jsonFile "${jsonFile}" --publicKeyFile "${publicKeyFile}"
}

# Set basic SBOM metadata with timestamp, authors, manufacture to ${sbomJson}
addSBOMMetadata() {
  local javaHome="${1}"
  local classpath="${2}"
  local jsonFile="${3}"
  "${javaHome}"/bin/java -cp "${classpath}" temurin.sbom.TemurinGenSBOM --addMetadata --jsonFile "${jsonFile}"
}

# Ref: https://cyclonedx.org/docs/1.4/json/#metadata
# Add the given Property name & value to the SBOM Metadata
addSBOMMetadataProperty() {
  local javaHome="${1}"
  local classpath="${2}"
  local jsonFile="${3}"
  local name="${4}"
  local value="${5}"
  if [ -z "${value}" ]; then
    value="N.A"
  fi
  "${javaHome}"/bin/java -cp "${classpath}" temurin.sbom.TemurinGenSBOM --addMetadataProp --jsonFile "${jsonFile}" --name "${name}" --value "${value}"
}

# Set basic SBoM formulation
addSBOMFormulation() {
  local javaHome="${1}"
  local classpath="${2}"
  local jsonFile="${3}"
  local formulaName="${4}"
  "${javaHome}"/bin/java -cp "${classpath}" temurin.sbom.TemurinGenSBOM --addFormulation --formulaName "${formulaName}" --jsonFile "${jsonFile}"
}

addSBOMFormulationComp() {
  local javaHome="${1}"
  local classpath="${2}"
  local jsonFile="${3}"
  local formulaName="${4}"
  local name="${5}"
  "${javaHome}"/bin/java -cp "${classpath}" temurin.sbom.TemurinGenSBOM --addFormulationComp --jsonFile "${jsonFile}" --formulaName "${formulaName}" --name "${name}"
}  

# Ref: https://cyclonedx.org/docs/1.4/json/#formulation
# Add the given Property name & value to the SBOM Formulation
addSBOMFormulationComponentProperty() {
  local javaHome="${1}"
  local classpath="${2}"
  local jsonFile="${3}"
  local formulaName="${4}"
  local compName="${5}"
  local name="${6}"
  local value="${7}"
  "${javaHome}"/bin/java -cp "${classpath}" temurin.sbom.TemurinGenSBOM --addFormulationCompProp --jsonFile "${jsonFile}" --formulaName "${formulaName}" --compName "${compName}" --name "${name}" --value "${value}"
}


# Ref: https://cyclonedx.org/docs/1.4/json/#metadata
# If the given property file exists and size over 2bytes, then add the given Property name with the given file contents value to the SBOM Metadata
addSBOMMetadataPropertyFromFile() {
  local javaHome="${1}"
  local classpath="${2}"
  local jsonFile="${3}"
  local name="${4}"
  local propFile="${5}"
  local value="N.A"
  if [ -f "${propFile}" ]; then
      if [ "$(stat --print=%s "${propFile}")" -ge 2 ]; then
        value=$(cat "${propFile}")
      fi
  fi
  "${javaHome}"/bin/java -cp "${classpath}" temurin.sbom.TemurinGenSBOM --addMetadataProp --jsonFile "${jsonFile}" --name "${name}" --value "${value}"
}

# Ref: https://cyclonedx.org/docs/1.4/json/#metadata_tools
# Add tool and version, e.g: alsa freemarker dockerimage
addSBOMMetadataTools() {
  local javaHome="${1}"
  local classpath="${2}"
  local jsonFile="${3}"
  local tool="${4}"
  local version="${5}"
  if [ -z "${version}" ]; then
    version="N.A"
  fi
  "${javaHome}"/bin/java -cp "${classpath}" temurin.sbom.TemurinGenSBOM --addMetadataTools --jsonFile "${jsonFile}" --tool "${tool}" --version "${version}"
}

# Ref: https://cyclonedx.org/docs/1.4/json/#metadata_component
# Add JDK as component into metadata, this is not a list, i.e cannot be called multiple times for the same ${sbomJson}
addSBOMMetadataComponent() {
  local javaHome="${1}"
  local classpath="${2}"
  local jsonFile="${3}"
  local name="${4}"
  local type="${5}"
  local version="${6}"
  local description="${7}"
  "${javaHome}"/bin/java -cp "${classpath}" temurin.sbom.TemurinGenSBOM --addMetadataComponent --jsonFile "${jsonFile}" --name "${name}"  --type "${type}" --version "${version}" --description "${description}"
}

# Ref: https://cyclonedx.org/docs/1.4/json/#components
# To add new component into 'components' list
addSBOMComponent(){
  local javaHome="${1}"
  local classpath="${2}"
  local jsonFile="${3}"
  local compName="${4}"
  local version="${5}"
  local description="${6}"
  "${javaHome}"/bin/java -cp "${classpath}" temurin.sbom.TemurinGenSBOM --addComponent --jsonFile "${jsonFile}" --compName "${compName}" --version "${version}" --description "${description}"
}

# Ref: https://cyclonedx.org/docs/1.4/json/#components
# If the given property file exists, then add the given Component and Property with the given file contents value
# Function not in use
addSBOMComponentFromFile() {
  local javaHome="${1}"
  local classpath="${2}"
  local jsonFile="${3}"
  local compName="${4}"
  local description="${5}"
  local name="${6}"
  local propFile="${7}"
  # always create component in sbom
  "${javaHome}"/bin/java -cp "${classpath}" temurin.sbom.TemurinGenSBOM --addComponent --jsonFile "${jsonFile}" --compName "${compName}" --description "${description}"
  local value="N.A" # default set to "N.A" as value for variant does not have $propFile generated in prepareWorkspace.sh
  if [ -e "${propFile}" ]; then
      value=$(cat "${propFile}")
  fi
  "${javaHome}"/bin/java -cp "${classpath}" temurin.sbom.TemurinGenSBOM --addComponentProp --jsonFile "${jsonFile}" --compName "${compName}" --name "${name}" --value "${value}"
}

# Ref: https://cyclonedx.org/docs/1.4/json/#components_items_hashes
# Add the given sha256 hash to the given SBOM Component
addSBOMComponentHash() {
  local javaHome="${1}"
  local classpath="${2}"
  local jsonFile="${3}"
  local compName="${4}"
  local hash="${5}"
  "${javaHome}"/bin/java -cp "${classpath}" temurin.sbom.TemurinGenSBOM --addComponentHash --jsonFile "${jsonFile}" --compName "${compName}" --hash "${hash}"
}

# Ref: https://cyclonedx.org/docs/1.4/json/#components_items_properties
# Add the given Property name & value to the given SBOM Component
addSBOMComponentProperty() {
  local javaHome="${1}"
  local classpath="${2}"
  local jsonFile="${3}"
  local compName="${4}"
  local name="${5}"
  local value="${6}"
  "${javaHome}"/bin/java -cp "${classpath}" temurin.sbom.TemurinGenSBOM --addComponentProp --jsonFile "${jsonFile}" --compName "${compName}" --name "${name}" --value "${value}"
}

# Ref: https://cyclonedx.org/docs/1.4/json/#components_items_properties
# If the given property file exists, then add the given Property name with the given file contents value to the given SBOM Component
addSBOMComponentPropertyFromFile() {
  local javaHome="${1}"
  local classpath="${2}"
  local jsonFile="${3}"
  local compName="${4}"
  local name="${5}"
  local propFile="${6}"
  local value="N.A"
  if [ -e "${propFile}" ]; then
      value=$(cat "${propFile}")
      "${javaHome}"/bin/java -cp "${classpath}" temurin.sbom.TemurinGenSBOM --addComponentProp --jsonFile "${jsonFile}" --compName "${compName}" --name "${name}" --value "${value}"
  fi
}

# Ref: https://cyclonedx.org/docs/1.6/json/#formulation_items_workflows
# Create or update a workflow entry under a given formula
addSBOMWorkflow() {
  local javaHome="${1}"
  local classpath="${2}"
  local jsonFile="${3}"
  local formulaName="${4}"
  local workflowRef="${5}"
  local workflowUid="${6}"
  local workflowName="${7}"
  local taskTypes="${8}"
  "${javaHome}"/bin/java -cp "${classpath}" temurin.sbom.TemurinGenSBOM --addWorkflow --jsonFile "${jsonFile}" --formulaName "${formulaName}" --workflowRef "${workflowRef}" --workflowUid "${workflowUid}" --workflowName "${workflowName}" --taskTypes "${taskTypes}"
}

# Ref: https://cyclonedx.org/docs/1.6/json/#formulation_items_workflows_items_steps
# Create a step inside of a workflow
addSBOMWorkflowStep() {
  local javaHome="${1}"
  local classpath="${2}"
  local jsonFile="${3}"
  local formulaName="${4}"
  local workflowRef="${5}"
  local workflowStepName="${6}"
  local description="${7}"
  "${javaHome}"/bin/java -cp "${classpath}" temurin.sbom.TemurinGenSBOM --addWorkflowStep --jsonFile "${jsonFile}" --formulaName "${formulaName}" --workflowRef "${workflowRef}" --workflowStepName "${workflowStepName}" --description "${description}"
}

# Ref: https://cyclonedx.org/docs/1.6/json/#formulation_items_workflows_items_steps_items_commands
# Add a executed command to a specific workflow step
addSBOMWorkflowStepCmd() {
  local javaHome="${1}"
  local classpath="${2}"
  local jsonFile="${3}"
  local formulaName="${4}"
  local workflowRef="${5}"
  local workflowStepName="${6}"
  local executed="${7}"
  "${javaHome}"/bin/java -cp "${classpath}" temurin.sbom.TemurinGenSBOM --addWorkflowStepCmd --jsonFile "${jsonFile}" --formulaName "${formulaName}" --workflowRef "${workflowRef}" --workflowStepName "${workflowStepName}" --executed "${executed}"
}