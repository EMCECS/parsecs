#!/usr/bin/env bash

# Copyright (c) 2012-15 EMC Corporation
# All Rights Reserved
#
# This software contains the intellectual property of EMC Corporation
# or is licensed to EMC Corporation from third parties.  Use of this
# software and the intellectual property contained therein is expressly
# limited to the terms and conditions of the License Agreement under which
# it is provided by or on behalf of EMC.


###############################
# parsecs ECS control library #
###############################


##### ECS CLI ecscli.profile
#
# keep the paths clean.
# the default ecscli.profile config bloats paths QUICKLY
if ! [[ "${PATH}" =~ ^.*ecscli.*$ ]]; then
    _oldpath="${PATH}"
    _oldpypath="${PYTHONPATH}"
    export _oldpath
    export _oldpypath
else
    PATH="${_oldpath}"
    PYTHONPATH="${_oldpypath}"
fi
#
# build env for ecscli.py
COOKIE_BASE="$script_home/cookies"
ECS_CLI_INSTALL_DIR="/opt/storageos/cli"
_ecsclipath="/opt/storageos/cli/bin/ecscli-2.1-py2.7.egg/ecscli"
_clipath="/opt/storageos/cli/bin:/opt/storageos/cli"
PATH="$_ecsclipath:$PATH"
PYTHONPATH="$_ecsclipath:$PYTHONPATH"
export PATH="$_clipath:$PATH"
export PYTHONPATH="$_clipath:$PYTHONPATH"
ECS_PORT=4443
ECS_UI_PORT=443
ECS_CONTROL_API_VERSION=
ECS_AUTHENTICATED=false
ECS_TOKEN=
COOKIE_DIR=${COOKIE_DIR:-"${COOKIE_BASE}/index${RACKINDEX}"}
COOKIE_FILE=${COOKIE_FILE:-"${COOKIE_DIR}/${ecs_user}cookie"}
ECS_HOSTNAME=${ECS_HOSTNAME:-"${rack_master[RACKINDEX]}"}
#
#####


##### ecscli.py wrappers
# according to the API docs this is available via HTTP GET /cli
# unsure which version it is or what capabilities/bugs it has.
#

ecs-cmd() {
    local index="$1"
    local cmd="$2"
    local sub="$3"
    shift 3
    local args=( $@ )
    local run=
    ecsclicmd="ecscli.py ${cmd} ${sub} -cf "$(ecs-cookiefile ${index})" -port ${ecs_port} -hostname ${rack_master[index]} ${args[@]}"
    debug "${ecsclicmd}"
    ${ecsclicmd}
}

ecs () {
    ecs-cmd ${RACKINDEX} ${@}
}

#
#####

##### directory table queue helpers
#
# *in case of directory table queue issues break glass*
#
# track dtqs for multiple nodes
declare -A unready_dt_num
#
# give it a node IP and it will return 0 if ready
# or 1 if not which should always be zero before
# proceeding.
# get dt qsize, use python to handle the xml, return 1 if any queue
ecs_dt_q() {
    local node="$1"
    unready_dt_num[$node]=1
    unready_dt_num[$node]=$(python -c "import os, xml.etree.ElementTree as ET; print ET.fromstring('$(curl -sq -m $api_timeout http://$node:9101/stats/dt/DTInitStat/)').find('entry').find('unready_dt_num').text") || return 1 # XML oneliner, NOH8M8
    if (( ${unready_dt_num[$node]} > 0 )); then
        return 1
    else
        return 0
    fi
}
# waitloop for dtq
# TODO: refactor into generic waitloop
ecs_dt_q_waitloop() {
    local node="$1"
    local seconds=0
    seconds=$(date +%s)
    log "ECS: DTQ: pod ${PODNUM}: node: ${node}: waiting for directory table queue to zero ( requesting qsize... )"
    while ! ecs_dt_q ${node} && ! (( ( $(date +%s) - seconds ) >= dt_ready_timeout )); do
        log "ECS: DTQ: pod ${PODNUM}: node: ${node}: waiting for directory table queue to zero ( qsize = ${unready_dt_num[$node]} )"
        api_waitloop_sleep
    done
    if (( ( $(date +%s) - seconds ) >= dt_ready_timeout )); then
        return 1
    else
        return 0
    fi
}
#
# only when rack = 0 ! TODO: make meta ops work as a wildcard rather than nothing
wait_for_dt_ready() {
    ecs_dt_q_waitloop "${rack_master[$(( ${RACKINDEX} ))]}"
}
#
#####

