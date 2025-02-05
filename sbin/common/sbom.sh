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

# Create a default SBOM xml file: sbomXml
createSBOMFile() {
  local javaHome="${1}"
  local classpath="${2}"
  local xmlFile="${3}"
  "${javaHome}"/bin/java -cp "${classpath}" temurin.sbom.TemurinGenSBOM --createNewSBOM --xmlFile "${xmlFile}"
}

signSBOMFile() {
  local javaHome="${1}"
  local classpath="${2}"
  local xmlFile="${3}"
  local privateKeyFile="${4}"
  "${javaHome}"/bin/java -cp "${classpath}" temurin.sbom.TemurinSignSBOM --signSBOM --xmlFile "${xmlFile}" --privateKeyFile "${privateKeyFile}"
}

verifySBOMSignature() {
  local javaHome="${1}"
  local classpath="${2}"
  local xmlFile="${3}"
  local publicKeyFile="${4}"
  "${javaHome}"/bin/java -cp "${classpath}" temurin.sbom.TemurinSignSBOM --verifySBOMSignature --xmlFile "${xmlFile}" --publicKeyFile "${publicKeyFile}"
}

# Set basic SBOM metadata with timestamp, authors, manufacture to ${sbomXml}
addSBOMMetadata() {
  local javaHome="${1}"
  local classpath="${2}"
  local xmlFile="${3}"
  "${javaHome}"/bin/java -cp "${classpath}" temurin.sbom.TemurinGenSBOM --addMetadata --xmlFile "${xmlFile}"
}

# Ref: https://cyclonedx.org/docs/1.4/json/#metadata
# Add the given Property name & value to the SBOM Metadata
addSBOMMetadataProperty() {
  local javaHome="${1}"
  local classpath="${2}"
  local xmlFile="${3}"
  local name="${4}"
  local value="${5}"
  if [ -z "${value}" ]; then
    value="N.A"
  fi
  "${javaHome}"/bin/java -cp "${classpath}" temurin.sbom.TemurinGenSBOM --addMetadataProp --xmlFile "${xmlFile}" --name "${name}" --value "${value}"
}

# Set basic SBoM formulation
addSBOMFormulation() {
  local javaHome="${1}"
  local classpath="${2}"
  local xmlFile="${3}"
  local formulaName="${4}"
  "${javaHome}"/bin/java -cp "${classpath}" temurin.sbom.TemurinGenSBOM --addFormulation --formulaName "${formulaName}" --xmlFile "${xmlFile}"
}

addSBOMFormulationComp() {
  local javaHome="${1}"
  local classpath="${2}"
  local xmlFile="${3}"
  local formulaName="${4}"
  local name="${5}"
  "${javaHome}"/bin/java -cp "${classpath}" temurin.sbom.TemurinGenSBOM --addFormulationComp --xmlFile "${xmlFile}" --formulaName "${formulaName}" --name "${name}"
}  

# Ref: https://cyclonedx.org/docs/1.4/json/#formulation
# Add the given Property name & value to the SBOM Formulation
addSBOMFormulationComponentProperty() {
  local javaHome="${1}"
  local classpath="${2}"
  local xmlFile="${3}"
  local formulaName="${4}"
  local compName="${5}"
  local name="${6}"
  local value="${7}"
  "${javaHome}"/bin/java -cp "${classpath}" temurin.sbom.TemurinGenSBOM --addFormulationCompProp --xmlFile "${xmlFile}" --formulaName "${formulaName}" --compName "${compName}" --name "${name}" --value "${value}"
}


# Ref: https://cyclonedx.org/docs/1.4/json/#metadata
# If the given property file exists and size over 2bytes, then add the given Property name with the given file contents value to the SBOM Metadata
addSBOMMetadataPropertyFromFile() {
  local javaHome="${1}"
  local classpath="${2}"
  local xmlFile="${3}"
  local name="${4}"
  local propFile="${5}"
  local value="N.A"
  if [ -f "${propFile}" ]; then
      if [ "$(stat --print=%s "${propFile}")" -ge 2 ]; then
        value=$(cat "${propFile}")
      fi
  fi
  "${javaHome}"/bin/java -cp "${classpath}" temurin.sbom.TemurinGenSBOM --addMetadataProp --xmlFile "${xmlFile}" --name "${name}" --value "${value}"
}

