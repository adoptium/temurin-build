#!/bin/bash

# Import common SBOM functions
source ../sbin/common/sbom.sh

# Get Jenkins job parameters
privateKey=$1
publicKey=$2
inputSbom=$3
outputSignedSbom=$4

# Build cyclonedx library
buildCyclonedxLib

# Sign SBOM
signSBOM "$privateKey" "$publicKey" "$inputSbom" "$outputSignedSbom"
