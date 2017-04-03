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

#
# This script depends upon environment variables set by the caller,
# which is expected to be Jenkins and the Jenkins PR builder plugin.
#


from __future__ import print_function
import os
import sys
import json
import urllib2
import functools
import subprocess

from utils import BUILD_HOME
from utils.shellutils import run_cmd


def print_err(msg):
    """
    Prints a set of arguments on STDERR.

    msg : String message
    """
    print(msg, file=sys.stderr)


def post_message_to_github(msg, ghprb_pull_id):
    """
    Adds a message to a given Github pull request.

    msg : String message
    ghprb_pull_id : Integer Github pull request identifier
    """

    print("Posting message to Github PR %s" % ghprb_pull_id)

    posted_message = json.dumps({"body": msg})

    url = "https://api.github.com/repos/adoptopenjdk/openjdk-jdk8u/issues" + ghprb_pull_id + "/comments"

    github_oauth_key = os.environ["GITHUB_OAUTH_KEY"]

    request = urllib2.Request(url,
                              headers={
                                  "Authorization": "token %s" % github_oauth_key,
                                  "Content-Type": "application/json"
                              },
                              data=posted_message)
    try:
        response = urllib2.urlopen(request)

        if response.getcode() == 201:
            print(" Success")
    except urllib2.HTTPError as http_e:
        print_err("Failed to post message to Github.")
        print_err(" > http_code: %s" % http_e.code)
        print_err(" > api_response: %s" % http_e.read())
        print_err(" > data: %s" % posted_message)
    except urllib2.URLError as url_e:
        print_err("Failed to post message to Github.")
        print_err(" > urllib2_status: %s" % url_e.reason[1])
        print_err(" > data: %s" % posted_message)


def pr_message(build_display_name,
               build_url,
               ghprb_pull_id,
               short_commit_hash,
               commit_url,
               msg,
               post_msg=''):
    # align the arguments properly for string formatting
    str_args = (build_display_name,
                msg,
                build_url,
                ghprb_pull_id,
                short_commit_hash,
                commit_url,
                str(' ' + post_msg + '.') if post_msg else '.')
    return '**[Test build %s %s](%stestReport)** for PR %s at commit [`%s`](%s)%s' % str_args


def run_pr_checks(pr_tests, ghprb_actual_commit, sha1):
    """
    Executes a set of pull request checks.

    pr_tests : list of tests to be run
    ghprb_actual_commit : the PR long hash value
    
    Returns a list of messages to post back to Github
    """
    # Ensure we save off the current HEAD (for revert)
    current_pr_head = run_cmd(['git', 'rev-parse', 'HEAD'], return_output=True).strip()
    pr_results = list()

    for pr_test in pr_tests:
        test_name = pr_test + '.sh'
        pr_results.append(run_cmd(['bash', os.path.join(BUILD_HOME, 'jenkins', 'pr-tests', test_name),
                                   ghprb_actual_commit, sha1],
                                  return_output=True).rstrip())
        # Ensure, after each test, that we're back on the current PR
        run_cmd(['git', 'checkout', '-f', current_pr_head])
    return pr_results


def run_tests(timeout):
    """
    Runs the `jenkins/run-pr-tests` script and responds with the correct message.

    timeout : length of time to wait for the tests to run.

    Returns a tuple containing the test result code and the message to post to the PR.
    """

    test_result_code = subprocess.Popen(['timeout',
                                         timeout,
                                         os.path.join(BUILD_HOME, 'jenkins', 'run-pr-tests')]).wait()

    failure_message_from_errcode = {
        1: 'executing the `jenkins/run-pr-tests` script',  # error to denote this script failures
        ERROR_CODES["ERROR_GENERAL"]: 'some tests',
        ERROR_CODES["ERROR_TIMEOUT"]: 'due to timeout, after a wait of \`%s\`' % (tests_timeout),
        ERROR_CODES["ERROR_STYLE"]: 'Java style tests',
        ERROR_CODES["ERROR_BUILD"]: 'to build',
        ERROR_CODES["ERROR_SANITY"]: 'sanity tests'
    }

    if test_result_code == 0:
        test_result_note = ' * This patch passes all tests.'
    else:
        test_result_note = ' * This patch **fails %s**.' % failure_message_from_errcode[test_result_code]

    return [test_result_code, test_result_note]


def main():
    # Important Environment Variables
    # ---
    # $ghprbActualCommit
    #   This is the hash of the most recent commit in the PR.
    #   The merge-base of this and master is the commit from which the PR was branched.
    # $sha1
    #   If the patch merges cleanly, this is a reference to the merge commit hash
    #     (e.g. "origin/pr/2606/merge").
    #   If the patch does not merge cleanly, it is equal to $ghprbActualCommit.
    #   The merge-base of this and master in the case of a clean merge is the most recent commit
    #     against master.
    ghprb_pull_id = os.environ["ghprbPullId"]
    ghprb_actual_commit = os.environ["ghprbActualCommit"]
    ghprb_pull_title = os.environ["ghprbPullTitle"]
    sha1 = os.environ["sha1"]

    # Marks this build as a pull request build.
    os.environ["OPENJDK_PRB"] = "true"

    build_display_name = os.environ["BUILD_DISPLAY_NAME"]
    build_url = os.environ["BUILD_URL"]

    commit_url = "https://github.com/adoptopenjdk/openjdk-jdk8u/commit/" + ghprb_actual_commit

    # GitHub doesn't auto-link short hashes when submitted via the API, unfortunately. :(
    short_commit_hash = ghprb_actual_commit[0:7]

    # format: http://linux.die.net/man/1/timeout
    # must be less than the timeout configured on Jenkins
    tests_timeout = "250m"

    # Array to capture all test names to run on the pull request. These tests are represented
    # by their file equivalents in the jenkins/pr-tests/ directory.
    #
    # To write a PR test:
    #   * the file must reside within the jenkins/pr-tests/ directory
    #   * be an executable bash script
    #   * accept two arguments on the command line,
    #       the first being the Github PR long commit hash, and
    #       the second the Github SHA1 hash.
    #   * return a string that will be posted to Github
    pr_tests = [
        "pr-mergeability"
        # add more tests here
    ]

    # a function to generate comments for Github posting
    github_message = functools.partial(pr_message,
                                       build_display_name,
                                       build_url,
                                       ghprb_pull_id,
                                       short_commit_hash,
                                       commit_url)

    # post start comment
    post_message_to_github(github_message('has started'), ghprb_pull_id)

    pr_check_results = run_pr_checks(pr_tests, ghprb_actual_commit, sha1)

    test_result_code, test_result_message = run_tests(tests_timeout)

    # post end comment
    result_comment = github_message('has finished')
    result_comment += '\n' + test_result_message + '\n'
    result_comment += '\n'.join(pr_check_results)

    post_message_to_github(result_comment, ghprb_pull_id)

    sys.exit(test_result_code)


if __name__ == "__main__":
    main()

