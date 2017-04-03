#!/usr/bin/env python2

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

import os

BUILD_HOME = os.path.abspath(os.path.join(os.path.dirname(os.path.realpath(__file__)), "../../"))
USER_HOME = os.environ.get("HOME")
ERROR_CODES = {
    "ERROR_GENERAL": 100,
    "ERROR_TIMEOUT": 101,
    "ERROR_STYLE": 102,
    "ERROR_BUILD": 103,
    "ERROR_SANITY": 104
}

