#!/bin/bash
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# Purpose: This script was contains colour codes that will be commonly used across multiple scripts

# Escape code
esc=$(echo -en "\033")

# Set colors
# shellcheck disable=SC2034
error="${esc}[0;31m"
# shellcheck disable=SC2034
good="${esc}[0;32m"
# shellcheck disable=SC2034
info="${esc}[0;33m"
# shellcheck disable=SC2034
git="${esc}[0;34m"
# shellcheck disable=SC2034
normal=$(echo -en "${esc}[m\017")

