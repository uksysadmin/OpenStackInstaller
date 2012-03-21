#!/bin/bash

#    Author K. Jackson (kevin@linuxservices.co.uk) 18 Feb 2011
#    Updated: February 2012 for Essex / Precise Installs
#
#    OSinstall.sh - Simple bash script installer for Openstack
#    Copyright (C) 2011 Kevin Jackson
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

#    Script will either take arguments on the command line or install defaults
#    This will form the basis of an automated script to install the relevant components of OpenStack

export LANG=C

# Check we're running as root
if [ "$(id -u)" != "0" ]; then
   echo "This script must be run as root"
   exit 1
fi

usage() {
cat << USAGE
Syntax
    OSinstall.sh -T {type} -s { network size } -n {number of networks} -p {public interface} -P {private interface} -f {floating_range} -F {fixed_range} -V {VLAN start} -C {Controller Address} -A {admin} -v {qemu | kvm} -t {default tenancy}

    -T: Installation type: all (single node) | controller | compute
    -s: Network size (IP address range on this network)
    -n: Number of networks to create
    -P: Public network interface
    -F: Floating (Public) IP range
    -p: Private network interface
    -f: Fixed (Private) IP range e.g. 10.0.0.0/8
    -V: VLAN Start
    -C: Cloud Controller Address (if left blank, will work it out but is required for node installs)
    -A: Admin username
    -v: Virtualization type: qemu for software, kvm for kvm (hardware)
    -t: Tenancy (Project)
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
--sql_connection=mysql://nova:${MYSQL_PASS}@${CC_ADDR}/nova
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
--keystone_ec2_url=http://${CC_ADDR}:5000/v2.0/tokens
--multi_host
--send_arp_for_ha
EOF

	cp configs/api-paste.ini /tmp
	sed -i "s/%CC_ADDR%/$CC_ADDR/g" /tmp/api-paste.ini
	sed -i "s/%SERVICE_TENANT_NAME%/$TENANCY/g" /tmp/api-paste.ini
	rm -f /etc/nova/api-paste.ini
	cp /tmp/api-paste.ini /etc/nova/api-paste.ini
	rm -f /tmp/api-paste.ini
}

