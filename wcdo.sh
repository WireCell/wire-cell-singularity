#!/bin/bash


wcdo-get-image () {
    local siname="$1"; shift
    if [ -z "$siname" ] ; then
        echo "usage: wcdo get-image <name> [dir [url]]" 1>&2
        echo -e "\t<name>\tan Singularity image name" 1>&2
        echo -e "\t<dir>\ta local directory to find images" 1>&2
        echo -e "\t<url>\tbase URL to find images" 1>&2
        return
    fi

    local sifile="${siname}.simg"
    if [[ "$siname" =~ \.simg$ ]] ; then
        sifile="$siname"
    fi
    if [ -f $(basename $sifile) ] ; then
        echo "Image already exists" 1>&2
        return
    fi
    if [ -f "$sifile" ] ; then
        ln -s $sifile .
        return
    fi

    local cache="${1:-.}" ; shift
    local baseurl="${1:-https://www.phy.bnl.gov/~bviren/simg}" ; shift

    local bsifile="$(basename $sifile)"
    local sitmp="$cache/$bsifile"
    if [ ! -f "$sitmp" ] ; then
        wget -O "$sitmp" "$baseurl/$bsifile"  1>&2
    fi
    ln -sf "$sitmp" .
}

wcdo-git-it () {
    local dir="$1" ; shift
    local gitcmd="$@"

    if [ -d "$dir" ] ; then
        return
    fi
    mkdir -p $dir
    pushd $dir
    $gitcmd 
    popd
}

# These semantically identified directories need to be synced on both
# native and container side.  They get baked into the generated rc file below.
wct_dev="src/wct"
mrb_dev="src/mrb"
wct_data="share/wirecell/data"
wct_cfg="share/wirecell/cfg"
ups_products="lib/ups"

# Initialize current directory as a workspace project
wcdo-init () {
    if [ ! -d "$mrb_dev" ] ; then mkdir -p "$mrb_dev" ; fi
    if [ ! -d "$ups_products" ] ; then mkdir -p "$ups_products" ; fi

    wcdo-git-it "$wct_dev" "git clone --recursive git@github.com:WireCell/wire-cell-build.git ."
    wcdo-git-it "$wct_data" "git clone --depth=1 https://github.com/WireCell/wire-cell-data.git ."
    wcdo-git-it "$wct_cfg" "git clone https://github.com/WireCell/wire-cell-cfg.git ."

    if [ -f wcdo.rc ] ; then
        echo "A wcdo.rc already exists.  Move it aside to get a fresh copy".
        return
    fi
    echo "Getting wcdo.rc from GitHub"
    wget https://raw.githubusercontent.com/WireCell/wire-cell-singularity/master/wcdo.rc
}



# Make a project in the current workspace current directory
# This creates wcdo-*.sh and wcdo-*.rc files
wcdo-make-project () {
    local name="$1" ; shift
    local simage="$1" ; shift
    local morebindings=$@

    if [ -z "$simage" ] ; then
        echo "usage wcdo-make-project <name> <image>"
        echo -e "\t<name>\tsome short name for the project"
        echo -e "\t<image>\ta Singularity image file"
        return
    fi

    wcdo-get-image $simage
    local siname=$(basename $simage .simg)
    simage="${siname}.simg"     # wash

    local here=$(pwd)

    # Bind workspace and any extras
    local bindargs="--bind ${here}:/wcdo"
    local wcdo_init=""
    if [ -d /cvmfs ] ; then
        bindargs="$bindargs --bind /cvmfs"
        wcdo_init="source /cvmfs/larsoft.opensciencegrid.org/products/setup"
    fi
    for one in $morebindings
    do
        bindargs="$bindargs --bind $one"
    done
    
    rcfile="wcdo-${name}.rc"
    shfile="wcdo-${name}.sh"

    cat <<EOF > "$shfile"
#!/bin/bash 

# Run this to enter an image for project $name.
# This file is generated.

# Given shared hook, eg to add singularity location to PATH
for one in local local-${name}
do
    script=${here}/wcdo-\${one}.sh
    if [ -f \$script ] ; then
        source \$script
    fi
done

singularity exec $bindargs "${here}/${simage}" env -i /bin/bash --rcfile "${here}/$rcfile"
EOF
    chmod +x $shfile
    echo "Generated $shfile"


    local lrcfile="wcdo-local-${name}.rc"
    if [ -f "$lrcfile" ] ; then
        echo "Local rc file exists: $lrcfile"
    else
        cat <<EOF > $lrcfile
#!/bin/bash

# This is a local wcdo rc file for project ${name}.
# It was initally generated but is recomended for customizing by you, dear user.
# It is included at the end of the main RC files.
    
# These are optional but required if wcdo-mrb-* commands are to be used.
wcdo_mrb_project_name=""
wcdo_mrb_project_version=""
wcdo_mrb_project_quals=""

# Additional variables may be usefully set since this file was
# first generated.  

# It is perhaps useful to end this with some command to be called 
# on each entry to the contaner.
# $wcdo_init

EOF
        echo "Generated $lrcfile"
    fi

    cat <<EOF > "$rcfile"
#!/bin/bash

# This is a bash RC file for project $name.
# It is generated and should NOT be edited.
# Instead, create and edit wcdo-local.rc for 
# all projects or wcdo-local-${name}.rc for this one.


# Give the container a name, eg for the shell prompt.
wcdo_simg="$siname"

# Canonical locations inside native-side $wcdo_workspace
wcdo_wct_dev=/wcdo/$wct_dev
wcdo_mrb_dev=/wcdo/$mrb_dev
wcdo_wct_data=/wcdo/$wct_data
wcdo_wct_cfg=/wcdo/$wct_cfg
wcdo_ups_products=/wcdo/$ups_products

# prime this
WIRECELL_PATH=${wcdo_wct_data}:${wcdo_wct_cfg}

# Some limited chunks of user environment to pass through.
PATH=/bin:/usr/bin:/usr/local/bin:/wcdo/bin 
LD_LIBRARY_PATH=/usr/local/lib:/wcdo/lib 
TERM="$TERM"
DISPLAY="$DISPLAY"
PAGER="$PAGER"
EDITOR="$EDITOR"
LANG=C
TERM=xterm-color
HOME="$HOME" 
LOGNAME="$LOGNAME" 
USER="$USER"
XAUTHORITY="$XAUTHORITY"

# Finally include the set of wcdo-* functions.
source /wcdo/wcdo.rc
# Given shared hook, eg to add singularity location to PATH
if [ -f /wcdo/wcdo-local.rc ] ; then
    source /wcdo/wcdo-local.rc
fi
if [ -f /wcdo/wcdo-local-${name}.rc ] ; then
    source /wcdo/wcdo-local-${name}.rc
fi

EOF
    echo "Generated $rcfile"
}


wcdo-help () {
    cat <<EOF
This script has several command and is run like:

   wcdo.sh <cmd> [cmd options]

All commands assume current working directory is a "wcdo workspace".

The commands are:

  init          initialize current directory as a wcdo workspace

  get-image     add a Singularity image by name to current directory

  make-project  make files to run and configure a project in the current directory

EOF
}

cmd="${1:-help}"; shift
wcdo-$cmd $@



