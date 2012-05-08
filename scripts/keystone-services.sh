#!/bin/bash

# Creates 'admin' user in default tenant ($TENANCY) with 'admin' role
# Creates service roles (swift, glance, nova, keystone) in 'service' tenant with 'admin' role
# Creates $USER role in default tenant ($TENANCY) with 'Member' and 'admin' roles

# !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
# WARNING! This script drops the keystone db and recreates it
# !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

# set default password
PASSWORD=openstack
DATABASE=keystone
DATABASE_USER=root
DATABASE_PASSWORD=openstack

# Assumes ENDPOINT has Compute API, Glance, Keystone and Storage

ENDPOINT=$1
USER=$2
# Default tenant to create
TENANCY=$3


if [[ ! $ENDPOINT ]]
then
	echo "Syntax: $(basename $0) KEYSTONE_IP USER TENANCY"
	exit 1
fi

# Using token auth env variables
SERVICE_ENDPOINT=http://$ENDPOINT:35357/v2.0/
SERVICE_TOKEN=999888777666


# ENDPOINT URLS
NOVA_PUBLIC_URL="http://$ENDPOINT:8774/v2/\$(tenant_id)s"
NOVA_ADMIN_URL=$NOVA_PUBLIC_URL
NOVA_INTERNAL_URL=$NOVA_PUBLIC_URL

EC2_PUBLIC_URL="http://$ENDPOINT:8773/services/Cloud"
EC2_ADMIN_URL="http://$ENDPOINT:8773/services/Admin"
EC2_INTERNAL_URL=$EC2_PUBLIC_URL

GLANCE_PUBLIC_URL="http://$ENDPOINT:9292/v1"
GLANCE_ADMIN_URL=$GLANCE_PUBLIC_URL
GLANCE_INTERNAL_URL=$GLANCE_PUBLIC_URL

KEYSTONE_PUBLIC_URL="http://$ENDPOINT:5000/v2.0"
KEYSTONE_ADMIN_URL="http://$ENDPOINT:35357/v2.0"
KEYSTONE_INTERNAL_URL=$KEYSTONE_PUBLIC_URL

SWIFT_PUBLIC_URL="https://$ENDPOINT:443/v1/AUTH_\$(tenant_id)s"
SWIFT_ADMIN_URL="https://$ENDPOINT:443/v1"
SWIFT_INTERNAL_URL=$SWIFT_PUBLIC_URL

VOLUME_PUBLIC_URL="http://$ENDPOINT:8776/v1/\$(tenant_id)s"
VOLUME_ADMIN_URL=$VOLUME_PUBLIC_URL
VOLUME_INTERNAL_URL=$VOLUME_PUBLIC_URL

# !WARNING!
# Drop the keystone database
# Recreate it
mysql -u${DATABASE_USER} -p${DATABASE_PASSWORD} -e "drop database $DATABASE; create database $DATABASE;" 2>&1 > /dev/null
keystone-manage db_sync


# Create required services
keystone --token $SERVICE_TOKEN --endpoint $SERVICE_ENDPOINT service-create --name nova --type compute --description 'OpenStack Compute Service'
keystone --token $SERVICE_TOKEN --endpoint $SERVICE_ENDPOINT service-create --name swift --type object-store --description 'OpenStack Storage Service'
keystone --token $SERVICE_TOKEN --endpoint $SERVICE_ENDPOINT service-create --name glance --type image --description 'OpenStack Image Service'
keystone --token $SERVICE_TOKEN --endpoint $SERVICE_ENDPOINT service-create --name keystone --type identity --description 'OpenStack Identity Service'
keystone --token $SERVICE_TOKEN --endpoint $SERVICE_ENDPOINT service-create --name ec2 --type ec2 --description 'EC2 Service'
keystone --token $SERVICE_TOKEN --endpoint $SERVICE_ENDPOINT service-create --name volume --type volume --description 'Volume Service'



