#!/bin/bash

# Source in configuration file
if [[ -f openstack.conf ]]
then
	. openstack.conf
else
	echo "Configuration file not found. Please create openstack.conf"
	exit 1
fi

DASHBOARD_LOCAL_SETTINGS=/etc/openstack-dashboard/local_settings.py

horizon_install() {
	sudo apt-get -y install apache2 openstack-dashboard memcached
}

horizon_configure() {
	sudo sed -i 's/^QUANTUM_ENABLED.*/QUANTUM_ENABLED = True/g' $DASHBOARD_LOCAL_SETTINGS
	echo "QUANTUM_ENABLED = True" | sudo tee -a $DASHBOARD_LOCAL_SETTINGS
	sudo sed -i "s/^OPENSTACK_HOST.*/OPENSTACK_HOST = \"$KEYSTONE_ENDPOINT\"/g" $DASHBOARD_LOCAL_SETTINGS

	# Default under Ubuntu is to install their theme. Can be overidden by setting HORIZON_THEME=default
	case $HORIZON_THEME in
		default)
			rm -f /etc/openstack-dashboard/ubuntu_theme.py
			;;
		*)
			;;
	esac
}

horizon_restart() {
	sudo service apache2 restart
	sudo service memcached restart
}

# Main
horizon_install
horizon_configure
horizon_restart
