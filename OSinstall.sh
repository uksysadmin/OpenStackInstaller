#!/bin/bash

#    Author K. Jackson (kevin@linuxservices.co.uk) 18 Feb 2011
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
    OSinstall.sh -T {type} -N {private virtual network w/subnet} -s { network size } -n {number of networks} -I {public interface} -C {Controller Address} -A {admin} -v {qemu | kvm}

    -T: Installation type: all (single node) | controller | compute
    -N: Private network the guests will use with subnet
	e.g. 10.0.0.0/8
    -s: Network size (IP address range on this network)
    -n: Number of networks to create
    -I: Public network interface
    -C: Cloud Controller Address (if left blank, will work it out but is required for node installs)
    -A: Admin username
    -v: Virtualization type: qemu for software, kvm for kvm (hardware)
USAGE
exit 1
}

LOGFILE=/var/log/nova/nova-install.log
mkdir -p /var/log/nova
touch /var/log/nova/nova-install.log

# Defaults
DEFAULT_ADMIN=kevinj
DEFAULT_NETWORK_SIZE=64
DEFAULT_NUM_NETWORKS=1
DEFAULT_VMNET="10.0.0.0/8"
DEFAULT_MYSQL_PASS="nova"
DEFAULT_INTERFACE=eth0
DEFAULT_VIRT="qemu"
DEFAULT_INSTALL="all"

# Process Command Line
while getopts T:N:s:n:I:C:A:v:hy opts
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
    N)
	VMNET=${OPTARG}
	;;
    s)
	NETWORK_SIZE=${OPTARG}
        ;;
    n)
	NUM_NETWORKS=${OPTARG}
	;;
    I)
	INTERFACE=${OPTARG}
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

if [ -z ${INTERFACE} ]
then
	INTERFACE=${DEFAULT_INTERFACE}
fi

if [ -z ${VIRT} ]
then
	VIRT=${DEFAULT_VIRT}
fi

if [ -z ${INSTALL} ]
then
	INSTALL=${DEFAULT_INSTALL}
fi

if [ -z ${CC_ADDR} ]
then
	# Check we're not a compute node install
	case ${INSTALL} in
		all|single|controller)
			# DEFAULT_INTERFACE=$(/sbin/route -n | grep ^0\.0\.0\.0 | awk '{print $8}')
			CC_ADDR=$(/sbin/ifconfig ${INTERFACE} | awk '/inet addr/ {split ($2,A,":"); print A[2]}')

			if [ -z ${CC_ADDR} ]
                        then
                                echo "Error, no IP set for ${INTERFACE}, your Public API interface you've chosen."
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
OpenStack will be installed with these options:

  Installation: ${INSTALL}
  Admin user: ${ADMIN}
  Private Network: ${VMNET} ${NUM_NETWORKS} ${NETWORK_SIZE}
  Public Interface = ${INTERFACE}
  Cloud Controller = ${CC_ADDR}
  Virtualization Type: ${VIRT}

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

# Packages to install per install type
case ${INSTALL} in
	all|single)
		NOVA_PACKAGES="nova-api nova-objectstore nova-scheduler nova-network nova-compute"
		EXTRA_PACKAGES="euca2ools unzip qemu"
		MYSQL_INSTALL=1
		RABBITMQ_INSTALL=1
		;;
	controller)
		NOVA_PACKAGES="nova-api nova-objectstore nova-scheduler nova-network nova-compute"
		EXTRA_PACKAGES="euca2ools unzip qemu"
		MYSQL_INSTALL=1
		RABBITMQ_INSTALL=1
		;;
	compute|node)
		NOVA_PACKAGES="nova-compute"
		EXTRA_PACKAGES="euca2ools unzip qemu"
		;;
esac

# All installation types need to do the following
echo "Setting up repos and installing software"
apt-get install -y python-software-properties 2>&1 >> ${LOGFILE}
#add-apt-repository ppa:nova-core/trunk 2>&1 >> ${LOGFILE}
add-apt-repository ppa:openstack-release/2011.2 2>&1 >> ${LOGFILE}
apt-get update 2>&1 >> ${LOGFILE}

# Install based on type
if [ ! -z ${RABBITMQ_INSTALL} ]
then
	apt-get install -y rabbitmq-server 2>&1 >> ${LOGFILE}
fi

apt-get install -y ${NOVA_PACKAGES} ${EXTRA_PACKAGES} 2>&1 >> ${LOGFILE}


