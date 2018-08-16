#!/bin/bash

# This here script installs a development version of WCT into a LS
# environment.  It's intended to run as root (yes) from a Singularity
# container build script.

# Why a script you ask?  Good question.  Because of the insanity that
# is known as UPS's "setup" script fails to work in whatever shell
# Singularity is running.  And more generaly, there's a bunch of fidly
# bits that are needed and keeping more than one container script in
# sync is a PITA, so crap goes here.

# It assumes that /usr/local/ups contains a built UPS "PRODUCTS" area


# set this to the most recent release
wirecell_release_version=v0_7_0a

# some UPS version string to give to the wirecell "product" we will build from source
wirecell_devel_version=dev

# UPS ROOT version
root_version=v6_12_06a

# the UPS "qualifiers"
ups_quals=e15:prof

source /usr/local/ups/setup

env

if [ ! -d /usr/local/ups/wirecell/${wirecell_devel_version}.version ] ; then
    ups declare wirecell ${wirecell_devel_version} \
        -f $(ups flavor) \
        -q ${ups_quals} \
        -r wirecell/${wirecell_devel_version} \
        -z /usr/local/ups \
        -U ups  \
        -m wirecell.table
    mkdir -p /usr/local/ups/wirecell/${wirecell_devel_version}/ups
    cp /usr/local/ups/wirecell/${wirecell_release_version}/ups/wirecell.table /usr/local/ups/wirecell/${wirecell_devel_version}/ups
fi

# hack alert, remove garbage installed by official scripts
junk=/usr/local/ups/wirecell/${wirecell_release_version}/wirecell-0.7.0/build/
if [ -d "$junk" ] ; then
    rm -rf "$junk"
fi

## not included, use system git
# setup git

echo "Getting WCT data and config packages"
mkdir -p /usr/local/share/wirecell
cd /usr/local/share/wirecell
git clone https://github.com/WireCell/wire-cell-cfg.git cfg
git clone https://github.com/WireCell/wire-cell-data.git data

setup wirecell ${wirecell_devel_version} -q ${ups_quals}
setup root ${root_version} -q ${ups_quals}

env

echo "Getting WCT source, building and installing"
cd /usr/local/src
git clone https://github.com/WireCell/wire-cell-build.git wct

cd /usr/local/src/wct
./switch-git-urls
git submodule init
git submodule update

./wcb configure \
    --with-tbb=no \
    --with-jsoncpp="$JSONCPP_FQ_DIR" \
    --with-jsonnet="$JSONNET_FQ_DIR" \
    --with-eigen-include="$EIGEN_DIR/include/eigen3" \
    --with-root="$ROOTSYS" \
    --with-fftw="$FFTW_FQ_DIR" \
    --with-fftw-include="$FFTW_INC" \
    --with-fftw-lib="$FFTW_LIBRARY" \
    --boost-includes="$BOOST_INC" \
    --boost-libs="$BOOST_LIB" \
    --boost-mt \
    --prefix="/usr/local/ups/wirecell/${wirecell_devel_version}/$(ups flavor)"


./wcb install  --notests || exit 1
export WIRECELL_PATH=/usr/local/share/wirecell/data:/usr/local/share/wirecell/cfg
./wcb --alltests
rm -rf build
# need to fix these tests....
rm -f util/test_*json*
