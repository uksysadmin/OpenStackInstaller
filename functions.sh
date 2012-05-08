#!/bin/bash

#    Author K. Jackson (kevin@linuxservices.co.uk) 0th May 2012
#
#    This program is free software: you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation, either version 3 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program.  If not, see <http://www.gnu.org/licenses/>.
#

# Functions script gets sourced in from the main OSinstall.sh script

export LANG=C

usage() {
cat << USAGE
Syntax
    OSinstall.sh -T {type} -s { network size } -n {number of networks} -p {public interface} -P {private interface} -f {floating_range} -F {fixed_range} -V {VLAN start} -C {Controller Address} -A {admin} -v {qemu | kvm} -t {default tenancy} -M {ip of MySQL service}

    -T: Installation type: all (single node) | controller | compute (default all)
    -s: Network size (IP address range on this network) (default 64)
    -n: Number of networks to create (default 1)
    -P: Public network interface (default network with default gw)
    -F: Floating (Public) IP range e.g. 172.16.1.0/24
    -p: Private network interface
    -f: Fixed (Private) IP range e.g. 10.0.0.0/8
    -V: VLAN Start (default 100)
    -C: Cloud Controller Address (default is worked out from public interface IP)
    -A: Admin username (default admin)
    -v: Virtualization type: qemu for software, kvm for kvm (hardware) (default qemu)
    -t: Tenancy (Project) (default demo)
    -M: MySQL IP (default Cloud Controller address)
USAGE
exit 1
}

mask2cidr() {
    # Credit http://www.linuxquestions.org/questions/programming-9/bash-cidr-calculator-646701/
    nbits=0
    if [ ! -z "$1" ]
    then
	    IFS=.
	    for dec in $1 ; do
		case $dec in
		    255) let nbits+=8;;
		    254) let nbits+=7;;
		    252) let nbits+=6;;
		    248) let nbits+=5;;
		    240) let nbits+=4;;
		    224) let nbits+=3;;
		    192) let nbits+=2;;
		    128) let nbits+=1;;
		    0);;
		    *) echo "Error: $dec is not recognised"; exit 1
		esac
	    done
    fi
    echo "$nbits"
}

configure_nova() {

# Configure the /etc/nova/nova.conf file
cat > /etc/nova/nova.conf << EOF
--daemonize=1
--dhcpbridge_flagfile=/etc/nova/nova.conf
--dhcpbridge=/usr/bin/nova-dhcpbridge
--force_dhcp_release
--logdir=/var/log/nova
--state_path=/var/lib/nova
--verbose
--connection_type=libvirt
--libvirt_type=${VIRT}
--libvirt_use_virtio_for_bridges
--sql_connection=mysql://nova:${MYSQL_PASS}@${MYSQL_ADDR}/nova
--s3_host=${CC_ADDR}
--s3_dmz=${CC_ADDR}
--rabbit_host=${CC_ADDR}
--ec2_host=${CC_ADDR}
--ec2_dmz_host=${CC_ADDR}
--ec2_url=http://${CC_ADDR}:8773/services/Cloud
--fixed_range=${VMNET}
--network_size=${NETWORK_SIZE}
--num_networks=${NUM_NETWORKS}
--FAKE_subdomain=ec2
--public_interface=${PUBLIC_INTERFACE}
--auto_assign_floating_ip
--state_path=/var/lib/nova
--lock_path=/var/lock/nova
--image_service=nova.image.glance.GlanceImageService
--glance_api_servers=${CC_ADDR}:9292
--vlan_start=${VLAN_START}
--vlan_interface=${PRIVATE_INTERFACE}
--root_helper=sudo nova-rootwrap
--zone_name=nova
--node_availability_zone=nova
--storage_availability_zone=nova
--allow_admin_api
--enable_zone_routing
--api_paste_config=/etc/nova/api-paste.ini
--vncserver_host=0.0.0.0
--vncproxy_url=http://${CC_ADDR}:6080
--ajax_console_proxy_url=http://${CC_ADDR}:8000
--osapi_host=${CC_ADDR}
--rabbit_host=${CC_ADDR}
--auth_strategy=keystone
--keystone_ec2_url=http://${CC_ADDR}:5000/v2.0/ec2tokens
--multi_host
--send_arp_for_ha
--novnc_enabled=true
--novncproxy_base_url=http://${CC_ADDR}:6080/vnc_auto.html
--vncserver_proxyclient_address=${CC_ADDR}
--vncserver_listen=${CC_ADDR}
EOF

cat > /etc/nova/nova-compute.conf << EOF
--libvirt_type=${VIRT}
EOF


	cp configs/api-paste.ini /tmp
	sed -i "s/%CC_ADDR%/$CC_ADDR/g" /tmp/api-paste.ini
	sed -i "s/%SERVICE_TENANT_NAME%/$TENANCY/g" /tmp/api-paste.ini
	rm -f /etc/nova/api-paste.ini
	cp /tmp/api-paste.ini /etc/nova/api-paste.ini
	rm -f /tmp/api-paste.ini
}

