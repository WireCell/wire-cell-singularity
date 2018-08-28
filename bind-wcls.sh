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

singularity exec \
            --bind /opt \
            --bind "$native_dir":/usr/local/ups-dev \
            $simg \
            env -i \
            TERM="$TERM" DISPLAY="$DISPLAY" PAGER="$PAGER" EDITOR="$EDITOR" LANG=C \
            HOME="$HOME" LOGNAME="$LOGNAME" XAUTHORITY="$XAUTHORITY" \
            /bin/bash $rcfile




