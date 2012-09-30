#!/bin/bash

MYSQL_ROOT_PASS="openstack"
MYSQL_DB_PASS="openstack"
ADMIN_USER_PASSWORD="openstack"
ADMIN_TENANT="admin"
SERVICE_PASS="openstack"
SERVICE_TENANT="service"

ENDPOINT=192.168.1.12
NOVA_ENDPOINT=$ENDPOINT
EC2_ENDPOINT=$ENDPOINT
GLANCE_ENDPOINT=$ENDPOINT
KEYSTONE_ENDPOINT=$ENDPOINT
SWIFT_ENDPOINT=$ENDPOINT
VOLUME_ENDPOINT=$ENDPOINT
CINDER_ENDPOINT=$ENDPOINT
QUANTUM_ENDPOINT=$ENDPOINT

ALL_ROLES="admin Member swiftoperator"

# Services
SERVICES="nova ec2 swift glance keystone cinder quantum"


# MySQL
# Create database
for d in nova glance cinder keystone ovs_quantum
do
	mysql -uroot -p$MYSQL_ROOT_PASS -e "drop database if exists $d;"
	mysql -uroot -p$MYSQL_ROOT_PASS -e "create database $d;"
	mysql -uroot -p$MYSQL_ROOT_PASS -e "grant all privileges on $d.* to $d@\"localhost\" identified by \"$MYSQL_DB_PASS\";"
	mysql -uroot -p$MYSQL_ROOT_PASS -e "grant all privileges on $d.* to $d@\"%\" identified by \"$MYSQL_DB_PASS\";"
done

sudo keystone-manage db_sync

# Service Users
#for a in $SERVICES
#do
#	keystone user-create --name $a --pass $SERVICE_PASS --email $a@localhost.localdomain
#done

# Roles
for r in $ALL_ROLES
do
	keystone role-create --name ${r}
done


# ENDPOINT URLS
NOVA_PUBLIC_URL="http://$NOVA_ENDPOINT:8774/v2/%(tenant_id)s"
NOVA_ADMIN_URL=$NOVA_PUBLIC_URL
NOVA_INTERNAL_URL=$NOVA_PUBLIC_URL

EC2_PUBLIC_URL="http://$EC2_ENDPOINT:8773/services/Cloud"
EC2_ADMIN_URL="http://$EC2_ENDPOINT:8773/services/Admin"
EC2_INTERNAL_URL=$EC2_PUBLIC_URL

GLANCE_PUBLIC_URL="http://$GLANCE_ENDPOINT:9292/v1"
GLANCE_ADMIN_URL=$GLANCE_PUBLIC_URL
GLANCE_INTERNAL_URL=$GLANCE_PUBLIC_URL

KEYSTONE_PUBLIC_URL="http://$KEYSTONE_ENDPOINT:5000/v2.0"
KEYSTONE_ADMIN_URL="http://$KEYSTONE_ENDPOINT:35357/v2.0"
KEYSTONE_INTERNAL_URL=$KEYSTONE_PUBLIC_URL

SWIFT_PUBLIC_URL="https://$SWIFT_ENDPOINT:443/v1/AUTH_%(tenant_id)s"
SWIFT_ADMIN_URL="https://$SWIFT_ENDPOINT:443/v1"
SWIFT_INTERNAL_URL=$SWIFT_PUBLIC_URL

#VOLUME_PUBLIC_URL="http://$VOLUME_ENDPOINT:8776/v1/%(tenant_id)s"
#VOLUME_ADMIN_URL=$VOLUME_PUBLIC_URL
#VOLUME_INTERNAL_URL=$VOLUME_PUBLIC_URL

CINDER_PUBLIC_URL="http://$CINDER_ENDPOINT:8776/v1/%(tenant_id)s"
CINDER_ADMIN_URL=$CINDER_PUBLIC_URL
CINDER_INTERNAL_URL=$CINDER_PUBLIC_URL

QUANTUM_PUBLIC_URL="http://$QUANTUM_ENDPOINT:9696/"
QUANTUM_ADMIN_URL=$QUANTUM_PUBLIC_URL
QUANTUM_INTERNAL_URL=$QUANTUM_PUBLIC_URL


# Create required services
keystone service-create --name nova --type compute --description 'OpenStack Compute Service'
keystone service-create --name swift --type object-store --description 'OpenStack Storage Service'
keystone service-create --name glance --type image --description 'OpenStack Image Service'
keystone service-create --name keystone --type identity --description 'OpenStack Identity Service'
keystone service-create --name ec2 --type ec2 --description 'EC2 Service'
#keystone service-create --name volume --type volume --description 'Volume Service'
keystone service-create --name cinder --type volume --description 'Cinder Service'
keystone service-create --name quantum --type network --description 'OpenStack Networking Service'



# Create endpoints on the services

for S in ${SERVICES^^}
do
	ID=$(keystone service-list | grep -i "\ $S\ " | awk '{print $2}')
	PUBLIC=$(eval echo \$${S}_PUBLIC_URL)
	ADMIN=$(eval echo \$${S}_ADMIN_URL)
	INTERNAL=$(eval echo \$${S}_INTERNAL_URL)
	keystone endpoint-create --region nova --service_id $ID --publicurl $PUBLIC --adminurl $ADMIN --internalurl $INTERNAL
done

#
# Add Default Tenant
#
keystone tenant-create --name $ADMIN_TENANT --description "admin Tenant" --enabled true
ADMIN_TENANT_ID=$(keystone tenant-list | grep "\ $ADMIN_TENANT\ " | awk '{print $2}')



#
# Create 'admin' User with 'admin', 'Member' and swiftoperator role in defaut tenant
#

# Difference --user vs --user_id, --role vs --role_id, tenant vs tenant_id

keystone user-create --name admin --tenant_id $ADMIN_TENANT_ID --pass $ADMIN_USER_PASSWORD --email root@localhost --enabled true
ADMIN_USER_ID=$(keystone user-list | grep "\ admin\ " | awk '{print $2}')

for R in $ALL_ROLES
do
    ROLE_ID=$(keystone role-list | grep "\ $R\ " | awk '{print $2}')
    keystone user-role-add --user_id $ADMIN_USER_ID --role_id $ROLE_ID --tenant_id $ADMIN_TENANT_ID
done

#
# Get admin role id
#
ADMIN_ROLE_ID=$(keystone role-list | grep "\ admin\ " | awk '{print $2}')

#
# Add Service Tenant
# tenant-create name service
#
keystone tenant-create --name $SERVICE_TENANT --description "Service Tenant" --enabled true
SERVICE_TENANT_ID=$(keystone tenant-list | grep "\ $SERVICE_TENANT\ " | awk '{print $2}')

#
# Add services to service tenant
# user-create --name service_name --pass service_name --tenant_id service_tenant_id --role admin_role_id
#
for S in ${SERVICES}
do
    keystone user-create --name $S --pass $S --tenant_id $SERVICE_TENANT_ID --email $S@localhost --enabled true
    SERVICE_ID=$(keystone user-list | grep "\ $S\ " | awk '{print $2}')
    # Grant admin role to the $S user in the service tenant
    keystone user-role-add --user_id $SERVICE_ID --role_id ${ADMIN_ROLE_ID} --tenant_id $SERVICE_TENANT_ID
done
