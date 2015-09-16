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

##### boilerplate
#
# boostrap parsecs
params=${@: -1}

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
source "$script_bin/parsenv.sh" -p 1 -r 1 -v -c -f $@ || exit 1
#
#####

##### single.sh - single node install support
#
step1() {
    #echo python step1_ecs_singlenode_install.py --ethadapter ${ce_netdev} --hostname ${ce_hostname} --disks ${ce_disks}
    unbuffer python step1_ecs_singlenode_install.py --ethadapter ${ce_netdev} --hostname ${ce_hostname} --disks ${ce_disks}
}

step2() {
    primary_ips="$(echo ${ip_range[$RACKINDEX]} | sed s/\ /,/g)"
    #echo python step2_object_provisioning.py --ECSNodes=${primary_ips} --Namespace=${ce_nsname} --ObjectVArray=${ce_vaname} --ObjectVPool=${ce_vpname} --UserName=${ce_username} --DataStoreName=${ce_dsname} --VDCName=${ce_vdcname} --MethodName=${1}
    unbuffer python step2_object_provisioning.py --ECSNodes=${primary_ips} --Namespace=${ce_nsname} --ObjectVArray=${ce_vaname} --ObjectVPool=${ce_vpname} --UserName=${ce_username} --DataStoreName=${ce_dsname} --VDCName=${ce_vdcname} --MethodName=${1}
}

do_normal_run() {
    cd ecs-single-node

    log_run step1
    wait_for_dt_ready
    general_sleep
    wait_for_dt_ready

    log_run step2
}

do_run() {
    cd ecs-single-node

    log_run step1
    wait_for_dt_ready
    wait_for_dt_ready
    log_run wait_for_cookies
    api_sleep
    wait_for_dt_ready

    # organize steps into groups and execute each group with extra checking
    # in between groups.
    provstep[1]="UploadLicense CreateObjectVarray CreateDataStore"
    provstep[2]="InsertVDC"
    provstep[3]="CreateObjectVpool"
    provstep[4]="CreateNamespace CreateUser CreateSecretKey"

    for ((i=1;((i < ${#provstep[@]}));++i)); do
        wait_for_dt_ready
        for step in ${provstep[i]}; do
            log "OP: step2: $step"
            if [[ "$step" =~ "CreateUser" ]]; then # because CreateUser currently throws an exception always
                log_run "step2 $step" || log "[BUG!] Ignoring CreateUser exception"
            else
                log_run "step2 $step" $general_timeout $general_holdtime true
            fi
            api_sleep
            wait_for_dt_ready
        done
        wait_for_dt_ready
        wait_for_dt_ready
        general_sleep
    done
}

do_git_config() {
    cd ~
    git config --global --add remote.origin.fetch "+refs/pull/*/head:refs/remotes/origin/pr/*"
    git config --global user.email "padthaitofuhot@users.noreply.github.com"
    git config --global user.name "padthaitofuhot"
}

do_git_pull_emcecs() {
    cd emcecs
    git checkout master
    git pull
    cd -
}

do_deploy_emcecs() {
    cd emcecs
    do_normal_run
}

do_step1_emcecs() {
    cd emcecs/ecs-single-node
    step1
}

do_deploy_tofu() {
    cd padthaitofuhot
    do_normal_run
}

do_step1_tofu() {
    cd padthaitofuhot/ecs-single-node
    step1
}

do_git_pull_tofu() {
    cd padthaitofuhot
    git checkout master
    git pull
    cd -
}

do_deploy_pr() {
    cd emcecs
    git checkout pr/${1}
    do_deploy_emcecs
}

abort() {
    echo "You didn't specify all the options. If doing single.sh run-pr, specify just the pr # as second argument"
    exit 1
}

case ${OP} in
    update)
        do_git_config
        do_git_pull_emcecs
    ;;
    update-tofu)
        do_git_config
        do_git_pull_tofu
    ;;
    deploy)
        $0 -o update
        do_deploy_emcecs
    ;;
    step1)
        $0 -o update
        do_step1_emcecs
    ;;
    step1-tofu)
        $0 -o update-tofu
        do_step1_tofu
    ;;
    deploy-tofu)
        $0 -o update-tofu
        do_deploy_tofu
    ;;
    run-pr)
        if [ -z "${params[0]}" ]; then
            abort
        else
            $0 -o update
            do_deploy_pr ${params[0]}
        fi
    ;;
    *)
        echo "params 1:${OP} 2:${params[0]}"
        abort
    ;;
esac
