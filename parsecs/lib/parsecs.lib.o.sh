#!/usr/bin/env bash
shopt -s extglob
shopt -s xpg_echo

# Copyright (c) 2012-15 EMC Corporation
# All Rights Reserved
#
# This software contains the intellectual property of EMC Corporation
# or is licensed to EMC Corporation from third parties.  Use of this
# software and the intellectual property contained therein is expressly
# limited to the terms and conditions of the License Agreement under which
# it is provided by or on behalf of EMC.


######################################
# parsecs output and logging library #
######################################

# TODO: refactor logging to use context tokens rather than writing logging context by hand.

_hostname="$(hostname)"
_logfile="$LOGFILE"

# runs a command and wires stdout and stderr into the generic logger
log_run() {
    command="$*"
    $DEBUG && log "DEBUG: ${command}"
    $command 2>&1 | log
}

# generic logger that can take input on stdin or as arguments
# wires console output into the generic output filter
log() {
    if [ -z "$*" ]; then
        while read line; do
            printf "%(%Y-%m-%d %H:%M:%S%z)T %s %s\n" -1 "$_hostname" "$line" | o
            printf "%(%Y-%m-%d %H:%M:%S%z)T %s %s\n" -1 "$_hostname" "$line" >> ${_logfile}
        done
    else
        printf "%(%Y-%m-%d %H:%M:%S%z)T %s %s\n" -1 "$_hostname" "$*" | o
        printf "%(%Y-%m-%d %H:%M:%S%z)T %s %s\n" -1 "$_hostname" "$*" >> ${_logfile}
    fi
}

# log only to file, for extra spammy debugging output
log_to_file() {
    if [ -z "${*}" ]; then
        while read -r line; do
            printf "%(%Y-%m-%d %H:%M:%S%z)T %s %s\n" -1 "$_hostname" "$line" >> "${_logfile}"
        done
    else
        printf "%(%Y-%m-%d %H:%M:%S%z)T %s %s\n" -1 "$_hostname" "${*}" >> "${_logfile}"
    fi
}

# smartish log roller
log_roll() {
    local mtime=
    local log="$1"

    # if our target xz file already exists, rename it: tag with its own mtime
    if [ -f "${log}.xz" ]; then
        mv "${log}.xz" "${log}.xz.$(date +%Y%m%d-%H%M%S -r ${log}.xz)"
    fi

    # if a logfile exists, get its mtime and xz compress it.
    if [ -f "${log}" ]; then
        mtime=$(date +%Y%m%d-%H%M%S -r ${log})
        xz ${log}
    fi

    # if we got an untagged xz-compressed logfile, tag it with mtime of raw log
    if [ -f "${log}.xz" ]; then
        mv "${log}.xz" "${log}.xz.${mtime}"
    fi
}

# writes directly to stderr
# can be used in functions that use echo or
# printf send output to other functions
debug() {
    if $DEBUG; then
        >&2 echo "DEBUG: ${*}"
    fi
}

# dies with message, respecting softexit (can be dangerous when shelling)
die() {
    log "${*}"
    quit 1
}

# generic death, respecting softexit (can be dangerous when shelling),
# for when a specific death cannot or will not be determined.
# TODO: always go back and change uses of this to something more specific. don't be lazy.
die_fatal_error() {
    die "FATAL: pod ${PODNUM}: rack ${RACK}: some operation failed, check logs and apply manual intervention."
    quit 1
}

# generic output filter wrapper
# filters everything on stdin or arguments through the
# output filter.
o() {
    local output=''
    if [ -z "${@}" ]; then
        while read -r line; do
            output_filter "${line}"
        done
    else
        output_filter "${@}"
    fi
}

