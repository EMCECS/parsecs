#!/usr/bin/env bash

# Copyright (c) 2012-15 EMC Corporation
# All Rights Reserved
#
# This software contains the intellectual property of EMC Corporation
# or is licensed to EMC Corporation from third parties.  Use of this
# software and the intellectual property contained therein is expressly
# limited to the terms and conditions of the License Agreement under which
# it is provided by or on behalf of EMC.


# Conditionally include the shell library so we don't waste cycles
# when doing scripted ops
$shell_source && source $script_home/lib/parsecs.lib.shell.sh

# Include the REST library
source $script_home/lib/parsecs.lib.rest.sh

# Include the common library
source $script_home/lib/parsecs.lib.common.sh

# Include the ECS Community Edition library
source $script_home/lib/parsecs.lib.ecsce.sh

# Include the output library
source $script_home/lib/parsecs.lib.o.sh

# Include and configure resty
# load resty to defaults if we're not on a meta-object
if (( $PODNUM != 0 )) && (( $RACK != 0 )) && (( $RACKINDEX != 0 )); then
    rest
fi

