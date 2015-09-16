#!/usr/bin/env bash
# set -x
# Copyright (c) 2012-15 EMC Corporation
# All Rights Reserved
#
# This software contains the intellectual property of EMC Corporation
# or is licensed to EMC Corporation from third parties.  Use of this
# software and the intellectual property contained therein is expressly
# limited to the terms and conditions of the License Agreement under which
# it is provided by or on behalf of EMC.

echo -e "NOTE: If this spams a lot of errors, run:\n# dos2unix parsecs/libexec/fixattr.sh\n# parsecs/libexec/fixattr.sh"

dostounix() {
    find $HOME/parsecs/libexec -type f ! -name '*.ps1' | xargs dos2unix
    find $HOME/parsecs/libexec | xargs chmod +x
    find $HOME/parsecs/lib -regex '.*.[sh|py]' | xargs dos2unix
    find $HOME/parsecs/lib -regex '.*.[sh|py]' | xargs chmod +x
    find $HOME -maxdepth 1 -name '*.sh' | xargs dos2unix
    find $HOME -maxdepth 1 -name '*.sh' | xargs chmod +x
    find $HOME -name 'docker.conf' | xargs dos2unix
    find /opt/storageos/cli ! -name '*.[pyc|egg]' | xargs dos2unix
    chmod 0700 $HOME/.ssh
    chmod 0600 $HOME/.ssh/authorized_keys
    chmod 0600 $HOME/.ssh/config
    chmod 0600 $HOME/.ssh/id_rsa
    chown root:root $HOME/.ssh/*
}

packages() {
    find $HOME/parsecs/pkg/ -type f -print0 | xargs -0 -n 1 7z e -o/usr/local/bin/ -y
    chmod +x /usr/local/bin/*
}

case "$1" in
    *)
        dostounix
    ;;
esac