# Ref: https://cyclonedx.org/docs/1.4/json/#metadata_tools
# Add tool and version, e.g: alsa freemarker dockerimage
addSBOMMetadataTools() {
  local javaHome="${1}"
  local classpath="${2}"
  local xmlFile="${3}"
  local tool="${4}"
  local version="${5}"
  if [ -z "${version}" ]; then
    version="N.A"
  fi
  "${javaHome}"/bin/java -cp "${classpath}" temurin.sbom.TemurinGenSBOM --addMetadataTools --xmlFile "${xmlFile}" --tool "${tool}" --version "${version}"
}

# Ref: https://cyclonedx.org/docs/1.4/json/#metadata_component
# Add JDK as component into metadata, this is not a list, i.e cannot be called multiple times for the same ${sbomXml}
addSBOMMetadataComponent() {
  local javaHome="${1}"
  local classpath="${2}"
  local xmlFile="${3}"
  local name="${4}"
  local type="${5}"
  local version="${6}"
  local description="${7}"
  "${javaHome}"/bin/java -cp "${classpath}" temurin.sbom.TemurinGenSBOM --addMetadataComponent --xmlFile "${xmlFile}" --name "${name}"  --type "${type}" --version "${version}" --description "${description}"
}

# Ref: https://cyclonedx.org/docs/1.4/json/#components
# To add new component into 'components' list
addSBOMComponent(){
  local javaHome="${1}"
  local classpath="${2}"
  local xmlFile="${3}"
  local compName="${4}"
  local version="${5}"
  local description="${6}"
  "${javaHome}"/bin/java -cp "${classpath}" temurin.sbom.TemurinGenSBOM --addComponent --xmlFile "${xmlFile}" --compName "${compName}" --version "${version}" --description "${description}"
}

# Ref: https://cyclonedx.org/docs/1.4/json/#components
# If the given property file exists, then add the given Component and Property with the given file contents value
# Function not in use
addSBOMComponentFromFile() {
  local javaHome="${1}"
  local classpath="${2}"
  local xmlFile="${3}"
  local compName="${4}"
  local description="${5}"
  local name="${6}"
  local propFile="${7}"
  # always create component in sbom
  "${javaHome}"/bin/java -cp "${classpath}" temurin.sbom.TemurinGenSBOM --addComponent --xmlFile "${xmlFile}" --compName "${compName}" --description "${description}"
  local value="N.A" # default set to "N.A" as value for variant does not have $propFile generated in prepareWorkspace.sh
  if [ -e "${propFile}" ]; then
      value=$(cat "${propFile}")
  fi
  "${javaHome}"/bin/java -cp "${classpath}" temurin.sbom.TemurinGenSBOM --addComponentProp --xmlFile "${xmlFile}" --compName "${compName}" --name "${name}" --value "${value}"
}

# Ref: https://cyclonedx.org/docs/1.4/json/#components_items_hashes
# Add the given sha256 hash to the given SBOM Component
addSBOMComponentHash() {
  local javaHome="${1}"
  local classpath="${2}"
  local xmlFile="${3}"
  local compName="${4}"
  local hash="${5}"
  "${javaHome}"/bin/java -cp "${classpath}" temurin.sbom.TemurinGenSBOM --addComponentHash --xmlFile "${xmlFile}" --compName "${compName}" --hash "${hash}"
}

# Ref: https://cyclonedx.org/docs/1.4/json/#components_items_properties
# Add the given Property name & value to the given SBOM Component
addSBOMComponentProperty() {
  local javaHome="${1}"
  local classpath="${2}"
  local xmlFile="${3}"
  local compName="${4}"
  local name="${5}"
  local value="${6}"
  "${javaHome}"/bin/java -cp "${classpath}" temurin.sbom.TemurinGenSBOM --addComponentProp --xmlFile "${xmlFile}" --compName "${compName}" --name "${name}" --value "${value}"
}

# Ref: https://cyclonedx.org/docs/1.4/json/#components_items_properties
# If the given property file exists, then add the given Property name with the given file contents value to the given SBOM Component
addSBOMComponentPropertyFromFile() {
  local javaHome="${1}"
  local classpath="${2}"
  local xmlFile="${3}"
  local compName="${4}"
  local name="${5}"
  local propFile="${6}"
  local value="N.A"
  if [ -e "${propFile}" ]; then
      value=$(cat "${propFile}")
      "${javaHome}"/bin/java -cp "${classpath}" temurin.sbom.TemurinGenSBOM --addComponentProp --xmlFile "${xmlFile}" --compName "${compName}" --name "${name}" --value "${value}"
  fi
}

