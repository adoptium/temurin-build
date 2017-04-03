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

from utils import ERROR_CODES, BUILD_HOME
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

    url = "https://api.github.com/repos/AdoptOpenJDK/openjdk-jdk8u/issues/" + ghprb_pull_id + "/comments"

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
        print_err(" > request_url %s" % url)
        print_err(" > http_code: %s" % http_e.code)
        print_err(" > api_response: %s" % http_e.read())
        print_err(" > data: %s" % posted_message)
    except urllib2.URLError as url_e:
        print_err("Failed to post message to Github.")
        print_err(" > request_url %s" % url)
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


def run_pr_checks():
    """
    Executes a set of pull request checks and returns their results.

    The plugin makes some very useful environment variables available.

    ghprbActualCommit
    ghprbActualCommitAuthor
    ghprbActualCommitAuthorEmail
    ghprbPullDescription
    ghprbPullId
    ghprbPullLink
    ghprbPullTitle
    ghprbSourceBranch
    ghprbTargetBranch
    sha1

    
    Returns a list of messages to post back to Github
    """
    # Ensure we save off the current HEAD (for revert)
    current_pr_head = run_cmd(['git', 'rev-parse', 'HEAD'], return_output=True).strip()
    pr_all_checks_pass = True
    pr_all_checks_results = list()

    print("Checking Foo")
    # Do a foo check here
    pr_all_checks_results.append("Foo check passes")

    print("Bogus check")
    author = os.environ["ghprbActualCommitAuthor"]
    if author == "gdams":
        pr_all_checks_pass = False
        pr_all_checks_results.append("Untrusted author %s" % author)
    
    # Ensure, after each check, that we're back on the current PR
    run_cmd(['git', 'checkout', '-f', current_pr_head])

    return [pr_all_checks_pass, pr_all_checks_results]


def main():
    ghprb_pull_id = os.environ["ghprbPullId"]
    ghprb_actual_commit = os.environ["ghprbActualCommit"]
    ghprb_pull_title = os.environ["ghprbPullTitle"]

    build_display_name = os.environ["BUILD_DISPLAY_NAME"]
    build_url = os.environ["BUILD_URL"]

    commit_url = "https://github.com/adoptopenjdk/openjdk-jdk8u/commit/" + ghprb_actual_commit

    # GitHub doesn't auto-link short hashes when submitted via the API.
    short_commit_hash = ghprb_actual_commit[0:7]

    # a function to generate comments for Github posting
    github_message = functools.partial(pr_message,
                                       build_display_name,
                                       build_url,
                                       ghprb_pull_id,
                                       short_commit_hash,
                                       commit_url)

    # post start comment
    post_message_to_github(github_message('has started'), ghprb_pull_id)

    all_checks_pass, all_checks_comments = run_pr_checks()

    if all_checks_pass:
        result_message = ' * This patch passes all checks.'
        exit_code = 0
    else:
        result_message = ' * This patch **fails one or more checks**.'
        exit_code = 1

    # post end comment
    result_comment = github_message('has finished')
    result_comment += '\n' + result_message + '\n'
    result_comment += '\n'.join(all_checks_comments)

    post_message_to_github(result_comment, ghprb_pull_id)

    sys.exit(exit_code)


if __name__ == "__main__":
    main()

