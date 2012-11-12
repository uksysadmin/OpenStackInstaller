#!/bin/bash

# Source in configuration file
if [[ -f openstack.conf ]]
then
	. openstack.conf
else
	echo "Configuration file not found. Please create openstack.conf"
	exit 1
fi

QUANTUM_CONF=/etc/quantum/quantum.conf
OVS_QUANTUM_PLUGIN_INI=/etc/quantum/plugins/openvswitch/ovs_quantum_plugin.ini

quantum_agent_install() {
	sudo apt-get -y install linux-headers-`uname -r` quantum-plugin-openvswitch-agent openvswitch-datapath-source

	sudo module-assistant auto-install openvswitch-datapath
}

quantum_agent_configure() {
	# quantum.conf
	sudo sed -i 's/^# auth_strategy.*/auth_strategy = keystone/g' $QUANTUM_CONF
	sudo sed -i 's/^# fake_rabbit.*/fake_rabbit = False/g' $QUANTUM_CONF

	# ovs_quantum_plugin.ini
	sudo rm -f $OVS_QUANTUM_PLUGIN_INI
        cat >/tmp/ovs_quantum_plugin.ini << EOF
[DATABASE]
sql_connection = mysql://quantum:$MYSQL_DB_PASS@$MYSQL_SERVER:3306/quantum
reconnect_interval = 2
[OVS]
# VLAN
tenant_network_type=vlan
network_vlan_ranges = ${PHYSICAL_NETWORK_NAME}:1:4094
bridge_mappings = physnet1:br-${PRIVATE_INTERFACE}
#tenant_network_type = gre
#tunnel_id_ranges = 1:1000
#integration_bridge = ${INT_BRIDGE}
#tunnel_bridge = br-tun
#local_ip = 10.0.0.201
#enable_tunneling = True
[AGENT]
root_helper = sudo /usr/bin/quantum-rootwrap /etc/quantum/rootwrap.conf
EOF
	sudo mv /tmp/ovs_quantum_plugin.ini $OVS_QUANTUM_PLUGIN_INI
	sudo chown quantum:quantum $OVS_QUANTUM_PLUGIN_INI
	sudo chmod 644 $OVS_QUANTUM_PLUGIN_INI
}

quantum_agent_restart() {
	sudo service openvswitch-switch stop
	sudo service openvswitch-switch start
	sudo service quantum-plugin-openvswitch-agent stop
	sudo service quantum-plugin-openvswitch-agent start
}

# Main
quantum_agent_install
quantum_agent_configure
quantum_agent_restart
