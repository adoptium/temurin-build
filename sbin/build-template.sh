#!/bin/bash

set +e

alreadyConfigured=$(/usr/bin/find . -name "config.status")

if [[ ! -z "$alreadyConfigured" ]] ; then
  echo "Not reconfiguring due to the presence of config.status"
else
  #Templated var that, gets replaced by build.sh
  {configureArg}

  exitCode=$?
  if [ "${exitCode}" -ne 0 ]; then
    exit 2;
  fi
fi

#Templated var that, gets replaced by build.sh
{makeCommandArg}

exitCode=$?
# shellcheck disable=SC2181
if [ "${exitCode}" -ne 0 ]; then
   exit 3;
fi
