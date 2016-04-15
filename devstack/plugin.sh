#!/bin/bash

# devstack/plugin.sh
# Triggers glusterfs specific functions to install and configure GlusterFS

# Dependencies:
#
# - ``functions`` file
# - ``DATA_DIR`` must be defined

# ``stack.sh`` calls the entry points in this order:
#
# - install_glusterfs
# - start_glusterfs
# - configure_cinder_backend_glusterfs
# - configure_cinder_backup_backend_glusterfs
# - configure_glance_backend_glusterfs
# - configure_nova_backend_glusterfs
# - configure_manila_backend_glusterfs
# - stop_glusterfs
# - cleanup_glusterfs

# configure_cinder_backend_vzstorage - Set config files, create data dirs, etc
function configure_cinder_backend_vzstorage {
    local be_name=$1
    iniset $CINDER_CONF $be_name volume_backend_name $be_name
    iniset $CINDER_CONF $be_name volume_driver "cinder.volume.drivers.vzstorage.VZStorageDriver"
    iniset $CINDER_CONF $be_name vzstorage_shares_config "$CINDER_CONF_DIR/vzstorage-shares-$be_name.conf"

    CINDER_VZSTORAGE_CLUSTERS="$CINDER_VZSTORAGE_CLUSTER_NAME [\"-u\", \"stack\", \"-g\", \"qemu\", \"-m\", \"0770\"]"
    echo "$CINDER_VZSTORAGE_CLUSTERS" | tee "$CINDER_CONF_DIR/vzstorage-shares-$be_name.conf"
}
# init_cinder_backend_vzstorage - Initialize minimalistic vzstorage cluster
# init_cinder_backend_vzstorage $be_name
function init_cinder_backend_vzstorage {
    local be_name=$1

    set -e
    CLUSTER_NAME=$CINDER_VZSTORAGE_CLUSTER_NAME
    PSTORAGE_PKGS="pstorage-chunk-server pstorage-client pstorage-ctl \
                   pstorage-libs-shared pstorage-metadata-server"
    if [[ "$os_VENDOR" == "CentOS" ]]; then
        sudo rpm -i http://download.pstorage.parallels.com/standalone/packages/rhel/7/pstorage-release.noarch.rpm
        PSTORAGE_PKGS=$PSTORAGE_PKGS pstorage-kmod
    elif [[ "$os_VENDOR" == "Virtuozzo" ]]; then
        echo "Running on Virtuozzo distribution, it requires no other kernel modules"
        # Hack to restart vcmmd after numpy updated
        sudo systemctl restart vcmmd.service
    else
        die $LINENO "Vzstorage is supported on CentOS and Virtuozzo distributions only"
    fi

    sudo yum install -y $PSTORAGE_PKGS
    [ -d /pstorage ] || sudo mkdir /pstorage

    echo PASSWORD | sudo pstorage -c $CLUSTER_NAME make-mds -I -a 127.0.0.1 -r /pstorage/$CLUSTER_NAME-mds -P
    sudo service pstorage-mdsd start
    sudo chkconfig pstorage-mdsd on

    sudo pstorage -c $CLUSTER_NAME make-cs -r /pstorage/$CLUSTER_NAME-cs
    sudo service pstorage-csd start
    sudo chkconfig pstorage-csd on

    echo 127.0.0.1 | sudo tee /etc/pstorage/clusters/$CLUSTER_NAME/bs.list

    set +e
}


if [[ "$1" == "stack" && "$2" == "pre-install" ]]; then
    echo_summary "Installing GlusterFS 3.7"
    install_glusterfs 3.7
elif [[ "$1" == "stack" && "$2" == "post-config" ]]; then
    if is_service_enabled glance && [[ "$CONFIGURE_GLUSTERFS_GLANCE" == "True" ]]; then
        echo_summary "Configuring GlusterFS as a backend for Glance"
        configure_glance_backend_glusterfs
    fi
    if is_service_enabled nova && [[ "$CONFIGURE_GLUSTERFS_NOVA" == "True" ]]; then
        echo_summary "Configuring GlusterFS as a backend for Nova"
        configure_nova_backend_glusterfs
    fi
    if is_service_enabled manila && [[ "$CONFIGURE_GLUSTERFS_MANILA" == "True" ]]; then
        echo_summary "Configuring GlusterFS as a backend for Manila"
        configure_manila_backend_glusterfs
    fi
elif [[ "$1" == "stack" && "$2" == "extra" ]]; then
    # Changing file permissions of glusterfs logs.
    # This avoids creation of zero sized glusterfs log files while running CI job (Bug: 1455951).
    sudo chmod 755 -R /var/log/glusterfs/
fi

if [[ "$1" == "unstack" ]]; then
    cleanup_glusterfs
    stop_glusterfs
fi

if [[ "$1" == "clean" ]]; then
    cleanup_glusterfs
fi

## Local variables:
## mode: shell-script
## End:
