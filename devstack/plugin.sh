#!/bin/bash

# devstack/plugin.sh
# Devstack plugin to install and configure Vzstorage

# Dependencies:
#
# - ``functions`` file
# - ``DATA_DIR`` must be defined

# ``stack.sh`` calls the entry points in this order:
#
# - install_vzstorage
# - start_vzstorage
# - configure_cinder_backend_vzstorage
# - configure_glance_backend_vzstorage
# - configure_nova_backend_vzstorage
# - stop_vzstorage
# - cleanup_vzstorage
VZSTORAGE_PLUGIN_DIR=$(readlink -f $(dirname ${BASH_SOURCE[0]}))
source $VZSTORAGE_PLUGIN_DIR/vzstorage-functions.sh

if [[ "$1" == "stack" && "$2" == "pre-install" ]]; then
    echo_summary "Installing Vzstorage"
    install_vzstorage
elif [[ "$1" == "stack" && "$2" == "post-config" ]]; then
    if is_service_enabled cinder && \
        [[ "$CONFIGURE_VZSTORAGE_CINDER" == "True" ]]; then
        echo_summary "Configuring Vzstorage as a backend for Nova"
        configure_cinder_backend_vzstorage
    fi
fi

if [[ "$1" == "unstack" ]]; then
    cleanup_vzstorage
fi

if [[ "$1" == "clean" ]]; then
    cleanup_vzstorage
fi

## Local variables:
## mode: shell-script
## End:
