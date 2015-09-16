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
source "$script_bin/parsenv.sh" -l $@ || exit 1

do_config_sp() {
    log "OP: ECS: STORAGEPOOL: pod ${PODNUM}: rack ${RACK}: configuring storagepool"

    # wait for directory table to chill out
    ecs_dt_q_waitloop "${rack_master[$RACKINDEX]}" || \
        die "FATAL: ECS: DTQUEUE: pod ${PODNUM}: rack ${RACK}: directory table queue error or timeout"

    # wait for cookies to bake
    log_run wait_for_cookie || die "FATAL: ECS: AUTH: pod ${PODNUM}: rack ${RACK}: couldn't get cookie"

    # add license file on racks 1 & 2
    log_run ecs-add-license || die "FATAL: ECS: LICENSE: pod ${PODNUM}: rack ${RACK}: couldn't add license"
    api_sleep

    # deactivate callhome
    ( ecs-support-deactivate-callhome ) || die "FATAL: ECS: CONFIG: pod ${PODNUM}: rack ${RACK}: couldn't deactivate callhome"
    api_sleep

    # wait for directory table to chill out
    ecs_dt_q_waitloop "${rack_master[$RACKINDEX]}" || \
        die "FATAL: ECS: DTQUEUE: pod ${PODNUM}: rack ${RACK}: directory table queue error or timeout"

    # create storage pool on racks 1 & 2
    #   - pod2-ecs1-sp
    #   - pod2-ecs2-sp
    log_run ecs-create-sp || die "FATAL: ECS: STORAGEPOOL: pod ${PODNUM}: rack ${RACK}: storagepool creation failed, system may be inconsistent."
    api_sleep

    # Wait for the storage pool to be created.
    wait_for_sp || die "FATAL: ECS: STORAGEPOOL: pod ${PODNUM}: rack ${RACK}: storagepool creation failed, system may be inconsistent."
    api_sleep

    log "OK: ECS: STORAGEPOOL: pod ${PODNUM}: rack ${RACK}: complete"
    log_roll $LOGFILE
    return 0
}

case $param in
    auto)
        do_config_sp
    ;;
    *)
        log "ERROR: You need to specify an op to make the script go. This keeps anyone from accidentally running it."
    ;;
esac
