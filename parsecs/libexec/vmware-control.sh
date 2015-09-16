#!/usr/bin/bash

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
source "$script_bin/parsenv.sh" -l $@ || exit 1

do_launchpad() {
    powershell="$(which powershell) -NonInteractive"
    transcript="$script_logs/reset-${PODNAME}-launchpad.log"
    hostname="$(hostname)"

    log() {
        if [ -z "$*" ]; then
            while read line; do
                printf "%(%Y-%m-%d %H:%M:%S%z)T %s %s\n" -1 "$hostname" "$line" | o
                printf "%(%Y-%m-%d %H:%M:%S%z)T %s %s\n" -1 "$hostname" "$line" >> ${LOGFILE}
            done
        else
            printf "%(%Y-%m-%d %H:%M:%S%z)T %s %s\n" -1 "$hostname" "$*" | o
            printf "%(%Y-%m-%d %H:%M:%S%z)T %s %s\n" -1 "$hostname" "$*" >> ${LOGFILE}
        fi
    }

    $powershell $(cygpath -w $script_bin/vmware-control.ps1) -logfile $(cygpath -w $transcript) -vm "${vmware_vm}" -snapshot "${vmware_snapshot}" -op "${param}" -user "${vm_user}" -pass "${vm_pass}"

    cat "${transcript}" | log
    rm -f "${transcript}"
}

case $param in
    stop|start)
        do_launchpad || {
            log "FATAL: CONFIG: pod ${PODNUM}: rack ${RACK}: A fatal error was caught. Manual intervention may be necessary."
            exit 1
        }
    ;;
    *)
        : # noop
    ;;
esac
