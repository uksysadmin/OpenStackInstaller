#!/bin/bash

# Source in configuration file
if [[ -f openstack.conf ]]
then
	. openstack.conf
else
	echo "Configuration file not found. Please create openstack.conf"
	exit 1
fi

ovs_install() {
	sudo apt-get update
	sudo apt-get -y install linux-headers-`uname -r` openvswitch-switch 
	sudo service openvswitch-switch start
}

ovs_configure() {
	sudo ovs-vsctl add-rb br-int
	sudo ovs-vsctl add-br br-ex
	sudo ovs-vsctl br-set-external-id br-ex bridge-id br-ex
	sudo ovs-vsctl add-port br-ex $OVS_EXTERNAL_INTERFACE
}

# Main
ovs_install
ovs_configure
