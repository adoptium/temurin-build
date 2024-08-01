#!/bin/bash
# shellcheck disable=SC1091
# ********************************************************************************
# Copyright (c) 2017 Contributors to the Eclipse Foundation
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
# Entry point to build (Adoptium) OpenJDK binaries for any platform.
#
# 1. Source scripts to support configuration, docker builds and native builds.
# 2. Parse the Command Line Args
# 3. Set a host of configuration options based on args, platform etc
# 4. Display and then persist those configuration options
# 5. Build the binary in Docker or natively
#
################################################################################

set -eu

# i.e. Where we are
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Pull in configuration and build support
# shellcheck source=sbin/common/config_init.sh
source "${SCRIPT_DIR}/sbin/common/config_init.sh"

# shellcheck source=docker-build.sh
source "${SCRIPT_DIR}/docker-build.sh"

# shellcheck source=native-build.sh
source "${SCRIPT_DIR}/native-build.sh"

# shellcheck source=configureBuild.sh
source "${SCRIPT_DIR}/configureBuild.sh"

echo "Starting $0 to configure, build (Adoptium)OpenJDK binary"

# Configure the build, display the parameters and write the config to disk
# see ${SCRIPT_DIR}/sbin/common/config_init.sh for details
configure_build "$@"
writeConfigToFile

# Store params to this script as "buildinfo"
# Ensure arguments containing "spaces" are quoted
makeJdkArgs=""
for arg in "$@"; do
  # Quote the argument if it contains spaces
  if [[ "${arg}" =~ .*" ".* ]]; then
    makeJdkArgs="${makeJdkArgs} \"${arg}\""
  else
    makeJdkArgs="${makeJdkArgs} ${arg}"
  fi
done
echo "${makeJdkArgs}" > ./workspace/config/makejdk-any-platform.args

# Let's build and test the (Adoptium) OpenJDK binary in Docker or natively
if [ ! "${BUILD_CONFIG[CONTAINER_COMMAND]}" == "false" ] ; then
  buildOpenJDKViaDocker
else
  buildOpenJDKInNativeEnvironment
fi
