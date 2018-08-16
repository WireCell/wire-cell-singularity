#!/bin/bash
simg="$1" ; shift
native_dir="$1" ; shift
bind_target=$(singularity exec $simg \
    bash -c 'source /usr/local/ups/setup; setup wirecell dev -q e15:prof; echo $WIRECELL_FQ_DIR')
singularity shell --bind "$native_dir":"$bind_target" $simg 


