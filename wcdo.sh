#!/bin/bash

# These may be overridden in $HOME/.wcdo/main-local.sh
wcdo_image_cache="."
wcdo_image_url="https://www.phy.bnl.gov/~bviren/simg"


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

    local cache="${1:-$wcdo_image_cache}" ; shift
    local baseurl="${1:-$wcdo_image_url}" ; shift

    local bsifile="$(basename $sifile)"
    local sitmp="$cache/$bsifile"
    if [ ! -f "$sitmp" ] ; then
        wget -O "$sitmp" "$baseurl/$bsifile"  1>&2
    fi
    ln -sf "$sitmp" .
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
    if [ ! -d "$ups_products/.upsfiles" ] ; then
        echo "Priming UPS area" 
        mkdir -p "$ups_products/.upsfiles"
        cat > "$ups_products/.upsfiles/dbconfig" <<EOF
FILE = DBCONFIG
AUTHORIZED_NODES = *
VERSION_SUBDIR = 1
PROD_DIR_PREFIX = \${UPS_THIS_DB}
UPD_USERCODE_DIR = \${UPS_THIS_DB}/.updfiles
EOF
    fi
    if [ ! -d "$ups_products/.updfiles" ] ; then
        mkdir -p "$ups_products/.updfiles"
        cat > "$ups_products/.updfiles/updconfig" <<EOF
File = updconfig

GROUP:
  product       = ANY
  flavor        = ANY
  qualifiers    = ANY
  options       = ANY
  dist_database = ANY
  dist_node     = ANY

COMMON:
     UPS_THIS_DB = "\${UPD_USERCODE_DB}"
     UPS_PROD_DIR = "\${UPS_PROD_NAME}/\${UPS_PROD_VERSION}/\${DASH_PROD_FLAVOR}\${DASH_PROD_QUALIFIERS}"
  UNWIND_PROD_DIR = "\${PROD_DIR_PREFIX}/\${UPS_PROD_DIR}"
      UPS_UPS_DIR = "ups"
   UNWIND_UPS_DIR = "\${UNWIND_PROD_DIR}/\${UPS_UPS_DIR}"
 UPS_TABLE_FILE  = "\${UPS_PROD_NAME}.table"
UNWIND_TABLE_DIR = "\${UNWIND_UPS_DIR}"
END:
EOF
        cat > "$ups_products/.updfiles/updusr.pm" <<EOF
require 'default_updusr.pm';
EOF
    fi


    if [ -f wcdo.rc ] ; then
        echo "A wcdo.rc already exists.  Move it aside to get a fresh copy".
        return
    fi
    echo "Getting wcdo.rc from GitHub"
    wget https://raw.githubusercontent.com/WireCell/wire-cell-singularity/master/wcdo.rc
}


wcdo-wct-one () {
    local name="$1" ; shift     # required, "data", "cfg", etc.
    local dir="$1" ; shift      # required
    local acc="${1:-anonymous}" ;shift
    local br="${1:-master}" ;shift
    
    if [ ! -d "$dir" ] ; then
        mkdir -p "$dir"
    fi

    pushd "$dir"

    if [ ! -d .git ] ; then
        git init
    fi

    # start from known state
    git remote remove origin 2>/dev/null || true

    giturl="git@github.com:WireCell/wire-cell-${name}.git"
    if [ "$acc" = "anonymous" ] ; then
        giturl="https://github.com/WireCell/wire-cell-${name}.git"
    fi
    git remote add --tags origin "$giturl"
    git fetch
    git checkout $br

    popd
}

wcdo-wct-data () {
    local acc="${1:-anonymous}" ;shift
    local br="${1:-master}" ;shift
    if [ $br != "master" ] ; then
        echo "WCT data doesn't have branches, forcing master instead of $br"
        br="master"
    fi
    wcdo-wct-one data "$wct_data" "$acc" "$br"
}

wcdo-wct-cfg () {
    local acc="${1:-anonymous}" ;shift
    local br="${1:-master}" ;shift
    wcdo-wct-one cfg "$wct_cfg" "$acc" "$br"
}

