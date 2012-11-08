#!/bin/bash

# Source in configuration file
if [[ -f openstack.conf ]]
then
	. openstack.conf
else
	echo "Configuration file not found. Please create openstack.conf"
	exit 1
fi

NOVA_CONF=/etc/nova/nova.conf
NOVA_API_PASTE=/etc/nova/api-paste.ini

nova_install() {
	sudo apt-get -y install nova-api nova-cert nova-doc nova-objectstore nova-scheduler nova-volume rabbitmq-server novnc nova-novncproxy nova-consoleauth python-cinderclient
}

nova_configure() {
	cat > /tmp/nova.conf << EOF
[DEFAULT]
logdir=/var/log/nova
state_path=/var/lib/nova
lock_path=/run/lock/nova
allow_admin_api=true
verbose=True
api_paste_config=/etc/nova/api-paste.ini
scheduler_driver=nova.scheduler.simple.SimpleScheduler
s3_host=$SWIFT_ENDPOINT
ec2_host=$EC2_ENDPOINT
ec2_dmz_host=$EC2_ENDPOINT
rabbit_host=$RABBIT_ENDPOINT
cc_host=$NOVA_ENDPOINT
nova_url=http://$NOVA_ENDPOINT:8774/v1.1/
sql_connection=mysql://nova:$MYSQL_DB_PASS@$MYSQL_SERVER/nova
ec2_url=http://$EC2_ENDPOINT:8773/services/Cloud
rootwrap_config=/etc/nova/rootwrap.conf

# Auth
use_deprecated_auth=false
auth_strategy=keystone
keystone_ec2_url=http://$KEYSTONE_ENDPOINT:5000/v2.0/ec2tokens
# Imaging service
glance_api_servers=$GLANCE_ENDPOINT:9292
image_service=nova.image.glance.GlanceImageService

# Virt driver
connection_type=libvirt
libvirt_type=$LIBVIRT_TYPE
libvirt_use_virtio_for_bridges=true
start_guests_on_host_boot=false
resume_guests_state_on_host_boot=false

# Vnc configuration
novnc_enabled=true
novncproxy_base_url=http://$NOVA_ENDPOINT:6080/vnc_auto.html
novncproxy_port=6080
vncserver_proxyclient_address=$NOVA_ENDPOINT
vncserver_listen=$NOVA_ENDPOINT

# Network settings
#dhcpbridge_flagfile=/etc/nova/nova.conf
#dhcpbridge=/usr/bin/nova-dhcpbridge
#network_manager=nova.network.manager.VlanManager
#public_interface=$PUBLIC_INTERFACE
#vlan_interface=$PRIVATE_INTERFACE
#vlan_start=$VLAN_START
#fixed_range=$PRIVATE_RANGE
#routing_source_ip=$NOVA_ENDPOINT
#network_size=1
network_api_class=nova.network.quantumv2.api.API
quantum_url=http://$QUANTUM_ENDPOINT:9696
quantum_auth_strategy=keystone
quantum_admin_tenant_name=$SERVICE_TENANT
quantum_admin_username=quantum
quantum_admin_password=$SERVICE_PASS
quantum_admin_auth_url=http://$KEYSTONE_ENDPOINT:35357/v2.0
libvirt_vif_driver=nova.virt.libvirt.vif.LibvirtHybridOVSBridgeDriver
linuxnet_interface_driver=nova.network.linux_net.LinuxOVSInterfaceDriver
firewall_driver=nova.virt.libvirt.firewall.IptablesFirewallDriver
force_dhcp_release=True
multi_host=True

# Cinder #
iscsi_helper=tgt
iscsi_ip_address=$CINDER_ENDPOINT
volume_api_class=nova.volume.cinder.API
osapi_volume_listen_port=5900
EOF

	sudo rm -f $NOVA_CONF
	sudo mv /tmp/nova.conf $NOVA_CONF
	sudo chmod 0640 $NOVA_CONF
	sudo chown nova:nova $NOVA_CONF

	# Paste file
        sudo sed -i "s/127.0.0.1/$KEYSTONE_ENDPOINT/g" $NOVA_API_PASTE
        sudo sed -i "s/%SERVICE_TENANT_NAME%/$SERVICE_TENANT/g" $NOVA_API_PASTE
        sudo sed -i "s/%SERVICE_USER%/nova/g" $NOVA_API_PASTE
        sudo sed -i "s/%SERVICE_PASSWORD%/$SERVICE_PASS/g" $NOVA_API_PASTE

	sudo nova-manage db sync
}

nova_networking() {
	# Defunct - not called
	# VLAN (for now)
	sudo nova-manage network create private --fixed_range_v4=$FIXED_RANGE --num_networks=1 --bridge=br100 --bridge_interface=$PRIVATE_INTERFACE --network_size=64 --vlan=$VLAN_START
	sudo nova-manage floating create --ip_range=$FLOATING_RANGE
}

nova_restart() {
	for P in $(ls /etc/init/nova* | cut -d'/' -f4 | cut -d'.' -f1)
	do
		sudo stop ${P} 
		sudo start ${P}
	done

	sudo service rabbitmq-server restart
}

# Main
nova_install
nova_configure
#nova_networking
nova_restart