local_mysql_install() {
	echo "Configuring MySQL for OpenStack"

	# MySQL - set root user in MySQL to $MYSQL_PASS
	# which we then use to set up nova, keystone and glance databases with the same $MYSQL_PASS

	cat <<MYSQL_PRESEED | debconf-set-selections
mysql-server-5.1 mysql-server/root_password password $MYSQL_PASS
mysql-server-5.1 mysql-server/root_password_again password $MYSQL_PASS
mysql-server-5.1 mysql-server/start_on_boot boolean true
MYSQL_PRESEED
	apt-get install -y mysql-server 2>&1 >> ${LOGFILE}
	sed -i 's/127.0.0.1/0.0.0.0/g' /etc/mysql/my.cnf
	service mysql restart

	# Create Databases
	for D in nova glance keystone
	do
		mysql -uroot -p$MYSQL_PASS -e "CREATE DATABASE $D;"
		mysql -uroot -p$MYSQL_PASS -e "GRANT ALL PRIVILEGES ON $D.* TO '$D'@'%' WITH GRANT OPTION;"
		mysql -uroot -p$MYSQL_PASS -e "SET PASSWORD FOR '$D'@'%' = PASSWORD('$MYSQL_PASS');"
	done
}

remote_mysql_install() {
	# Create Databases
	for D in nova glance keystone
	do
		mysql -uroot -p$MYSQL_PASS -h ${MYSQL_ADDR} -e "CREATE DATABASE $D;"
		mysql -uroot -p$MYSQL_PASS -h ${MYSQL_ADDR} -e "GRANT ALL PRIVILEGES ON $D.* TO '$D'@'%' WITH GRANT OPTION;"
		mysql -uroot -p$MYSQL_PASS -h ${MYSQL_ADDR} -e "SET PASSWORD FOR '$D'@'%' = PASSWORD('$MYSQL_PASS');"
	done
}

glance_install() {
	# Configure glance configs
	# Grab from local github repo
	TMPAREA=/tmp/glance_OSI
	rm -rf $TMPAREA
	mkdir -p $TMPAREA
	cp configs/glance* $TMPAREA

	# Configure files (sed info in)
	if [[ $LOCAL_MYSQL_INSTALL -eq 1 ]] 
	    then
            MYSQL_ADDR=${CC_ADDR}
        fi

	sed -i "s/%ADMIN_TOKEN%/$KEYSTONE_ADMIN_TOKEN/g" $TMPAREA/*.*
	sed -i "s/%MYSQL_ADDR%/$MYSQL_ADDR/g" $TMPAREA/*.*
	sed -i "s/%MYSQL_PASS%/$MYSQL_PASS/g" $TMPAREA/*.*
	sed -i "s/%CC_ADDR%/$CC_ADDR/g" $TMPAREA/*.*

	# Put in place
	rm -f /etc/glance/glance.*
	mkdir -p /etc/glance
	cp $TMPAREA/* /etc/glance

	stop glance-registry

	glance-manage version_control 0
	glance-manage db_sync

	start glance-registry
}

keystone_install() {
	# Configure keystone configs
	# Grab from local github repo
	TMPAREA=/tmp/keystone_OSI
	rm -rf $TMPAREA
	mkdir -p $TMPAREA
	cp configs/keystone.conf $TMPAREA

	# Configure files (sed info in)
        if [[ $LOCAL_MYSQL_INSTALL -eq 1 ]] 
        then
            MYSQL_ADDR=${CC_ADDR}
        fi
	
        sed -i "s/%MYSQL_ADDR%/$MYSQL_ADDR/g" $TMPAREA/*.*
	sed -i "s/%MYSQL_PASS%/$MYSQL_PASS/g" $TMPAREA/*.*
        sed -i "s/%CC_ADDR%/$CC_ADDR/g" $TMPAREA/*.*

	# Put in place
	if [[ ! -f /etc/keystone/keystone.conf.orig ]] 
	then 
		mv /etc/keystone/keystone.conf{,.orig}
	else
		rm -f /etc/keystone/keystone.conf	
	fi
	cp $TMPAREA/keystone.conf /etc/keystone

	stop keystone 
	start keystone 

	# Create roles, tenants and services
	./keystone-services.sh $CC_ADDR $ADMIN $TENANCY
	# Technically the user gets created in the above reference script
	# But this useful script can be run seperately without issues
	# and creates the resource config env file (userrc)
	./create-user -u $ADMIN -p openstack -t $TENANCY -C $CC_ADDR
}

horizon_install() {
	# Small amount of configuration
	rm -f /etc/openstack-dashboard/local_settings.py
	cp configs/local_settings.py /etc/openstack-dashboard/local_settings.py
	mkdir -p /var/www/.novaclient
	chown www-data /var/www/.novaclient
	service apache2 restart
}
