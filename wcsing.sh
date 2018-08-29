#!/bin/bash
simg="$1" ; shift
rcfile="$1"; shift

if [ -n "$rcfile" ] ; then
    rcfile="--rcfile $rcfile"
fi

bindargs=""
for bind in $@
do
    bindargs="$bindargs --bind $bind"
done

singularity exec \
            $bindargs \
            $simg \
            env -i \
            WIRECELL_PATH=/usr/local/share/wirecell/data:/usr/local/share/wirecell/cfg \
            PATH=/bin:/usr/bin:/usr/local/bin:/usr/local/opt/wct/bin \
            LD_LIBRARY_PATH=/usr/local/lib:/usr/local/opt/wct/lib \
            TERM="$TERM" DISPLAY="$DISPLAY" PAGER="$PAGER" EDITOR="$EDITOR" LANG=C \
            HOME="$HOME" LOGNAME="$LOGNAME" XAUTHORITY="$XAUTHORITY" \
            /bin/bash $rcfile




