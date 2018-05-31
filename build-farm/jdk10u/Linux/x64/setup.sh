#!/bin/bash

[ -r /opt/rh/devtoolset-2/root/usr/bin/gcc ] && export CC=/opt/rh/devtoolset-2/root/usr/bin/gcc
[ -r /opt/rh/devtoolset-2/root/usr/bin/g++ ] && export CXX=/opt/rh/devtoolset-2/root/usr/bin/g++