##### authentication
#

### die on oopsie auth against zero objects
die_meta_object() {
    log "FATAL: One does not simply authenticate against a meta-object."
    log "FATAL: Use 'chpod' and 'chrack' to select a real pod+rack and"
    log "FATAL: try again."
    quit 1
}

# authenticate and return cookiefile path for a given rack number
# refactored to pure bash 2015-14-09
ecs-cookiefile() {

    local tmp=''
    local out=''
    local index=${1:-"${RACKINDEX}"}
    local old_cookie=''
    local cookie=''
    local resp=''

    local COOKIE_DIR="${COOKIE_BASE}/index${index}"
    local COOKIE_FILE="${COOKIE_DIR}/${ecs_user}cookie"

    if (( $RACKINDEX == 0 )) || (( $PODNUM == 0)) || (( $RACK == 0 )); then
        die_meta_object
        return 1
    fi

    if ! [ -d "${COOKIE_DIR}" ]; then
        mkdir -p "${COOKIE_DIR}"
    fi

    # IF there is no cookie file OR if there is an empty cookie file OR if the cookie file is older than 60 minutes,
    # THEN let's actually talk to the (potentially very slow) API and try to get a valid cookie.
    if ( [ ! -f "${COOKIE_FILE}" ] ) \
    || ( [ -f "${COOKIE_FILE}" ] && [ -z "$(<${COOKIE_FILE})" ] ) \
    || ( [ -f "${COOKIE_FILE}" ] && (( $(date +%s -r ${COOKIE_FILE}) < $(date +%s -d "-60 min") )) )
    then

        # if there's a cookiefile, read it and see if there's any contents.
        # if so, try to reauth against the contents.
        if [ -f "${COOKIE_FILE}" ]; then
            old_cookie=$(<${COOKIE_FILE})
            if [ -z "$old_cookie" ]; then
                rm -f $COOKIE_FILE
            fi
        fi

        # set up the login endpoint
        htraw "https://${rack_master[${index}]}:${ecs_port}/login"

        # make a temp file and store the headers from our request into that file
        out="$(mktemp)"
        # if we have an old cookie, then let's try to reauth it.
        if [ -z "$old_cookie" ]; then
            tmp=$(GET -D "${out}" -u $ecs_user:$ecs_pass)
        else
            tmp=$(GET -D "${out}" -H "X-SDS-AUTH-TOKEN: $old_cookie")
        fi
        # get the cookie from the temp file
        cookie=$(grep X-SDS-AUTH-TOKEN "${out}")
        echo ${cookie##*\:\ } >${COOKIE_FILE}
        # get all the response headers
        resp=$(<"${out}")
        # remove the temp file
        rm -f "${out}"

        # if login succeeded and we got a cookie in the file, then everything is good.
        if [[ "$resp" =~ "200" ]]; then
            if [ -f "${COOKIE_FILE}" ] && ! [ -z "$(<${COOKIE_FILE})" ]; then
                echo "${COOKIE_FILE}"
                # shell helper var when sourcing parsenv.sh for one-liners
                ECS_TOKEN=${cookie##*\:\ }
                export ECS_TOKEN
                return 0
            else
                # if login succeded and we didn't get a cookie in the file, then something weird
                # happened and we error out.
                echo "/dev/null"
                >&2 o "ECS: REST: pod ${PODNUM}: rack ${RACK}: node ${rack_master[${index}]}: login successful, but got no cookie!"
                return 1
            fi
        else
            # if login failed and we were trying to reauth an old cookie, then try again without the old cookie.
            if ! [ -z "$old_cookie" ]; then
                rm -f $COOKIE_FILE
                ecs-cookiefile ${index}
            # if we were doing password auth and login failed, then the whole thing failed.
            else
                echo "/dev/null"
                >&2 o "ECS: REST: pod ${PODNUM}: rack ${RACK}: node ${rack_master[${index}]}: login failed, no cookie for us!"
                return 1
            fi
        fi
    # OTHERWISE, just spam the old cookie and skip talking to the API. Not as stable, but can be easily
    # worked around by deleting the old cookie file.
    else
        echo "${COOKIE_FILE}"
        # shell helper var when sourcing parsenv.sh for one-liners
        ECS_TOKEN=$(cat ${COOKIE_FILE})
        export ECS_TOKEN
        return 0
    fi

}

wait_for_cookie() {
    local index=${1:-"$RACKINDEX"}
    local seconds=0
    seconds=$(date +%s)
    local result=""

    while [ -z "$result" ] && ! (( ( $(date +%s) - seconds ) >= cookie_timeout )); do
        result=$(cat $(ecs-cookiefile $index))
        api_waitloop_sleep
    done

    if [ -z "$result" ]; then
        log "ERROR: ECS: STORAGEPOOL: pod: ${PODNUM}: node: ${rack_master[$index]}: waited $cookie_timeout seconds for API to start and give me cookies"
        log "FATAL: ECS: STORAGEPOOL: pod: ${PODNUM}: node: ${rack_master[$index]}: cannot continue without a cookie. Aborting!"
    fi

    if [ -z "$result1" ]; then
        return 1
    else
        log "OK: ECS: pod ${PODNUM}: node: ${rack_master[$index]}: API is serving fresh cookies"
        return 0
    fi
}

# waits for vdc/rack masters to respond to cookie requests
wait_for_cookies() {
    wait_for_cookie $RACKINDEX
    wait_for_cookie $(( $RACKINDEX + 1 ))
}

#
#####

##### EMC support configs
#
# deactivate callhome if behind seven proxies and unable to
# actually call home. Keeps postfix from grinding and ever-
# increasing mailq and FTP from using resources pointlessly.
ecs-support-deactivate-callhome() {
    rest /vdc/callhome/connectemc/config/deactivate || return 1
    # waitloop $function->(true/false) $timeout $iteration_delay $debug $message
    waitloop POST || return 1
    rest
    return 0
}
#
#####

##### licensing
#
# add license file to currently selected rack
# TODO: retry loop this
ecs-add-license() {
    local out=''
    ecs system add-license -licensetextfile "${ecs_license_file}" 2>&1 | log_to_file
    if [[ "$(ecs system get-license)" =~ ^.*${ecs_license_match}.*$ ]]; then
        >&2 echo "OK: ECS: LICENSE: pod ${PODNUM}: rack ${RACK} licensing success"
        return 0
    else
        >&2 echo "ERROR: ECS: LICENSE: pod ${PODNUM}: rack ${RACK} licensing failure"
        return 1
    fi
}
#
#####

##### storagepool / varray configuration
#
# get a storagepool's URN
ecs-get-sp-urn() {
    local index=${1}
    local urn=''
    rest /vdc/data-services/varrays $index
    GET | jq -r -M '.varray[] | .id' | vc
}

# create a storagepool
ecs-create-sp() {
    local varray_name="$ce_vaname"
    local urn=''
    local hns=( ${host_names[RACKINDEX]} )
    local ips=( ${ip_range[RACKINDEX]} )
    # create the varray
    ecs varray create -name "$varray_name" -isProtected false
    api_sleep
    # get the varray urn
    urn="$(ecs-get-sp-urn ${RACKINDEX})"
    api_sleep
    # create the datastore by associating commodity nodes to a varray
    for ((i=0;i<=(( ${#hns[@]} - 1 ));++i)); do
        ecs datastore create -varray ${urn} \
            -name "${hns[i]}"."${domain_name}" -dsid "${ips[i]}" | jq -C .
        api_sleep
    done
}

# get a json blob of storagepools from the web UI
# bug: the ECS API does not provide information on a
# storagepool's member datastores' provisioning state,
# so we have to go to the web UI to get it. Thankfully
# the same authcookie works there as well.
ecs-get-sp-json() {
    local index=$1
    rest /storagepools $index 443
    GET
}

# waits for all datastore members of a storagepool to report "readytouse"
wait_for_sp() {
    local seconds=0
    seconds=$(date +%s)
    local result=0
    local json=

    while (( $result < $sp_size )) && ! (( ( $(date +%s) - seconds ) >= sp_timeout )); do
        json="$(ecs-get-sp-json $RACKINDEX)"
        result=$( (jq '.data[].nodes[] | .devstate' <<< "$json") | wc -l)
        (( $result < $sp_size )) && log "ECS: STORAGEPOOL: pod $PODNUM: rack ${RACK}: waiting for nodes to join pool ( $result / $sp_size )"
        # $DEBUG && echo "$json" | pypp | log
        api_waitloop_sleep
    done

    if (( $result < $sp_size )); then

        log "FATAL: ECS: STORAGEPOOL: pod: ${PODNUM}: rack ${RACK}: waited $sp_timeout seconds for $sp_size nodes to join the storagepool "
        log "FATAL: ECS: STORAGEPOOL: pod: ${PODNUM}: rack ${RACK}: cannot continue without a storage pool. aborting."
        exit 1
    else
        log "OK: ECS: STORAGEPOOL: pod: ${PODNUM}: rack ${RACK}: $result of $sp_size nodes joined; storagepool is UP"
        return 0
    fi
}
#
#####

##### Virtual Data Center configuration
#

# get vdc secret key for a given rack number
ecs-get-vdc-key() {
    local index=$1
    local key=''
    rest /object/vdcs/vdc/local/secretkey ${index}
    GET | jq .key | vc || return 1
    return 0
}

##### wait for VDC visibility
# give it a node IP and it will return 0 if ready
# or 1 if not which should always be zero before
# proceeding.

# get visible vdcs, return 0 if both are visible, 1 if not.
ecs_vdc_visible() {
    local visible=1
    rest /object/vdcs/vdc/list || return 1
    # TODO: rewrite this to use jq instead of jkid please
    visible="$(GET / | jkid -c -q vdc . name)" || return 1
    if (( ${visible} < ${vdc_count} )); then
        return 1
    else
        return 0
    fi
}

# waitloop for vdc visibility
ecs_vdc_visible_waitloop() {
    local seconds=0
    seconds=$(date +%s)
    log "ECS: VDC: pod ${PODNUM}: rack 1: waiting for VDCs to become accessible in the API"
    while ! ecs_vdc_visible && ! (( ( $(date +%s) - seconds ) >= vdc_ready_timeout )); do
        log "ECS: VDC: pod ${PODNUM}: rack 1: node: ${node}: waiting for VDCs to become accessible in the API"
        api_waitloop_sleep
    done
}

# TODO: travis pls. refactor this.
wait_for_vdc_visible() {
    ecs_vdc_visible_waitloop
}

# create a single VDC
ecs-create-vdc() {
    local name=${1}
    local key=${2}
    local endpoints=${3}
    local count=0
    local maxcount=0
    maxcount=$(( $vdc_insert_timeout / ( $ecsapi_hold_time * 3 ) ))
    wait_for_dt_ready
    log "OP: ECS: VDC: pod ${PODNUM}: rack 1: creating VDC $name with $endpoints"
    while ! ecs_vdc_exists $name; do
        rest /object/vdcs/vdc/"$name"
        list_to_obj interVdcEndPoints ${endpoints}%\
                    secretKeys ${key}%\
                    vdcName ${name}%\
                    | PUT | jq -C .
        ((++count))
        ((count >= $maxcount)) && die "FATAL: ECS: VDC: pod ${PODNUM}: couldn't create VDC ${name}!"
        api_waitloop_sleep
        $DEBUG && log "ECS: VDC: pod ${PODNUM}: rack 1: creating VDC $name ( try $count / $maxcount )"
    done
    # this functions as a directory table queue debouncer
    # so that even if it hits zero once while provisioning
    # the VDC, we won't continue on if it spikes again immediately
    # after.  It happens plenty often that it causes problems.
    # It is a good idea to consider the dtq before starting and
    # after finishing a critical provisioning operation.
    wait_for_dt_ready
    wait_for_dt_ready
    wait_for_dt_ready
    log "OK: ECS: VDC: pod ${PODNUM}: rack 1: created VDC $name with $endpoints"
    return 0
}

# check to see if a VDC exists
ecs_vdc_exists() {
    local vdcname=$1
    local vdclist=''
    rest /object/vdcs/vdc/list
    vdclist=$(GET | jq '.vdc[] | .vdcName') 2>/dev/null
    if ! [ -z "$vdclist" ]; then
        if [[ "$vdclist" =~ "$vdcname" ]]; then
            return 0
        else
            return 1
        fi
    else
        return 1
    fi
}

# create single node vdc
ecs-create-vdcs-single() {
    # Set up the VDC names
    local primary_vdc_name="$ce_vdcname"

    # Make comma-delimited list of rack 1's storagepool IPs
    local primary_ips=
    primary_ips="$(echo ${ip_range[$RACKINDEX]} | sed s/\ /,/g)"

    # Get VDC key for rack 1
    local primary_vdc_key=
    primary_vdc_key=$(echo $(waitloop "ecs-get-vdc-key ${RACKINDEX}" || die_fatal_error))
    primary_vdc_key=${primary_vdc_key%%\\}

    if ! ecs_vdc_exists $primary_vdc_name; then
        ecs-create-vdc $primary_vdc_name $primary_vdc_key $primary_ips
    fi

    wait_for_dt_ready
}
#
#####

##### replication group configuration
#

# create a single replication group in a single VDC rack
ecs-create-rgs-single() {
    local urn_sp1=

    urn_sp1="$( ecs-get-sp-urn $RACKINDEX )" || die_fatal_error

    ecs objectvpool create -name "$ce_rgname" \
        -description only_vdc1 -allowallnamespaces true \
        -zonemapping "${urn_sp1}^$ce_vdcname"  || die_fatal_error
        api_sleep
    wait_for_dt_ready
}

# disgusting bash hacks
# TODO: refactor ecs-get-rg-urn to use resty instead of this nonsense
bash_xml() {
    local IFS=\>
    read -d \< key value
}

ecs-get-rg-urn() {
    local name=${1}
    local tmp_id=
    ecs objectvpool list -f xml | while bash_xml; do
        if [[ "$key" == "name" ]] && [[ "$value" == "$name" ]]; then
            echo "$tmp_id"
            break
        elif [[ "$key" == "id" ]]; then
            tmp_id="${value}"
        fi
    done
}
#
#####

##### namespace configuration
#
# create namespace on default replication group
# TODO: put this in a waitloop
ecs-create-namespaces-single() {
    local admin="$ce_username"
    ecs namespace create -namespace "ns-ecs1" -admin "$admin" \
        -objectvpool "$(ecs-get-rg-urn ${PODNAME}-ecs1-rg)"  || die_fatal_error
    api_sleep
    wait_for_dt_ready
}

# create object users with s3 and swift passwords
ecs-create-object-users() {
    for tag in $ce_rgname; do
        # create user
        ecs objectuser create -uid "ns-${tag}-user" \
            -namespace "ns-${tag}" | jq -C . || die_fatal_error
        # generate s3 keypair
        api_sleep
        ecs secretkeyuser user-add -uid "ns-${tag}-user" | jq -C . || die_fatal_error
        # create swift password
        api_sleep
        ecs passwordgroup create -uid "ns-${tag}-user" -ns "ns-${tag}" \
            -pw "Password123" -groups_list "admin" | jq -C . || die_fatal_error
        api_sleep
        wait_for_dt_ready
    done
}

ecs-create-object-users-single() {
    for tag in ecs1; do
        # create user
        ecs objectuser create -uid "ns-${tag}-user" \
            -namespace "ns-${tag}" | jq -C . || die_fatal_error
        # generate s3 keypair
        api_sleep
        ecs secretkeyuser user-add -uid "ns-${tag}-user" | jq -C . || die_fatal_error
        # create swift password
        api_sleep
        ecs passwordgroup create -uid "ns-${tag}-user" -ns "ns-${tag}" \
            -pw "Password123" -groups_list "admin" | jq -C . || die_fatal_error
        api_sleep
        wait_for_dt_ready
    done
}

# create default buckets
#   - bucket1 -> ns-geo-user
#   - bucket1 -> ns-ecs1-user
#   - bucket1 -> ns-ecs2-user
ecs-create-buckets() {
    ecs bucket create -n "s3_bucket1" -vp "$(ecs-get-rg-urn ${PODNAME}-ecs-geo-rg)" \
        -stale true -ns "ns-geo" -fs false -ht "s3" || die_fatal_error
    api_sleep
    wait_for_dt_ready
    ecs bucket create -n "s3_bucket1" -vp "$(ecs-get-rg-urn ${PODNAME}-ecs1-rg)" \
        -stale true -ns "ns-ecs1" -fs false -ht "s3" || die_fatal_error
    api_sleep
    wait_for_dt_ready
    ecs-cmd $(( $RACKINDEX + 1 )) bucket create -n "s3_bucket1" -vp "$(ecs-get-rg-urn ${PODNAME}-ecs2-rg)" \
        -stale true -ns "ns-ecs2" -fs false -ht "s3" || die_fatal_error
    api_sleep
    wait_for_dt_ready
}

ecs-create-buckets-single() {
    wait_for_dt_ready
    ecs bucket create -n "s3_bucket1" -vp "$(ecs-get-rg-urn ${PODNAME}-ecs1-rg)" \
        -stale true -ns "ns-ecs1" -fs false -ht "s3" || die_fatal_error
    api_sleep
}

###########################