mysql_install() {
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

glance_install() {
	# Configure glance configs
	# Grab from local github repo
	TMPAREA=/tmp/glance_OSI
	rm -rf $TMPAREA
	mkdir -p $TMPAREA
	cp configs/glance* $TMPAREA

	# Configure files (sed info in)
	sed -i "s/%CC_ADDR%/$CC_ADDR/g" $TMPAREA/*.*
	sed -i "s/%ADMIN_TOKEN%/$KEYSTONE_ADMIN_TOKEN/g" $TMPAREA/*.*
	sed -i "s/%MYSQL_PASS%/$MYSQL_PASS/g" $TMPAREA/*.*

	# Put in place
	rm -f /etc/glance/glance.*
	mkdir -p /etc/glance
	cp $TMPAREA/* /etc/glance

	stop glance-registry
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
	sed -i "s/%CC_ADDR%/$CC_ADDR/g" $TMPAREA/*.*
	sed -i "s/%MYSQL_PASS%/$MYSQL_PASS/g" $TMPAREA/*.*

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
	mkdir -p /var/www/.novaclient
	chown www-data /var/www/.novaclient
}

LOGFILE=/var/log/nova/nova-install.log
mkdir -p /var/log/nova
touch /var/log/nova/nova-install.log

# Defaults
DEFAULT_ADMIN=demo
DEFAULT_KEYSTONE_ADMIN_TOKEN=999888777666
DEFAULT_NETWORK_SIZE=64
DEFAULT_NUM_NETWORKS=1
DEFAULT_VMNET="10.0.0.0/8"
DEFAULT_MYSQL_PASS="openstack"
DEFAULT_PUBLIC_INTERFACE=eth1
DEFAULT_PRIVATE_INTERFACE=eth0
DEFAULT_VLAN_START=100
DEFAULT_VIRT="qemu"
DEFAULT_INSTALL="all"
DEFAULT_TENANCY="demo"


# Process Command Line
while getopts T:N:s:n:p:f:P:F:V:C:A:v:t:hy opts
do
  case $opts in
    T)
	INSTALL=$(echo "${OPTARG}" | tr [A-Z] [a-z])
	case ${INSTALL} in
		all|single|controller|compute|node)
		;;
	*)
		usage
		;;
	esac
	;;
    s)
	NETWORK_SIZE=${OPTARG}
        ;;
    n)
	NUM_NETWORKS=${OPTARG}
	;;
    P)
	PUBLIC_INTERFACE=${OPTARG}
	;;
    F)
	FLOATING_RANGE=${OPTARG}
	;;
    p)
	PRIVATE_INTERFACE=${OPTARG}
	;;
    f)
	VMNET=${OPTARG}
	;;
    V)
	VLAN_START=${OPTARG}
	;;
    C)
	CC_ADDR=${OPTARG}
	;;
    A)
	ADMIN=${OPTARG}
	;;
    v)
	VIRT=${OPTARG}
	;;
    t)
	TENANCY=${OPTARG}
	;;
    y)
	AUTO=1
	;;
    h)
	usage
	;;
  esac
done


# Check defaults / parameters passed to it

if [ -z ${VMNET} ]
then
	VMNET=${DEFAULT_VMNET}
fi

if [ -z ${ADMIN} ]
then
	ADMIN=${DEFAULT_ADMIN}
fi

if [ -z ${MYSQL_PASS} ]
then
	MYSQL_PASS=${DEFAULT_MYSQL_PASS}
fi

if [ -z ${NETWORK_SIZE} ]
then
	NETWORK_SIZE=${DEFAULT_NETWORK_SIZE}
fi

if [ -z ${NUM_NETWORKS} ]
then
	NUM_NETWORKS=${DEFAULT_NUM_NETWORKS}
fi

if [ -z ${PUBLIC_INTERFACE} ]
then
	PUBLIC_INTERFACE=${DEFAULT_PUBLIC_INTERFACE}
fi

if [ -z ${PRIVATE_INTERFACE} ]
then
	PRIVATE_INTERFACE=${DEFAULT_PRIVATE_INTERFACE}
fi

if [ -z ${VLAN_START} ]
then
	VLAN_START=${DEFAULT_VLAN_START}
fi

if [ -z ${VIRT} ]
then
	VIRT=${DEFAULT_VIRT}
fi

if [ -z ${TENANCY} ]
then
	TENANCY=${DEFAULT_TENANCY}
fi

if [ -z ${KEYSTONE_ADMIN_TOKEN} ]
then
	KEYSTONE_ADMIN_TOKEN=${DEFAULT_KEYSTONE_ADMIN_TOKEN}
fi

if [ -z ${INSTALL} ]
then
	INSTALL=${DEFAULT_INSTALL}
fi

# Work out DEFAULT_FLOATING from public interface
_NETWORK=$(/sbin/route -n | grep ${PUBLIC_INTERFACE} | egrep -v UG | awk '{print $1}')
_NETMASK=$(/sbin/route -n | grep ${PUBLIC_INTERFACE} | egrep -v UG | awk '{print $3}')
_CIDR=$(mask2cidr $_NETMASK)
DEFAULT_FLOATING="$_NETWORK/$_CIDR"

if [ -z ${FLOATING_RANGE} ]
then
	FLOATING_RANGE=${DEFAULT_FLOATING}
fi


if [ -z ${CC_ADDR} ]
then
	# Check we're not a compute node install
	case ${INSTALL} in
		all|single|controller)
			# DEFAULT_PUBLIC_INTERFACE=$(/sbin/route -n | grep ^0\.0\.0\.0 | awk '{print $8}')
			CC_ADDR=$(/sbin/ifconfig ${PUBLIC_INTERFACE} | awk '/inet addr/ {split ($2,A,":"); print A[2]}')

			if [ -z ${CC_ADDR} ]
                        then
                                echo "Error, no IP set for ${PUBLIC_INTERFACE}, your Public API interface you've chosen."
                                exit 1
                        fi


			;;
		*)
			echo 
			echo "You must specify the Cloud Controller Address (-C xxx.xxx.xxx.xxx) for a compute node install"
			echo
			exit 1
			;;
	esac
fi
		

# Verification (if -y isn't specified)
cat << CONFIG
OpenStack Essex Release: OpenStack with Keystone and Glance

OpenStack will be installed with these options:

  Installation: ${INSTALL}
  Networking: VLAN (${VLAN_START})
  Private Interface = ${PRIVATE_INTERFACE}
  >> Private Network: ${VMNET} ${NUM_NETWORKS} ${NETWORK_SIZE}
  Public Interface = ${PUBLIC_INTERFACE}
  >> Public Floating network = ${FLOATING_RANGE}
  Cloud Controller (API, Keystone + Glance) = ${CC_ADDR}
  Virtualization Type: ${VIRT}

  Note: The larger the public floating range, the longer it takes to create the entries
        Stick to a /24 to create 256 entries in test environments with the -F parameter

  Account Credentials
	Tenancy: admin
	Role: Admin
	Credentials: admin:admin

	Tenancy: ${TENANCY}
	Role: Member, Admin
	Credentials ${ADMIN}:${TENANCY}
CONFIG

if [ -z ${AUTO} ]
then
	echo "Are you sure you want to continue? [Y/n]"
	read YESNO
	if [ "${YESNO}" = "n" ]
	then
		echo "Aborting!"
		exit 1
	fi
fi

# Libc6 Presents an interactive session question - override
cat <<LIBC6_PRESEED | debconf-set-selections
libc6   glibc/upgrade   boolean true
libc6:amd64     glibc/upgrade   boolean true
libc6   libraries/restart-without-asking        boolean true
libc6:amd64     libraries/restart-without-asking        boolean true
LIBC6_PRESEED


# Required for workaround to stop dbconfig interrupting keystone install
cat <<DBCONFIG_PRESEED | debconf-set-selections
keystone	keystone/dbconfig-install	boolean	false
keystone	keystone/dbconfig-reinstall	boolean	false
dbconfig-common	dbconfig-common/purge	boolean	false
DBCONFIG_PRESEED


# Packages to install per install type
case ${INSTALL} in
	all|single)
		NOVA_PACKAGES="nova-api nova-objectstore nova-scheduler nova-network nova-compute glance keystone openstack-dashboard memcached"
		EXTRA_PACKAGES="euca2ools unzip qemu ntp python-dateutil"
		MYSQL_INSTALL=1
		GLANCE_INSTALL=1
		KEYSTONE_INSTALL=1
		RABBITMQ_INSTALL=1
		HORIZON_INSTALL=1
		;;
	controller)
		NOVA_PACKAGES="nova-api nova-objectstore nova-scheduler nova-network nova-compute glance keystone openstack-dashboard memcached"
		EXTRA_PACKAGES="euca2ools unzip qemu ntp python-dateutil"
		MYSQL_INSTALL=1
		GLANCE_INSTALL=1
		KEYSTONE_INSTALL=1
		RABBITMQ_INSTALL=1
		HORIZON_INSTALL=1
		;;
	compute|node)
		NOVA_PACKAGES="nova-compute nova-network python-keystone"
		EXTRA_PACKAGES="euca2ools unzip qemu ntp python-dateutil"
		;;
esac

# All installation types need to do the following
echo "Setting up repos and installing software"

# For Essex, this is part of Ubuntu 12.04
if [ $(lsb_release -r | awk '{print $2}') != "12.04" ]
then
	apt-get install -y python-software-properties 2>&1 >> ${LOGFILE}
	echo "Not running Ubuntu Precise Pangolin 12.04, add Essex Trunk PPA" >> ${LOGFILE}
	add-apt-repository ppa:openstack-core/trunk 2>&1 >> ${LOGFILE}
fi
apt-get update 2>&1 >> ${LOGFILE}

# Install based on type
if [ ! -z ${RABBITMQ_INSTALL} ]
then
	apt-get install -y rabbitmq-server 2>&1 >> ${LOGFILE}
fi



apt-get install -y ${NOVA_PACKAGES} ${EXTRA_PACKAGES} 2>&1 >> ${LOGFILE}


# Configure Nova Conf
configure_nova

if [ ! -z ${MYSQL_INSTALL} ]
then
	mysql_install
fi

if [ ! -z ${GLANCE_INSTALL} ]
then
	glance_install
fi

if [ ! -z ${KEYSTONE_INSTALL} ]
then
	keystone_install
fi

if [ ! -z ${HORIZON_INSTALL} ]
then
	horizon_install
fi


case ${INSTALL} in
	"all"|"single")
		# Configure the networking for this environment
		echo "Configuring OpenStack VM Network: ${VMNET} ${NUM_NETWORKS} ${NETWORK_SIZE}"
		nova-manage db sync
		nova-manage network create vmnet --fixed_range_v4=${VMNET} --network_size=${NETWORK_SIZE} --bridge_interface=${PRIVATE_INTERFACE}
		nova-manage floating create --ip_range=${FLOATING_RANGE}
		service libvirt-bin restart 2>&1 >> ${LOGFILE}
		;;
	"controller")
		# Configure the networking for this environment
		echo "Configuring OpenStack VM Network: ${VMNET} ${NUMBER_NETWORKS} ${NETWORK_SIZE}"
		nova-manage db sync
		nova-manage network create ${VMNET} ${NUM_NETWORKS} ${NETWORK_SIZE}
		nova-manage floating create --ip_range=${FLOATING_RANGE}
		service libvirt-bin restart 2>&1 >> ${LOGFILE}
		;;
	"compute"|"node")
		nova-manage db sync
		service libvirt-bin restart 2>&1 >> ${LOGFILE}
		;;
esac

# Ubuntu has a permission issue at the mo... https://bugs.launchpad.net/nova/+bug/956876
# Tiny workaround
if [[ -d /var/lib/nova ]]
then
        chown -R nova:nova /var/lib/nova
fi


echo "Restarting service to finalize changes..."

if [ ! -z ${KEYSTONE_INSTALL} ]
then
	stop keystone 2>&1 >> ${LOGFILE}
	start keystone 2>&1 >> ${LOGFILE}
fi

if [ ! -z ${GLANCE_INSTALL} ]
then
	stop glance-api 2>&1 >> ${LOGFILE}
	stop glance-registry 2>&1 >> ${LOGFILE}
	start glance-api 2>&1 >> ${LOGFILE}
	start glance-registry 2>&1 >> ${LOGFILE}
fi

for P in $(ls /etc/init/nova* | cut -d'/' -f4 | cut -d'.' -f1)
do
	stop ${P} 2>&1 >> ${LOGFILE}
	start ${P} 2>&1 >> ${LOGFILE}
done



# Instructions
case ${INSTALL} in
	"compute"|"node")
	HOST=$(hostname -s)
	MYIP=$(/sbin/ifconfig eth0 | awk '/inet addr/ {split ($2,A,":"); print A[2]}')
cat << INSTRUCTIONS
Ensure that the following is in DNS or in /etc/hosts

# Host Entry to ensure controller can find compute node via hostname
${MYIP} ${HOST} 

INSTRUCTIONS
		;;
	*)
cat << INSTRUCTIONS
To set up your environment and a test VM execute the following:

    Upload a test Ubuntu image:
      ./upload_ubuntu.sh -a admin -p openstack -t ${TENANCY} -C ${CC_ADDR}

    Setting up user environment
      Copy over the ${ADMIN}rc file created in this directory to your client
      Source in the ${ADMIN}rc file:   . ${ADMIN}rc

    Add a keypair to your environment so you can access the guests using keys:
      euca-add-keypair $ADMIN > $ADMIN.pem
      chmod 0600 $ADMIN.pem

    Set the security group defaults (iptables):
      euca-authorize default -P tcp -p 22 -s 0.0.0.0/0
      euca-authorize default -P tcp -p 80 -s 0.0.0.0/0
      euca-authorize default -P tcp -p 8080 -s 0.0.0.0/0
      euca-authorize default -P icmp -t -1:-1


    *****************************************************
    To run, check, connect and terminate an instance
      euca-run-instances \$emi -k $ADMIN -t m1.tiny

      euca-describe-instances

      ssh -i $ADMIN.pem root@ipaddress

      euca-terminate-instances instanceid
    *****************************************************

INSTRUCTIONS
		;;
esac
