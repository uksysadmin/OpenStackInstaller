#!/bin/bash

# Cinder requires LVM volume: cinder-volumes

# Source in configuration file
if [[ -f openstack.conf ]]
then
	. openstack.conf
else
	echo "Configuration file not found. Please create openstack.conf"
	exit 1
fi

CINDER_CONF=/etc/cinder/cinder.conf
CINDER_API_PASTE=/etc/cinder/api-paste.ini

cinder_install() {
	sudo apt-get update
	sudo apt-get -y install cinder-api cinder-scheduler cinder-volume open-iscsi python-cinderclient tgt
}

cinder_configure() {
	# Cinder Api Paste
	sudo sed -i "s/127.0.0.1/$KEYSTONE_ENDPOINT/g" $CINDER_API_PASTE
	sudo sed -i "s/%SERVICE_TENANT_NAME%/$SERVICE_TENANT/g" $CINDER_API_PASTE
	sudo sed -i "s/%SERVICE_USER%/cinder/g" $CINDER_API_PASTE
	sudo sed -i "s/%SERVICE_PASSWORD%/$SERVICE_PASS/g" $CINDER_API_PASTE

	# Database
	sudo sed -i "s,^sql_connection.*,sql_connection = mysql://cinder:$MYSQL_DB_PASS@$MYSQL_SERVER/cinder,g" $CINDER_CONF
}

cinder_restart() {
	sudo stop cinder-api
	sudo start cinder-api
	sudo stop cinder-volume
	sudo start cinder-volume
}

# Main
cinder_install
cinder_configure
cinder_restart
