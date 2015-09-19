#!/usr/bin/env bash

# Copyright (c) 2012-15 EMC Corporation
# All Rights Reserved
#
# This software contains the intellectual property of EMC Corporation
# or is licensed to EMC Corporation from third parties.  Use of this
# software and the intellectual property contained therein is expressly
# limited to the terms and conditions of the License Agreement under which
# it is provided by or on behalf of EMC.


###################################
# parsecs shell functions library #
###################################

# TODO: set jq to a var to respect $COLORIZE

slog() {
    o "PARSENV: $*"
}

# make help do something useful for a change
help() {
    slog "[ interactive shell commands ]"
    slog "help"
#    slog "chenv|che|ce [/]<pod>/<rack>[/arg1/arg2/arg ...]"
#    slog "chpod|chp <pod>" # not overloading `cp`
#    slog "chrack|chr|cr <rack>"
    slog "show|sh|s <var|nodes|sp|vdc|rg|ns|buckets|users|dtq>"
    slog "show|sh|s <audit|config|metadata|license|failzones>"
    slog "show|sh|s <cap|spcap|cookie|cookiefile|vdckey>"
    slog "rest [uri] [rackindex] [port]"
    slog "rerr <API error# code>"
    slog "GET [curl opts] [rel uri]"
    slog "PUT [curl opts] [rel uri] [json data]"
    slog "POST [curl opts] [rel uri] [json data]"
    slog "DELETE [curl opts] [rel uri]"
#    slog "ipmi <on|off|reboot|pxe|hdd|bios|bmc|sol|resetbmc> <RMM IP>"
}

reload() {
    $DEBUG && [[ ! "$@" =~ "-t" ]] && local v="-v"
    $COLORIZE && [[ ! "$@" =~ "-b" ]] && local c="-c"
    source $script_bin/parsenv.sh -p ${PODNUM} -r ${RACK} ${c} ${v} -f $@
}

rerr() {
    rest_error_map $1
}

rest_get() {
    local node=${rack_master[$RACKINDEX]}
    local uri=$1
    shift
    slog "REST: node $node: requesting ${@}..."
    rest "$uri"
    GET > >(jq -C .) 2> >(o)
    rest
}

#chpod() {
#    PODNUM=$1
#    reload
#}
#
#alias chp='chpod'
#
#chrack() {
#    RACK=$1
#    reload
#}
#
#alias chr='chrack'
#alias cr='chrack'
#
#chenv() {
#    if [ -z "$1" ]; then
#        slog "specify path: /pod/rack/arg 1/arg 2/arg ..."
#        slog "example: # ce /1/2/c/v"
#        slog "changes to pod 1 rack 2 and enables color and verbosity"
#    else
#        local args=("${@//\// }")
#        set -- ${args[@]}
#        local p=$1
#        local r=$2
#        shift 2
#        local a=''
#        for i in $@; do
#            a+="-$i "
#        done
#        reload -p $p -r $r $a
#    fi
#}
#
#alias che='chenv'
#alias ce='chenv'

show_head() {
    prompt_line "${BBlack}"
    slog "parsecs ${SCRIPT_VERSION} environment loaded for pod ${PODNUM} rack ${RACK}"
}

show_warn() {
    [ ${PODNUM} -eq 0 ] && slog "!!! operating on meta-pod (be careful!)"
    [ ${RACK} -eq 0 ] && slog "!!! operating on meta-rack (be careful!)"
}

show_vars() {
    slog "DEBUG = ${DEBUG} | COLORIZE = ${COLORIZE}"
    slog "RACKINDEX = ${RACKINDEX} | COOKIE_DIR = ${COOKIE_DIR}"
    slog "script_bin = ${script_bin} | script_logs = $script_logs"
}

show_nodes() {
    slog "nodes: ${ip_range[$RACKINDEX]}"
}

show_storagepools() {
    local node=${rack_master[$RACKINDEX]}
    slog "REST: node $node: requesting storage pool data from UI..."
    rest /storagepools $RACKINDEX 443 || return 1
    GET | jq -C . || return 1
    slog "REST: node $node: requesting storage pool data from ECS API..."
    rest /vdc/data-services/varrays || return 1
    GET | jq -C . || return 1
    rest
}

