#!/usr/bin/env bash
invoked=$_
OPTIND=1

# Copyright (c) 2012-15 EMC Corporation
# All Rights Reserved
#
# This software contains the intellectual property of EMC Corporation
# or is licensed to EMC Corporation from third parties.  Use of this
# software and the intellectual property contained therein is expressly
# limited to the terms and conditions of the License Agreement under which
# it is provided by or on behalf of EMC.

### boostrap the environment
param="${!#}"
if [ -f /etc/parsecs.conf ]; then
    source /etc/parsecs.conf
fi
if [ -f $HOME/.parsecs.rc ]; then
    source $HOME/.parsecs.rc
fi
if [ -z "$script_home" ]; then
    echo "FATAL: parsecs is not properly configured."
    exit 1
fi
source "$script_bin/parsenv.sh" -p 0 -r 0 -v -c -l $@ || exit 1

### make sure the include dir exists and that we are in it.
if ! [ -d "$script_home/../include" ]; then
    if ! mkdir -p "$script_home/../include"; then
        echo "FATAL: can't mkdir $script_home/../include"
        exit 1
    fi
fi
if [ -d "$script_home/../include" ]; then
    if ! cd $script_home/../include; then
        echo "FATAL: can't cd into $script_home/../include"
        exit 1
    fi
else
    echo "FATAL: $script_home/../include doesn't exist!"
    exit 1
fi

include_dir="$PWD"

### if everything is good with the path, start the installation

### Packages used, recommended, or referenced by parsecs from yum repos
yum_pkgs="wget curl findutils git make dos2unix expect iotop glances gcc python-devel iftop ncurses jq htop pigz"
yum -y check-update
yum -y install epel-release
yum -y check-update
yum -y upgrade
yum -y ${yum_pkgs}

### Python packages for "new" scripts
### not used yet
# pip_pkgs="netifaces finch requests"
# /usr/bin/easy_install pip
# pip install ${pip_pkgs}

### symlink into parsecs scripts
git clone https://github.com/padthaitofuhot/resty.git || exit 1
chmod +x ${include_dir}/resty/resty
ln -s ${include_dir}/resty/resty ${script_bin}/resty
git clone https://github.com/padthaitofuhot/jkid.git || exit 1
chmod +x ${include_dir}/jkid/jkid
ln -s ${include_dir}/jkid/jkid ${script_bin}/jkid

### semaphore to flag installation complete
touch "$script_home/include.sem"
