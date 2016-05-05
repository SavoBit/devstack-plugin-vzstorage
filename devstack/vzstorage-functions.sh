#!/bin/bash

# devstack/vzstorage-functions.sh
# Functions to control the installation and configuration of the Vzstorage

# Installs Vzstorage packages
# Triggered from devstack/plugin.sh as part of devstack "pre-install"
function install_vzstorage {
    PSTORAGE_PKGS="pstorage-chunk-server pstorage-client pstorage-ctl \
                pstorage-libs-shared pstorage-metadata-server"
    if [[ "$os_VENDOR" == "CentOS" ]]; then
        sudo rpm -i $PSTORAGE_STANDALONE_REPO_PKG
        PSTORAGE_PKGS=$PSTORAGE_PKGS pstorage-kmod
    elif [[ "$os_VENDOR" == "Virtuozzo" ]]; then
        echo "Running on Virtuozzo distribution, \
            it requires no other kernel modules"
        # Hack to restart vcmmd after numpy updated
        sudo systemctl restart vcmmd.service
    else
        die $LINENO "Vzstorage is supported on CentOS \
                    and Virtuozzo distributions only"
    fi

    #sudo yum install -y $PSTORAGE_PKGS
    install_package $PSTORAGE_PKGS
}

# Confiugures minimal functioning setup 
# Triggered from devstack/plugin.sh as part of devstack "pre-install"
function setup_vzstorage {
    cluster_name=$VZSTORAGE_CLUSTER_NAME
    if [[ -z "$cluster_name" ]]; then
        die $LINENO "VZSTORAGE_CLUSTER_NAME is not defined"
    fi
    [ -d $VZSTORAGE_DATA_DIR ] || sudo mkdir $VZSTORAGE_DATA_DIR

    echo PASSWORD | sudo pstorage -c $cluster_name \
        make-mds -I -a 127.0.0.1 \
        -r $VZSTORAGE_DATA_DIR/$cluster_name-mds -P
    sudo service pstorage-mdsd start
    sudo chkconfig pstorage-mdsd on

    sudo pstorage -c $cluster_name make-cs \
        -r $VZSTORAGE_DATA_DIR/$cluster_name-cs
    sudo service pstorage-csd start
    sudo chkconfig pstorage-csd on

    echo 127.0.0.1 | sudo tee /etc/pstorage/clusters/$cluster_name/bs.list

    set +eu
}

# Cleanup Vzstorage
# Triggered from devstack/plugin.sh as part of devstack "clean"
function cleanup_vzstorage {
    cat /proc/mounts | awk '/^pstorage\:\/\// {print $1}' | xargs -r -n 1 sudo umount
    sudo service pstorage-mdsd stop
    sudo service pstorage-csd stop
    sudo rm -rf /etc/pstorage/clusters/*
    sudo rm -rf ${VZSTORAGE_DATA_DIR}
}


# Configure Vzstorage as a backend for Cinder
# Triggered from stack.sh
# configure_cinder_backend_vzstorage
function configure_cinder_backend_vzstorage {
    local be_name=$1
    iniset $CINDER_CONF DEFAULT os_privileged_user_auth_url \
        $KEYSTONE_AUTH_URI/v2.0
    iniset $CINDER_CONF $be_name volume_backend_name $be_name
    iniset $CINDER_CONF $be_name volume_driver \
        "cinder.volume.drivers.vzstorage.VZStorageDriver"
    iniset $CINDER_CONF $be_name vzstorage_shares_config \
        "$CINDER_CONF_DIR/vzstorage-shares-$be_name.conf"

    CINDER_VZSTORAGE_CLUSTERS="$VZSTORAGE_CLUSTER_NAME \
        [\"-u\", \"stack\", \"-g\", \"qemu\", \"-m\", \"0770\"]"
    echo "$CINDER_VZSTORAGE_CLUSTERS" |\
        tee "$CINDER_CONF_DIR/vzstorage-shares-$be_name.conf"
}
