# Create a default SBOM json file: ${sbomJson}
createSBOMFile() {
  "${javaHome}"/bin/java -cp "${classpath}" temurin.sbom.TemurinGenSBOM --createNewSBOM --jsonFile "$sbomJson"
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


# Ref: https://cyclonedx.org/docs/1.4/json/#components
# To add new component into 'components'
addaddSBOMComponent(){
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
# addSBOMComponentFromFile() {
#   local javaHome="${1}"
#   local classpath="${2}"
#   local jsonFile="${3}"
#   local compName="${4}"
#   local description="${5}"
#   local name="${6}"
#   local propFile="${7}"
#   # always create component in sbom
#   "${javaHome}"/bin/java -cp "${classpath}" temurin.sbom.TemurinGenSBOM --addComponent --jsonFile "${jsonFile}" --compName "${compName}" --description "${description}"
#   local value="N.A" # default set to "N.A" as value for variant does not have $propFile generated in prepareWorkspace.sh
#   if [ -e "${propFile}" ]; then
#       value=$(cat "${propFile}")
#   fi
#   "${javaHome}"/bin/java -cp "${classpath}" temurin.sbom.TemurinGenSBOM --addComponentProp --jsonFile "${jsonFile}" --compName "${compName}" --name "${name}" --value "${value}"
# }

# Ref: https://cyclonedx.org/docs/1.4/json/#components_items_properties
# Add the given Property name & value to the given SBOM Component
addSBOMComponentProperty() {
  local javaHome="${1}"
  local classpath="${2}"
  local jsonFile="${3}"
  local compName="${4}"
  local name="${5}"
  local value="${6}"
  if [ "${isFromFile}" == "true"]; then
   local value=$(cat "${value}")
    "${javaHome}"/bin/java -cp "${classpath}" temurin.sbom.TemurinGenSBOM --addComponentProp --jsonFile "${jsonFile}" --compName "${compName}" --name "${name}" --value "${value}"
  fi
}

Ref: https://cyclonedx.org/docs/1.4/json/#components_items_properties
If the given property file exists, then add the given Property name with the given file contents value to the given SBOM Component
addSBOMComponentPropertyFromFile() {
  local javaHome="${1}"
  local classpath="${2}"
  local jsonFile="${3}"
  local compName="${4}"
  local name="${5}"
  local propFile="${6}"
  if [ -e "${propFile}" ]; then
      local value=$(cat "${propFile}")
      "${javaHome}"/bin/java -cp "${classpath}" temurin.sbom.TemurinGenSBOM --addComponentProp --jsonFile "${jsonFile}" --compName "${compName}" --name "${name}" --value "${value}"
  fi
}

# Ref: https://cyclonedx.org/docs/1.4/json/#externalReferences
addComponentExternalReference() {
  local javaHome="${1}"
  local classpath="${2}"
  local jsonFile="${3}"
  local comment="${4}"
  local type="${5}"
  local url="${6}"
  "${javaHome}"/bin/java -cp "${classpath}" temurin.sbom.TemurinGenSBOM --addExternalReference --jsonFile "${jsonFile}" --url "${url}" --type "${type}" --comment "${comment}"
}
