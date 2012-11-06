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
	# VM Communication network bridge
	sudo ovs-vsctl add-br ${INT_BRIDGE}
	sudo ovs-vsctl add-br br-${PRIVATE_INTERFACE}
	sudo ovs-vsctl add-port br-${PRIVATE_INTERFACE} ${PRIVATE_INTERFACE}

	# External bridge
	sudo ovs-vsctl add-br ${EXT_BRIDGE}
	sudo ovs-vsctl add-port ${EXT_BRIDGE} ${PRIVATE_INTERFACE}
}

# Main
ovs_install
ovs_configure

# Configure ${EXT_BRIDGE} to reach public network :
sudo ip addr flush dev ${EXT_BRIDGE}
sudo ip addr add ${EXT_BRIDGE_IP}/${EXT_BRIDGE_NETMASK} dev ${EXT_BRIDGE}
sudo ip link set ${EXT_BRIDGE} up
