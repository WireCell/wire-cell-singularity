#!/bin/bash

# this gets run inside the container

wct=$1 ; shift
cd "$wct"
source /usr/local/ups/setup
setup wirecell dev -q e15:prof
echo $WIRECELL_FQ_DIR 

./waftools/wct-configure-for-ups.sh ups
./wcb -p --notests install
export WIRECELL_PATH=/usr/local/share/wirecell/cfg:/usr/local/share/wirecell/data
./wcb -p --alltests
