#!/bin/bash
# ********************************************************************************
# Copyright (c) 2018 Contributors to the Eclipse Foundation
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

exit_script() {
    if [[ -z ${KEEP_CONTAINER} ]] ; then
      docker ps -a | awk '{ print $1,$2 }' | grep "$CONTAINER_NAME" | awk '{print $1 }' | xargs -I {} docker rm -f {}
    fi
    echo "Process exited"
    trap - SIGINT SIGTERM # clear the trap
    kill -- -$$ # Sends SIGTERM to child/sub processes
}

trap exit_script SIGINT SIGTERM 