# evaluate string as tokens and colorize accordingly.
# It's surprisingly fast.  For bash.
output_filter() {
    if $COLORIZE; then
        shopt -s nocasematch
        for part in $@; do
            case ${part%[-:]} in
                FATAL)
                    output+="${BRed}${On_Red}${part}${Color_Off} "
                ;;
                ERROR|FAIL)
                    output+="${BYellow}${On_Red}${part}${Color_Off} "
                ;;
                WARNING)
                    output+="${BWhite}${On_Red}${part}${Color_Off} "
                ;;
                NOTICE)
                    output+="${BWhite}${On_Blue}${part}${Color_Off} "
                ;;
                DOWN|BAD|failed|*pending*)
                    output+="${BRed}${part}${Color_Off} "
                ;;
                INFO|PARSENV|NOTE|Required|[0-9]|[0-9][0-9]|[0-9][0-9][0-9]|[0-9][0-9][0-9][0-9]|[0-9][0-9][0-9][0-9][0-9]|[0-9][0-9][0-9][0-9][0-9][0-9]) #integers cardinalities 1-6
                    output+="${BYellow}${part}${Color_Off} "
                ;;
                OK|COMPLETED|optional|UP|*GOOD*|*PASS*|*readytouse*)
                    output+="${BGreen}${part}${Color_Off} "
                ;;
                DEBUG|PID|unmounting|time=|\#\#*|\.\.\.\.*)
                    output+="${BBlack}${part} " # no reset to grab the line as same color unless other tokens change it
                ;;
                \|) # A single pipe
                    output+="${BBlack}${part}${Color_Off} "
                ;;
                OP|CONFIG|EXIT|usage|example|*clean*|*generate*|*emit*|update*|create*|sign*|*make*|*remove*|*INSTALL|*CONFIGURE*|*push*|*pull*|join*|*load*|tag*|put*|get*|delete*|post*)
                    output+="${BWhite}${part}${Color_Off} "
                ;;
                FABRIC|DISK|FILE|DOCKER|dockerhealth|*CLUSTER*|doit|viprscp|viprexec)
                    output+="${BBlue}${part}${Color_Off} "
                ;;
                ECS|LICENSE|VDC|STORAGEPOOL|REPLGROUP|DOMAIN|AUTH|API|NAMESPACE|BUCKET|*VALIDATE*|*VERIFY*|*CHECK*|*validators)
                    output+="${BPurple}${part}${Color_Off} "
                ;;
                [0-9][0-9][0-9][0-9]-[0-1][0-9]-[0-3][0-9]) # datestamp
                    output+="${Cyan}${part}${Color_Off} "
                ;;
                                         # leap seconds :)
                [0-2][0-9]:[0-5][0-9]:[0-6][0-9]-[0-1][0-9][0-5]0|[0-2][0-9]:[0-5][0-9]:[0-6][0-9]+[0-1][0-9][0-5]0) # timestamp
                    output+="${Cyan}${part}${Color_Off} "
                ;;
                *[0-9]*.[0-9]*.[0-9]*.[0-9]*) # IP address[/CIDR]
                    output+="${BPurple}${part}${Color_Off} "
                ;;
                *=*) # tuple marker
                    output+="${Green}${part}${Color_Off} "
                ;;
                PXE|BMC|RMM|IPMI|DHCP|ipmiutil|BASEOS|rack|pod|node|master|[0-9]*K|[0-9]*%)
                    output+="${Yellow}${part}${Color_Off} "
                ;;
                "$color_hostname") # hostname of generator
                    output+="${BCyan}${part}${Color_Off} "
                ;;
                !!!) # triple-bang warning flag for interactive shells
                    output+="${BYellow}${On_Purple}${part} "
                ;;
                parsecs)
                    output+="${BWhite}P${BCyan}a${Cyan}r${BBlue}s${BWhite}ECS${Color_Off} "
                ;;
                ecs)
                    output+="${BWhite}E${BCyan}C${Cyan}S${Color_Off} "
                ;;
                DNS|ping|ntp|ntpd|setrackinfo|getrackinfo|network|IP|netmask|route|dnsserver|dnssearch|meta-pod|meta-rack)
                    output+="${BRed}${part}${Color_Off} "
                ;;
               [\"]red[\"])
                    output+="${BWhite}${On_Red}[${part}]${Color_Off} "
                ;;
                [\"]green[\"])
                    output+="${BWhite}${On_Green}[${part}]${Color_Off} "
                ;;
                *)
                    output+="${White}${part} "
                ;;
            esac
        done
        >&2 builtin echo "${output}"
        shopt -u nocasematch
    else
        >&2 builtin echo "${@}"
    fi
}

# DANGEROUS! Strips color escape sequences out of all files in the
# $script_logs directory. Not the best idea when there are .xz files
# present as they will usually contain strings that look like escapes
# but are actually compressed data. Don't use this unless you also
# don't use the log roller.
dangerous_strip_logs() {
    find "$script_logs" -type f \
    | xargs sed -i -r "s/\x1B\[([0-9]{1,2}(;[0-9]{1,2})?)?[m|K]//g"
}

# Strips color escape sequences from output, useful when using with | tee
# pipes in aggregate operation scripts that trigger actions on several
# hosts simultaneously over ssh.
strip_color() {
    while read -r line; do
        builtin echo "$line" | sed -r "s/\x1B\[([0-9]{1,2}(;[0-9]{1,2})?)?[m|K]//g"
    done
}

# builds a solid line using unicode line-drawing characters
# the width of the terminal ($COLUMNS). Takes a color string
# as an argument.
prompt_line() {
    local color=${1:-"$BBlack"}
    local i=0
    local s=""
    while (( $i < ${COLUMNS:-80} )); do
        s+="q"
        ((++i))
    done
    builtin echo -n "${color}\E(0$s\E(B${Color_Off}"
}

### some colors and characters by name

# Reset
Color_Off='\e[0m'       # Text Reset

# Fancy chars
FancyX='\342\234\227'    # Unicode Fancy X
Checkmark='\342\234\223' # Unicode Fancy Checkmark

# Regular Colors
Black='\e[0;30m'        # Black
Red='\e[0;31m'          # Red
Green='\e[0;32m'        # Green
Yellow='\e[0;33m'       # Yellow
Blue='\e[0;34m'         # Blue
Purple='\e[0;35m'       # Purple
Cyan='\e[0;36m'         # Cyan
White='\e[0;37m'        # White

# Bold
BBlack='\e[1;30m'       # Black
BRed='\e[1;31m'         # Red
BGreen='\e[1;32m'       # Green
BYellow='\e[1;33m'      # Yellow
BBlue='\e[1;34m'        # Blue
BPurple='\e[1;35m'      # Purple
BCyan='\e[1;36m'        # Cyan
BWhite='\e[1;37m'       # White

# Underline
UBlack='\e[4;30m'       # Black
URed='\e[4;31m'         # Red
UGreen='\e[4;32m'       # Green
UYellow='\e[4;33m'      # Yellow
UBlue='\e[4;34m'        # Blue
UPurple='\e[4;35m'      # Purple
UCyan='\e[4;36m'        # Cyan
UWhite='\e[4;37m'       # White

# Background
On_Black='\e[40m'       # Black
On_Red='\e[41m'         # Red
On_Green='\e[42m'       # Green
On_Yellow='\e[43m'      # Yellow
On_Blue='\e[44m'        # Blue
On_Purple='\e[45m'      # Purple
On_Cyan='\e[46m'        # Cyan
On_White='\e[47m'       # White
