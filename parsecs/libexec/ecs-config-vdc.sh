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

do_config_rack() {
    log "OP: ECS: VDC: configuring pod ${PODNUM} rack ${RACK}"

    # Only configure VDCs from pod master (rack 1)
    if (( RACK == 1 )); then
        wait_for_dt_ready # wait for directory table to finish its queue
        log_run wait_for_cookies
        api_sleep
        # create VDC1 on rack 1
        #   - pod2-ecs1-vdc
        # create VDC2 on rack 1
        #   - pod2-ecs2-vdc
        wait_for_dt_ready
        ecs-create-vdcs-single || die "FATAL: ECS: VDC: pod ${PODNUM}: rack ${RACK}: could not create VDCs"
        api_sleep
        wait_for_dt_ready
        wait_for_vdc_visible # wait for the VDCs to show up in the APi
        # create replication groups:
        #   1 both VDCs (default)
        #   - pod2-ecs-geo-rg
        #   1 on VDC1
        #   - pod2-ecs1-rg
        #   1 on VDC2
        #   - pod2-ecs2-rg
        wait_for_dt_ready
        # TODO: need to check for API readiness between all these ops to avoid failures caused by nothing more than the API tempfailing.
        api_waitloop_sleep; api_waitloop_sleep; api_waitloop_sleep; api_waitloop_sleep
        waitloop ecs-create-rgs-single || die "FATAL: ECS: VDC: pod ${PODNUM}: rack ${RACK}: could not create replication groups"
        # create namespace on default replication group
        #   - ns-geo -> pod2-ecs-geo-rg
        #   - ns-ecs1 -> pod2-ecs1-rg
        #   - ns-ecs2 -> pod2-ecs2-rg
        wait_for_dt_ready
        api_waitloop_sleep
        waitloop ecs-create-namespaces-single || die "FATAL: ECS: VDC: pod ${PODNUM}: rack ${RACK}: could not create namespaces"
        # create object users with s3 and swift passwords
        #   - ns-geo-user -> ns-geo
        #   - ns-ecs1-user -> ns-ecs1
        #   - ns-ecs2-user -> ns-ecs2
        #   - s3 provided!
        #   - swift swift-password
        wait_for_dt_ready
        api_waitloop_sleep
        waitloop ecs-create-object-users-single || die "FATAL: ECS: VDC: pod ${PODNUM}: rack ${RACK}: could not create object users"
        # create default buckets
        #   - bucket1 -> ns-geo-user
        #   - bucket1 -> ns-ecs1-user
        #   - bucket1 -> ns-ecs2-user
        wait_for_dt_ready
        api_waitloop_sleep
        waitloop ecs-create-buckets-single || die "FATAL: ECS: VDC: pod ${PODNUM}: rack ${RACK}: could not create buckets"
        api_sleep
        log "OP: ECS: VDC: pod ${PODNUM}: rack ${RACK}: waiting for any remaining background processes to complete..."
        wait

        log "OK: ECS: VDC: pod ${PODNUM}: rack ${RACK}: complete"
        log_roll $LOGFILE
        return 0
    fi
}


case $param in
    auto)
        do_config_rack
    ;;
    *)
        log "ERROR: You need to specify an op to make the script go. This keeps anyone from accidentally running it."
    ;;
esac
