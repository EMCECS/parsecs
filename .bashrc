#!/usr/bin/env bash

# Copyright (c) 2012-15 EMC Corporation
# All Rights Reserved
#
# This software contains the intellectual property of EMC Corporation
# or is licensed to EMC Corporation from third parties.  Use of this
# software and the intellectual property contained therein is expressly
# limited to the terms and conditions of the License Agreement under which
# it is provided by or on behalf of EMC.


# always update the window size on new prompt
shopt -s checkwinsize

# get parsec env bootstrap
source $HOME/.parsecs.rc

# add $HOME and parsecs to PATH
PATH="$HOME:$HOME/bin:$script_home/libexec:$PATH"

# colors are nice
TERM=xterm-256color

# useful aliases
alias pp="$script_bin/pypp"
alias pypp="$script_bin/pypp"

# terminal-width unicode line
prompt_line() {
    local color="$1"
    local i=0
    local s=""
    while (( $i < ${COLUMNS:-80} )); do
        s+="q"
        ((++i))
    done
    builtin echo -ne "${color}\E(0$s\E(B${Color_Off}"
}

# prompt
prompt_command() {
    local last_err=$?

    local date="\[${BBlack}\][\[${Purple}\]\D{%Y}\[${BBlack}\]-\[${Purple}\]\D{%m}\[${BBlack}\]-\[${Purple}\]\D{%d}"
    local time="\[${BPurple}\]\D{%H}\[${BBlack}\]:\[${BPurple}\]\D{%M}\[${BBlack}\]:\[${Purple}\]\D{%S}\[${BBlack}\]]"

    local parsecs_env="\[${Yellow}\]p:\[${BYellow}\]${PODNUM} \[${Yellow}\]r:\[${BYellow}\]${RACK} \[${Yellow}\]i:\[${BYellow}\]${RACKINDEX}"

    if [ -z "$ECS_TOKEN" ]; then
        local resty_env="\[${BBlack}\](\[${Red}\]No API AuthN\[${BBlack}\])"
    else
        local resty_env="\[${BBlack}\](\[${BBlue}\]${_resty_host}\[${BBlack}\])"
    fi

    local cwd="\[${BCyan}\]\w\[${Color_Off}\]"

    local wherewho="\[${BBlack}\][\[${Purple}\]\u\[${BBlack}\]@\[${Purple}\]\h\[${BBlack}\]]\[${Color_Off}\]"

    local ppip="\[\033(0\]b\[\033(B\]\[${Color_Off}\]"

    local err_txt=
    if (( $last_err == 0 )); then
        prompt_line "${BBlack}"
        err_txt="\[${BBlack}\]${last_err} \[$BGreen\]"
    else
        prompt_line "${BRed}"
        err_txt="\[${BWhite}\]${last_err} \[$BRed\]"
    fi

# ps1 def multiline
PS1="${date} ${time} ${parsecs_env} ${resty_env} ${cwd}
${wherewho} ${err_txt}${ppip} "
}

PROMPT_COMMAND='prompt_command'
export TERM PATH PROMPT_COMMAND PS1
