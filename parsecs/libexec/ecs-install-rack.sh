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
    echo "ERROR: parsecs is not properly configured."
    exit 1
fi
source "$script_bin/parsenv.sh" $@ -f || exit 1

do_install_rack() {
    log "OP: ecs-install-rack: resetting pod $PODNUM rack $RACK"
    send_push_files &
    send_release_files &
    wait
    # run pre-install validation pass
    parsecs -p ${PODNUM} -j $RACK -d -c $COLORIZE || die_fatal_error
    # run installer
    parsecs -p ${PODNUM} -i $RACK -d -c $COLORIZE || die_fatal_error
    # clean up extra script junk
    # parsecs -p ${PODNUM} -r $RACK -z -d -c $COLORIZE || die_fatal_error
    # log "OP: removing parsecs from nodes"
    # rm_parsecs

    reap_logs
    log "OP: waiting for any remaining background processes to complete..."
    wait
    log "NOTICE: ecs-reset-rack: rack $RACK reset complete"
    log_roll $LOGFILE
    return 0
}

case $param in
    auto)
        do_install_rack || {
            log "FATAL: A fatal error was caught. Manual intervention may be necessary."
            exit 1
        }
    ;;
    *)
        : # noop
    ;;
esac
