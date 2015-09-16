#!/usr/bin/env bash

# Copyright (c) 2012-15 EMC Corporation
# All Rights Reserved
#
# This software contains the intellectual property of EMC Corporation
# or is licensed to EMC Corporation from third parties.  Use of this
# software and the intellectual property contained therein is expressly
# limited to the terms and conditions of the License Agreement under which
# it is provided by or on behalf of EMC.


# the rack here doesn't matter. it'll get overwritten by
# rack scripts. We just need the libraries here for
# bootstrapping
# boostrap the environment
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
source "$script_bin/parsenv.sh" -r 0 -l $@ || exit 1

do_ecs_install_pod() {
    # installs can be nonsequential
    errors=0
    $script_bin/ecs-install-rack.sh -p ${PODNUM} -r 1 -v -l auto &
    pid1=$!
    $script_bin/ecs-install-rack.sh -p ${PODNUM} -r 2 -v -l auto &
    pid2=$!
    wait ${pid1} || ((++errors))
    wait ${pid2} || ((++errors))

    if [ ${errors} -gt 0 ]; then
        exit ${errors}
    fi
}

case $param in
    auto)
        do_ecs_install_pod
    ;;
    *)
        log "ERROR: You need to specify an op to make the script go. This keeps anyone from accidentally running it."
    ;;
esac