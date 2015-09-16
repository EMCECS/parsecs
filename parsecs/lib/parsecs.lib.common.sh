#!/usr/bin/env bash

# Copyright (c) 2012-15 EMC Corporation
# All Rights Reserved
#
# This software contains the intellectual property of EMC Corporation
# or is licensed to EMC Corporation from third parties.  Use of this
# software and the intellectual property contained therein is expressly
# limited to the terms and conditions of the License Agreement under which
# it is provided by or on behalf of EMC.


#####################################
# parsecs common bash stuff library #
#####################################


# generic waitloop
# waitloop $function->(true/false) $timeout $iteration_delay $debug $message
waitloop() {
    local wltest=${1} # thing to exec that returns true(0) or false(>=1)
    local wlwait=${2:-"$general_timeout"} # seconds to wait for $wltest to return true
    local wliter=${3:-"$(( $ecsapi_hold_time * 2 ))"} # seconds to wait between iteration
    local wldebug=${4:-false} # true or false, always log iterations?
    shift 4
    local wltext="${*:-OP: pod ${PODNUM}: rack: ${RACK}: waiting for ${wltest} to succeed}"
    local wltime=$(date +%s)

    while ! ($wltest) && (( ( $(date +%s) - $wltime ) < $wlwait )) ; do
        ( $wldebug || $DEBUG ) && log $wltext
        sleep $wliter
    done
    if (( ( $(date +%s) - $wltime ) < $wlwait )); then
        return 0
    else
        return 1
    fi
}

# delay in an otherwise fast api waitloop
# waits for twice ecsapi_hold_time
api_waitloop_sleep() {
    sleep $(( $ecsapi_hold_time * 2 ))
}

general_sleep() {
    sleep $general_holdtime
}

# delay between API operations
api_sleep() {
    sleep ${ecsapi_hold_time}
}

# delay between IPMI operations
ipmi_sleep() {
    sleep ${ipmi_hold_time}
}

# merges two arrays, the first becoming keys; second, values.
# Third argument is the array key to access of the resulting array.
# You should probably switch to python.
xarray_get() {
    local x=($1)
    local y=($2)
    local v="$3"
    declare -A z=()
    for ((i=0;((i <= ( ${#x[@]} - 1 ) ));++i)); do
        key=${x[i]}
        z[$key]="${y[i]}"
    done
    echo ${z["$v"]}
}

# If you find yourself using these, you should consider
# refactoring or switching to pyrhon.
lock() {
    local lockfile="$script_bin/lock.${1}.lck"
    if ! [ -f "$lockfile" ]; then
        touch "$lockfile"
        return 0
    else
        return 1
    fi
}

lock_wait() {
    local lockfile="$script_bin/lock.${1}.lck"
    while [ -f "$lockfile" ]; do
        sleep 1
    done
}

unlock() {
    local lockfile="$script_bin/lock.${1}.lck"
    if [ -f "$lockfile" ]; then
        rm "$lockfile"
    fi
}