show_vdc() {
    rest_get /object/vdcs/vdc/list virtual data center data
}

show_vdc_events() {
    local node=${rack_master[$RACKINDEX]}
    starttime=$(date -Iminutes -d 00)
    starttime=${starttime%[-+]*}
    endtime=$(date -Iminutes)
    endtime=${endtime%[-+]*}
    namespace=${ce_nsname}
    slog "REST: node $node: requesting VDC audit events for namespace $namespace between $starttime and $endtime..."
    rest /vdc/events
    GET -q start_time="$starttime" -q end_time="$endtime" -q namespace="$namespace" | jq -C .
}

show_rg() {
    rest_get /vdc/data-service/vpools
}

show_ns() {
    rest_get /object/namespaces namespace data
}

show_buckets() {
    local namespace=${1:-"$ce_nsname"}
    local node=${rack_master[$RACKINDEX]}
    slog "REST: node $node: requesting bucket data..."
    rest /object/bucket || return 1
    GET -q "namespace=$namespace" | jq -C . || return 1
    rest
}

show_users() {
    rest_get /object/users user data
}

show_dtq() {
    local node=${rack_master[$RACKINDEX]}
    slog "DTQ: node $node: requesting directory table data..."
    ecs_dt_q $node
    slog "DTQ: node $node: DT queue length: ${unready_dt_num[$node]}"
}

show_license() {
    rest_get /license license data
}

show_config() {
    rest_get /config/object/properties config data
 }

show_metadata() {
   rest_get /config/object/properties/metadata/ config metadata
}

show_temp_failed_zones() {
    rest_get /tempfailedzone/allfailedzones temporary failed zones
}

show_capacity() {
    rest_get /object/capacity storage capacity
}

show_va_cap() {
    urn=$(ecs-get-sp-urn $RACKINDEX)
    rest_get /object/capacity/$urn storage capacity of storagepool $ce_vaname
}

show_cookie() {
    echo "\n$(<$(ecs-cookiefile $RACKINDEX))\n"
}

show_vdckey() {
    rest_get /object/vdcs/vdc/local/secretkey local VDC secretkey
}

show () {
    case $1 in
        env|environment) show_env;;
        var|vars) show_vars;;
        nodes) show_nodes;;
        va|varray|sp|storagepools) show_storagepools;;
        vdc) show_vdc;;
        vdckey) show_vdckey;;
        audit) show_vdc_events;;
        rg)show_rg;;
        ns)show_ns;;
        buckets) show_buckets $@;;
        users) show_users;;
        dtq) show_dtq;;
        cap) show_capacity;;
        vacap|spcap) show_va_cap;;
        failzones) show_temp_failed_zones;;
        conf|config) show_config;;
        meta|metadata) show_metadata;;
        lic|license) show_license;;
        cookie) show_cookie;;
        cookiefile) ecs-cookiefile $RACKINDEX;;
        *) help;;
    esac
}

# OK to overload `sh` since we're pure bash with shebangs everywhere
# and if anything specifically needs POSIX compatibility, it SHOULD
# (according to POSIX!) have a `#!/bin/sh` shebang or else it ought
# to expect nothing.
alias sh='show'
alias s='show'

#ipmi() {
#    case $1 in
#        reboot)
#            reboot_node $2
#        ;;
#        off)
#            ipmioff $2
#        ;;
#        on)
#            ipmion $2
#        ;;
#        hdd)
#            ipmihdd $2
#        ;;
#        pxe)
#            ipmipxe $2
#        ;;
#        bios)
#            ipmibios $2
#        ;;
#        resetbmc)
#            ipmi_reset_bmc $2
#        ;;
#        bmc)
#            echo "${ipmi_password}" | sshpass ssh ${ssh_options} ${ipmi_username}@${2}
#        ;;
#        sol)
#            echo "${ipmi_password}" | sshpass ssh ${ssh_options} ${ipmi_username}@${2} "start system1/sol1"
#        ;;
#        *)
#            help
#        ;;
#    esac
#}
