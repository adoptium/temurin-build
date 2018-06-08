#!/bin/bash

if [ "${ARCHITECTURE}" == "x64" ]
then
  export PATH=/opt/rh/devtoolset-2/root/usr/bin:$PATH
  if [ -r /opt/rh/devtoolset-2/root/usr/bin/g++-NO ]; then
    export CC=/opt/rh/devtoolset-2/root/usr/bin/gcc
    export CXX=/opt/rh/devtoolset-2/root/usr/bin/g++
    ls -l $CC $CXX
    $CC --version
    $CXX --version
  fi
fi