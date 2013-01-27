#!/bin/bash

# Source in configuration file
if [[ -f openstack.conf ]]
then
        . openstack.conf
else
        echo "Configuration file not found. Please create openstack.conf"
        exit 1
fi

keystone_install() {
	sudo apt-get install -y keystone python-keystone python-keystoneclient

	# Database
	KEYSTONE_CONF=/etc/keystone/keystone.conf
        sudo sed -i "s,^connection.*,connection = mysql://keystone:$MYSQL_DB_PASS@$MYSQL_SERVER/keystone,g" $KEYSTONE_CONF
	sudo keystone-manage db_sync
}

keystone_create_environment_resource_file() {
	# Create "adminrc" resource file
	RC_FILE=adminrc
	if [[ -f $RC_FILE ]]
	then
		# Back up existing file
		rm -f $RC_FILE.bak
		mv $RC_FILE{,.bak}
	fi

	echo "export OS_TENANT_NAME=$ADMIN_TENANT" >> $RC_FILE
	echo "export OS_USERNAME=admin" >> $RC_FILE
	echo "export OS_PASSWORD=$ADMIN_USER_PASSWORD" >> $RC_FILE
	echo "export OS_AUTH_URL=http://$KEYSTONE_ENDPOINT:5000/v2.0/" >> $RC_FILE
	echo "export SERVICE_ENDPOINT=http://$KEYSTONE_ENDPOINT:35357/v2.0/" >> $RC_FILE
	echo "export SERVICE_TOKEN=ADMIN" >> $RC_FILE
}

keystone_create_roles() {
	# Roles
	for r in $ALL_ROLES
	do
		keystone role-create --name ${r}
	done
}

keystone_create_services() {
	# Create required services
	keystone service-create --name nova --type compute --description 'OpenStack Compute Service'
	keystone service-create --name swift --type object-store --description 'OpenStack Storage Service'
	keystone service-create --name glance --type image --description 'OpenStack Image Service'
	keystone service-create --name keystone --type identity --description 'OpenStack Identity Service'
	keystone service-create --name ec2 --type ec2 --description 'EC2 Service'
	#keystone service-create --name volume --type volume --description 'Volume Service'
	keystone service-create --name cinder --type volume --description 'Cinder Service'
	keystone service-create --name quantum --type network --description 'OpenStack Networking Service'
}

keystone_create_service_endpoints() {
	# Create endpoints on the services

	for S in ${SERVICES^^}
	do
		ID=$(keystone service-list | grep -i "\ $S\ " | awk '{print $2}')
		PUBLIC=$(eval echo \$${S}_PUBLIC_URL)
		ADMIN=$(eval echo \$${S}_ADMIN_URL)
		INTERNAL=$(eval echo \$${S}_INTERNAL_URL)
		keystone endpoint-create --region nova --service_id $ID --publicurl $PUBLIC --adminurl $ADMIN --internalurl $INTERNAL
	done
}

keystone_create_default_tenant() {
	# Add Default Tenant
	keystone tenant-create --name $ADMIN_TENANT --description "admin Tenant" --enabled true
}


keystone_create_user_admin() {
	# Create 'admin' User with 'admin', 'Member' and swiftoperator role in defaut tenant
	# Difference --user vs --user_id, --role vs --role_id, tenant vs tenant_id

	ADMIN_TENANT_ID=$(keystone tenant-list | grep "\ $ADMIN_TENANT\ " | awk '{print $2}')
	keystone user-create --name admin --tenant_id $ADMIN_TENANT_ID --pass $ADMIN_USER_PASSWORD --email root@localhost --enabled true
}

keystone_assign_roles_admin() {
	ADMIN_USER_ID=$(keystone user-list | grep "\ admin\ " | awk '{print $2}')
	for R in $ALL_ROLES
	do
	    ROLE_ID=$(keystone role-list | grep "\ $R\ " | awk '{print $2}')
	    keystone user-role-add --user_id $ADMIN_USER_ID --role_id $ROLE_ID --tenant_id $ADMIN_TENANT_ID
	done
}

keystone_create_service_tenant() {
	# Add Service Tenant
	keystone tenant-create --name $SERVICE_TENANT --description "Service Tenant" --enabled true
}

keystone_create_user_services() {
	# Get admin role id
	ADMIN_ROLE_ID=$(keystone role-list | grep "\ admin\ " | awk '{print $2}')
	# Add services to service tenant
	SERVICE_TENANT_ID=$(keystone tenant-list | grep "\ $SERVICE_TENANT\ " | awk '{print $2}')
	for S in ${SERVICES}
	do
	    keystone user-create --name $S --pass $SERVICE_PASS --tenant_id $SERVICE_TENANT_ID --email $S@localhost --enabled true
	    SERVICE_ID=$(keystone user-list | grep "\ $S\ " | awk '{print $2}')
	    # Grant admin role to the $S user in the service tenant
	    keystone user-role-add --user_id $SERVICE_ID --role_id ${ADMIN_ROLE_ID} --tenant_id $SERVICE_TENANT_ID
	done
}



keystone_install
keystone_create_environment_resource_file
. adminrc

keystone_create_roles
keystone_create_default_tenant
keystone_create_user_admin
keystone_assign_roles_admin

keystone_create_services
keystone_create_service_endpoints
keystone_create_service_tenant
keystone_create_user_services
