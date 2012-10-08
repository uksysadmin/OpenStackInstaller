#!/bin/bash

# Source in configuration file
if [[ -f openstack.conf ]]
then
	. openstack.conf
else
	echo "Configuration file not found. Please create openstack.conf"
	exit 1
fi

GLANCE_REGISTRY_CONF=/etc/glance/glance-registry.conf
GLANCE_API_CONF=/etc/glance/glance-api.conf
GLANCE_API_PASTE=/etc/glance/glance-api-paste.ini
GLANCE_REGISTRY_PASTE=/etc/glance/glance-registry-paste.ini

glance_install() {
	sudo apt-get -y install glance glance-api python-glanceclient glance-common glance-registry python-glance
}

glance_configure() {
	# Glance Api Paste
	sudo sed -i "s/127.0.0.1/$KEYSTONE_ENDPOINT/g" $GLANCE_API_PASTE
	sudo sed -i "s/%SERVICE_TENANT_NAME%/$SERVICE_TENANT/g" $GLANCE_API_PASTE
	sudo sed -i "s/%SERVICE_USER%/glance/g" $GLANCE_API_PASTE
	sudo sed -i "s/%SERVICE_PASSWORD%/$SERVICE_PASS/g" $GLANCE_API_PASTE

	# Glance Registry Paste
	sudo sed -i "s/127.0.0.1/$KEYSTONE_ENDPOINT/g" $GLANCE_REGISTRY_PASTE
	sudo sed -i "s/%SERVICE_TENANT_NAME%/$SERVICE_TENANT/g" $GLANCE_REGISTRY_PASTE
	sudo sed -i "s/%SERVICE_USER%/glance/g" $GLANCE_REGISTRY_PASTE
	sudo sed -i "s/%SERVICE_PASSWORD%/$SERVICE_PASS/g" $GLANCE_REGISTRY_PASTE

	# Database
	sudo sed -i "s,^sql_connection.*,sql_connection = mysql://glance:$MYSQL_DB_PASS@$MYSQL_SERVER/glance,g" $GLANCE_REGISTRY_CONF
	sudo sed -i "s,^sql_connection.*,sql_connection = mysql://glance:$MYSQL_DB_PASS@$MYSQL_SERVER/glance,g" $GLANCE_API_CONF

	# Add Paste Lines
	if [[ ! $(sudo grep "^\[paste_deploy\]" $GLANCE_REGISTRY_CONF) ]]
	then
		echo "[paste_deploy]
flavor = keystone" | sudo tee -a $GLANCE_REGISTRY_CONF
	fi

	if [[ ! $(sudo grep "^\[paste_deploy\]" $GLANCE_API_CONF) ]]
	then
		echo "[paste_deploy]
flavor = keystone" | sudo tee -a $GLANCE_API_CONF
	fi

	sudo glance-manage db_sync
}

glance_restart() {
	sudo stop glance-api
	sudo start glance-api
	sudo stop glance-registry
	sudo start glance-registry
}

# Main
glance_install
glance_configure
glance_restart
