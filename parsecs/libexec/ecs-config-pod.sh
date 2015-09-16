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

# TODO: fix this so it's not required:
# for multirack scripts, always set the base rack to 1
source "$script_bin/parsenv.sh" -r 1 -l $@ || exit 1

do_config_pod() {
    log "OP: ECS: CONFIG: configuring pod $PODNUM"

    $script_bin/ecs-config-sp.sh -p ${PODNUM} -r 1 -l -v auto &
    pid1=$!
    $script_bin/ecs-config-sp.sh -p ${PODNUM} -r 2 -l -v auto &
    pid2=$!
    wait $pid1 || die_fatal_error
    wait $pid2 || die_fatal_error

    $script_bin/ecs-config-vdc.sh -p ${PODNUM} -r 1 -l -v auto || die_fatal_error

    log "OP: ECS: CONFIG: pod ${PODNUM}: waiting for any remaining background processes to complete..."
    wait
    log "OK: ECS: pod ${PODNUM}: complete"
    return 0
}

case $param in
    auto)
        do_config_pod
    ;;
    *)
        log "ERROR: You need to specify an op to make the script go. This keeps anyone from accidentally running it."
    ;;
esac
