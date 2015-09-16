#!/usr/bin/env bash
invoked=$_
OPTIND=1
shopt -s xpg_echo
shopt -s extglob

# Copyright (c) 2012-15 EMC Corporation
# All Rights Reserved
#
# This software contains the intellectual property of EMC Corporation
# or is licensed to EMC Corporation from third parties.  Use of this
# software and the intellectual property contained therein is expressly
# limited to the terms and conditions of the License Agreement under which
# it is provided by or on behalf of EMC.

hard_exits=true
local_only=false
shell_source=false

quit() {
    if $hard_exits; then
        exit $1
    else
        return $1
    fi
}

if [[ "$0" == "-bash" ]]; then
    hard_exits=false
    shell_source=true
fi

if $shell_source; then
    lfn="$script_logs/parsecs-shell.log"
else
    lfn="$(basename $0)"
    lfn="$script_logs/${bn0%.sh}.log"
fi

# flow-through defaults
LOGFILE=${LOGFILE:-"${lfn}"}
PODNUM=${PODNUM:-''}
RACK=${RACK:-''}
DEBUG=${DEBUG:-false}
PODNAME=${PODNAME:-''}
RACKINDEX=${RACKINDEX:-0}
PARSENV=${PARSENV:-false}
COLORIZE=${COLORIZE:-false}
OP=${OP:-''}

argc=0
while getopts "p:r:o:dvfltbc" opt; do
    case "$opt" in
        p)
            PODNUM="${OPTARG}"
            PODNAME="pod${PODNUM}"
            ((argc+=2))
        ;;
        r)
            RACK="${OPTARG}"
            # TODO: RACKINDEX is based on number of rack per-pod, so use a var here not static int
            case ${PODNUM} in
                0)
                    RACKINDEX=0
                ;;
                1)
                    RACKINDEX=$((0+RACK))
                ;;
                2)
                    RACKINDEX=$((2+RACK))
                ;;
                *)
                    quit 1
                ;;
                # Add more as necessary until I come up with a better way.
            esac
            ((argc+=2))
        ;;
        [dv])
            DEBUG=true
            ((argc+=1))
        ;;
        t)
            DEBUG=false
            ((argc+=1))
        ;;
        f)
            PARSENV=false
            ((argc+=1))
        ;;
        s|l)
            PARSENV=false
            local_only=true
            shell_source=false
            hard_exits=true
            ((argc+=1))
        ;;
        c)
            COLORIZE=true
            ((argc+=1))
        ;;
        b)
            COLORIZE=false
            ((argc+=1))
        ;;
        o)
            OP=${OPTARG}
            ((argc+=1))
        ;;
    esac
done

# future use
shift $argc
set --

if [[ "$invoked" == "$0" ]]; then
    echo "PARSENV: Useless if invoked directly"
    quit 1
fi

if $PARSENV; then
    o "PARSENV: environment already loaded, use -f to reload"
else

    if [ -z "${PODNUM}" ] || [ -z "${RACK}" ]; then
        echo "\nScript: ${0}"
        echo "Parsecs environment loader error"
        echo "\nInvalid argument combination: $*"
        echo "\nUsage:"
        echo "\nRequired:\n"
        echo "-p <#>\tpod number"
        echo "-r <#>\track number"
        echo "\nOptional:\n"
        echo "-v,-d\tenable verbose"
        echo "-f\tforce environment update"
        echo "-s\tscript config [no export(1) implies -f)]"
        echo "-c\tcolorize output (for weary eyes)"
        echo "\nExample:\n"
        echo "Reset ECS pod 1 rack 2 in verbose mode"
        echo "# ecs-reset-rack.sh -p 1 -r 2 -v"
        echo "\nEnable ECS bash macros in shell and"
        echo "force a reload of the parsecs environment"
        echo "for working on pod 6 rack 2"
        echo "# source libexec/parsenv.sh -p 6 -r 2 -f\n"
        quit 1
    else

        # find configs and import from least to most specific
        if [ -f /etc/parsecs.conf ]; then
            source /etc/parsecs.conf
        fi
        if [ -f $HOME/.parsecs.rc ]; then
            source $HOME/.parsecs.rc
        fi
        if [ -z "$script_home" ]; then
            for checkdir in /lib /usr/lib /usr/local/lib $HOME; do
                if [ -d "$checkdir/parsecs" ]; then
                    script_home="$checkdir/parsecs"
                fi
            done
        fi

        # can't find config? tell user to fix it.
        if [ -z "$script_home" ]; then
            echo "PARSENV: Couldn't find parsecs installation."
            echo "PARSENV: Perhaps you need to create a config"
            echo "PARSENV: file to point to it?  It can be in"
            echo "PARSENV: one of these places:"
            echo "PARSENV:     /etc/parsecs.conf"
            echo "PARSENV:     $HOME/.parsecs.rc"
            echo "PARSENV: contents should simply be:"
            echo "PARSENV:     script_home=<path/to/parsecs>"
            echo "PARSENV: Thanks!"
            quit 1
        fi

        # export script_home and create ~/.parsecs.rc if not exists
        if ! [ -z "$script_home" ]; then
            export script_home
            if ! [ -f "$HOME/.parsecs.rc" ]; then
                echo "PARSENV: updating $HOME/.parsecs.rc with parsecs location"
                echo "PARSENV: so I don't have to scan for it every time I start."
                echo "script_home=\"$script_home\"" > "$HOME/.parsecs.rc"
            fi
        fi

        # import everything
        source $script_home/parsecs.conf
        source $script_home/lib/includes.sh

        $shell_source && show_head
        $shell_source && show_warn # warn if pod or rack = 0 (meta-pod/meta-rack)
        $shell_source && $DEBUG && show_vars
    fi

    if ! $local_only; then
        export POD="/dev/null" # deprecated, cause bees if used
        export PODNUM
        export RACK
        export DEBUG
        export PODNAME
        export RACKINDEX
        export PARSENV=true
        export COLORIZE
        export LOGFILE
        export OP
    fi

fi