# Create endpoints on the services
for S in NOVA EC2 SWIFT GLANCE VOLUME KEYSTONE
do
	ID=$(keystone --token $SERVICE_TOKEN --endpoint $SERVICE_ENDPOINT service-list | grep -i "\ $S\ " | awk '{print $2}')
	PUBLIC=$(eval echo \$${S}_PUBLIC_URL)
	ADMIN=$(eval echo \$${S}_ADMIN_URL)
	INTERNAL=$(eval echo \$${S}_INTERNAL_URL)
	keystone --token $SERVICE_TOKEN --endpoint $SERVICE_ENDPOINT endpoint-create --region nova --service_id $ID --publicurl $PUBLIC --adminurl $ADMIN --internalurl $INTERNAL
done


# 
# Add Default Tenant
# 
keystone --token $SERVICE_TOKEN --endpoint $SERVICE_ENDPOINT tenant-create --name $TENANCY --description "Default Tenant" --enabled true
TENANT_ID=$(keystone --token $SERVICE_TOKEN --endpoint $SERVICE_ENDPOINT tenant-list | grep "\ $TENANCY\ " | awk '{print $2}')


#
# Create roles
#
ALL_ROLES="admin Member swiftoperator"
for R in $ALL_ROLES
do
	keystone --token $SERVICE_TOKEN --endpoint $SERVICE_ENDPOINT role-create --name $R
done

# 
# Create 'admin' User with 'admin', 'Member' and swiftoperator role in defaut tenant
#
keystone --token $SERVICE_TOKEN --endpoint $SERVICE_ENDPOINT user-create --name admin --tenant_id $TENANT_ID --pass $PASSWORD --email root@localhost --enabled true
ADMIN_USER_ID=$(keystone --token $SERVICE_TOKEN --endpoint $SERVICE_ENDPOINT user-list | grep "\ admin\ " | awk '{print $2}')
for R in $ALL_ROLES
do
	ROLE_ID=$(keystone --token $SERVICE_TOKEN --endpoint $SERVICE_ENDPOINT role-list | grep "\ $R\ " | awk '{print $2}')
	keystone --token $SERVICE_TOKEN --endpoint $SERVICE_ENDPOINT user-role-add --user $ADMIN_USER_ID --role $ROLE_ID --tenant_id $TENANT_ID
done

#
# Get admin role id
#
ADMIN_ROLE_ID=$(keystone --token $SERVICE_TOKEN --endpoint $SERVICE_ENDPOINT role-list | grep "\ admin\ " | awk '{print $2}')

#
# Add Service Tenant
# tenant-create name service
#
keystone --token $SERVICE_TOKEN --endpoint $SERVICE_ENDPOINT tenant-create --name service --description "Service Tenant" --enabled true
SERVICE_TENANT_ID=$(keystone --token $SERVICE_TOKEN --endpoint $SERVICE_ENDPOINT tenant-list | grep "\ service\ " | awk '{print $2}')

#
# Add services to service tenant
# user-create --name service_name --pass service_name --tenant_id service_tenant_id --role admin_role_id
#
SERVICES="glance nova keystone swift"
for S in ${SERVICES}
do
	keystone --token $SERVICE_TOKEN --endpoint $SERVICE_ENDPOINT user-create --name $S --pass $S --tenant_id $SERVICE_TENANT_ID --email $S@localhost --enabled true
	SERVICE_ID=$(keystone --token $SERVICE_TOKEN --endpoint $SERVICE_ENDPOINT user-list | grep "\ $S\ " | awk '{print $2}')
	# Grant admin role to the $S user in the service tenant
	keystone --token $SERVICE_TOKEN --endpoint $SERVICE_ENDPOINT user-role-add --user $SERVICE_ID --role ${ADMIN_ROLE_ID} --tenant_id $SERVICE_TENANT_ID
done


# For a normal user we'll use the 'create-user' script
./create-user -u ${USER} -p ${PASSWORD} -t ${TENANCY} -C ${ENDPOINT}