wcdo-wct-source () {
    local acc="${1:-anonymous}" ;shift
    local br="${1:-master}" ;shift
    wcdo-wct-one build "$wct_dev" "$acc" "$br"

    pushd "$wct_dev"

    if [ "$acc" = "anonymous" ] ; then
        ./switch-git-urls anon
    else
        ./switch-git-urls dev
    fi
    git checkout -b $br $br
    git submodule init
    git submodule update
    if [ "$br" != "master" ] ; then
        git submodule foreach git checkout -b $br origin/$br
    else
        git submodule foreach git checkout master
    fi
    git submodule foreach git pull origin $br
    popd
}
wcdo-wct () {
    local acc="${1:-anonymous}" ;shift
    local br="${1:-master}" ;shift
    wcdo-wct-data "$acc" "$br"
    wcdo-wct-cfg "$acc" "$br"
    wcdo-wct-source "$acc" "$br"    
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
    local bindings="${here}:/wcdo"
    local wcdo_init=""
    if [ -d /cvmfs ] ; then
        bindings="$bindings /cvmfs"
        wcdo_init="source /cvmfs/larsoft.opensciencegrid.org/products/setup"
    fi
    for one in $morebindings
    do
        bindings="$bindings $one"
    done
    
    rcfile="wcdo-${name}.rc"
    shfile="wcdo-${name}.sh"

    touch $shfile
    chmod +w $shfile
    cat <<EOF > "$shfile"
#!/bin/bash 

# Run this to enter an image for project $name.
# This file is generated.

wcdo_image=${here}/${simage}
wcdo_generated_bindings="$bindings"
wcdo_bindings=""
wcdo_rcfile=${here}/${rcfile}

# Given shared hook, eg to add singularity location to PATH
# Or, override some wcdo_* variables
for script in \${HOME}/.wcdo/project-local.sh ${here}/wcdo-local.sh ${here}/wcdo-local-${name}.sh
do
    if [ -f \$script ] ; then
        source \$script
    fi
done

bindargs=""
for one in \$wcdo_bindings \$wcdo_generated_bindings
do
    bindargs="\$bindargs --bind \$one"
done

cmd="singularity exec \$bindargs \$wcdo_image env -i /bin/bash --rcfile \$wcdo_rcfile"

if [ "\$1" = "bundle" ] ; then

    keep=""
    for one in ${here}/wcdo.rc ${here}/wcdo-${name}.rc ${here}/wcdo-${name}.sh ${here}/wcdo-local-${name}.rc ${here}/wcdo-local-${name}.sh \$HOME/.wcdo/main-local.sh \$HOME/.wcdo/project-local.rc \$HOME/.wcdo/project-local.sh
    do
        if [ ! -f \$one ] ; then
            continue
        fi
        keep="\$keep \$(readlink -f \$one)"
    done
    bname="wcdo-bundle-${name}"
    tar -czf \${bname}.tgz \$keep
    sha1sum \$wcdo_image \${bname}.tgz > ${here}/\${bname}.txt
    echo \$cmd >> ${here}/\${bname}.txt
    ls -l \${bname}.*
    exit
fi

echo \$cmd
\$cmd

EOF
    chmod +x $shfile
    echo "Generated $shfile, don't edit"
    chmod 555 $shfile


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
        echo "Generated $lrcfile, please edit"
        chmod 644 $lrcfile
    fi

    touch $rcfile
    chmod +w $rcfile
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
export TERM="xterm-color"
export DISPLAY="$DISPLAY"
export PAGER="$PAGER"
export EDITOR="$EDITOR"
export LANG=C
export HOME="$HOME" 
export LOGNAME="$LOGNAME" 
export USER="$USER"
export XAUTHORITY="$XAUTHORITY"

# Finally include the set of wcdo-* functions.
source /wcdo/wcdo.rc
# Hook in more global rc files:
for maybe in \$HOME/.wcdo/project-local.rc /wcdo/wcdo-local.rc /wcdo/wcdo-local-${name}.rc
do
    if [ -f \$maybe ] ; then
        source \$maybe
    fi
done

EOF
    echo "Generated $rcfile, don't edit"
    chmod 444 $rcfile
}


wcdo-help () {
    cat <<EOF
This script has several command and is run like:

   wcdo.sh <cmd> [cmd options]

All commands assume current working directory is a "wcdo workspace".

The commands are:

  init

        initialize current directory as a wcdo workspace

  wct [access [branch]]

        Get Wire-Cell Toolkit source, data and configuration

  get-image <imagename> [cachedir [url]]

        Add a Singularity image by name to current directory

  make-project <projname> <imagename> [bindings]

        Make files to run and configure a project in the current directory

For details see:

https://github.com/WireCell/wire-cell-singularity/blob/master/wcdo.org

EOF
}

if [ -f $HOME/.wcdo/main-local.sh ] ; then
    source $HOME/.wcdo/main-local.sh
fi


cmd="${1:-help}"; shift
wcdo-$cmd $@