# Configure the /etc/nova/nova.conf file
cat > /etc/nova/nova.conf << EOF
--daemonize=1
--dhcpbridge_flagfile=/etc/nova/nova.conf
--dhcpbridge=/usr/bin/nova-dhcpbridge
--logdir=/var/log/nova
--state_path=/var/lib/nova
--verbose
--libvirt_type=${VIRT}
--sql_connection=mysql://root:nova@${CC_ADDR}/nova
--s3_host=${CC_ADDR}
--rabbit_host=${CC_ADDR}
--ec2_host=${CC_ADDR}
--ec2_url=http://${CC_ADDR}:8773/services/Cloud
--fixed_range=${VMNET}
--network_size=${NETWORK_SIZE}
--num_networks=${NUM_NETWORKS}
--FAKE_subdomain=ec2
--public_interface=${INTERFACE}
--state_path=/var/lib/nova
--lock_path=/var/lock/nova
EOF

if [ ! -z ${MYSQL_INSTALL} ]
then
	echo "Configuring MySQL for OpenStack"

	# MySQL
	MYSQL_PASS=nova
	cat <<MYSQL_PRESEED | debconf-set-selections
mysql-server-5.1 mysql-server/root_password password $MYSQL_PASS
mysql-server-5.1 mysql-server/root_password_again password $MYSQL_PASS
mysql-server-5.1 mysql-server/start_on_boot boolean true
MYSQL_PRESEED
	apt-get install -y mysql-server 2>&1 >> ${LOGFILE}
	sed -i 's/127.0.0.1/0.0.0.0/g' /etc/mysql/my.cnf
	service mysql restart
	mysql -uroot -p$MYSQL_PASS -e 'CREATE DATABASE nova;'
	mysql -uroot -p$MYSQL_PASS -e "GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' WITH GRANT OPTION;"
	mysql -uroot -p$MYSQL_PASS -e "SET PASSWORD FOR 'root'@'%' = PASSWORD('$MYSQL_PASS');"
fi


case ${INSTALL} in
	"all"|"single")
		# Configure the networking for this environment
		echo "Configuring OpenStack VM Network: ${VMNET} ${NUMBER_NETWORKS} ${NETWORK_SIZE}"
		nova-manage db sync
		nova-manage network create ${VMNET}
		service libvirt-bin restart 2>&1 >> ${LOGFILE}
		;;
	"controller")
		# Configure the networking for this environment
		echo "Configuring OpenStack VM Network: ${VMNET} ${NUMBER_NETWORKS} ${NETWORK_SIZE}"
		nova-manage db sync
		nova-manage network create ${VMNET}
		service libvirt-bin restart 2>&1 >> ${LOGFILE}
		;;
	"compute"|"node")
		nova-manage db sync
		service libvirt-bin restart 2>&1 >> ${LOGFILE}
		;;
esac

echo "Restarting service to finalize changes..."

for P in ${NOVA_PACKAGES}
do
 service ${P} restart 2>&1 >> ${LOGFILE}
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
  sudo nova-manage user admin ${ADMIN}
  sudo nova-manage project create myproject ${ADMIN}
  sudo nova-manage project zipfile myproject ${ADMIN}
  mkdir -p cloud/creds
  cd cloud/creds
  unzip ~${ADMIN}/nova.zip
  . novarc
  cd


Example test UEC image:
  wget http://smoser.brickies.net/ubuntu/ttylinux-uec/ttylinux-uec-amd64-12.1_2.6.35-22_1.tar.gz
  uec-publish-tarball ttylinux-uec-amd64-12.1_2.6.35-22_1.tar.gz mybucket

Add a keypair to your environment so you can access the guests using keys:
  euca-add-keypair openstack > cloud/creds/openstack.pem
  chmod 0600 cloud/creds/*

Set the security group defaults (iptables):
  euca-authorize default -P tcp -p 22 -s 0.0.0.0/0
  euca-authorize default -P tcp -p 80 -s 0.0.0.0/0
  euca-authorize default -P tcp -p 8080 -s 0.0.0.0/0
  euca-authorize default -P icmp -t -1:-1


*****************************************************
To run, check, connect and terminate an instance
  euca-run-instances \$emi -k openstack -t m1.tiny

  euca-describe-instances

  ssh -i cloud/keys/openstack.pem root@ipaddress

  euca-terminate-instances instanceid
*****************************************************

INSTRUCTIONS
		;;
esac
