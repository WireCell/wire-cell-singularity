#!/bin/bash
simg="$1" ; shift
native_dir="$1" ; shift
rcfile="$1"; shift

if [ -n "$rcfile" ] ; then
    rcfile="--rcfile $rcfile"
fi
if [ ! -d "$native_dir" ] ; then
    echo "bind-wct: directory to bind does not exist, making it now"
    mkdir -p "$native_dir"
fi

bind_target=$(singularity exec $simg \
    bash -c 'source /usr/local/ups/setup; setup wirecell dev -q e15:prof; echo $WIRECELL_FQ_DIR')
singularity exec --bind "$native_dir":"$bind_target" $simg /bin/bash $rcfile



