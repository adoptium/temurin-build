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

def pr_check_author(author):
    """
    Check that the author is acceptable for this PR.
    This could check they are not on a banned list, or that they
    do have an OCA, etc. etc.

    returns a tuple, [boolean, string] = [whether the check passed, a message to display in the PR]
    """
    print("Bogus author check")
    if author == "untrustedguy":
        print("Failed author check : %s" % author)
        return [ False, "** Failed author check %s **" % author ]

    return [ True, "Passed author check %s" % author ]

