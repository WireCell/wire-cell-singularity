#!/bin/bash
simg="$1" ; shift
ups_dir="$1" ; shift
upsdev_dir="$1" ; shift
rcfile="$1"; shift

if [ -n "$rcfile" ] ; then
    rcfile="--rcfile $rcfile"
fi
if [ ! -d "$ups_dir" ] ; then
    echo "$0: directory to bind does not exist, making it now"
    mkdir -p "$ups_dir" || exit 1
fi
if [ ! -d "$upsdev_dir" ] ; then
    echo "$0: directory to bind does not exist, making it now"
    mkdir -p "$upsdev_dir" || exit 1
fi

singularity exec \
            --bind "$ups_dir":/usr/local/ups \
            --bind "$upsdev_dir":/usr/local/ups-dev \
            $simg \
            env -i \
            TERM="$TERM" DISPLAY="$DISPLAY" PAGER="$PAGER" EDITOR="$EDITOR" LANG=C \
            HOME="$HOME" LOGNAME="$LOGNAME" XAUTHORITY="$XAUTHORITY" USER="$USER" \
            /bin/bash $rcfile

# Don't run bash directly to avoid poluting container with native environment.
# As a side effect this polution somehow breaks bash history.
#            /bin/bash --noprofile $rcfile



