#!/bin/bash

#    OpenStackInstaller - Bash script installer for Openstack
#    Kevin Jackson, 2012
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

CONFIG=$(PWD)/configuration

# Check we're running as root
if [ "$(id -u)" != "0" ]; then
   echo "This script must be run as root"
   exit 1
fi

# Source in functions
. functions/functions.sh


LOGFILE=/var/log/nova/nova-install.log
mkdir -p /var/log/nova
touch /var/log/nova/nova-install.log

# Defaults
# Source in defaults
. ./defaults

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

CC_ADDR=""

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
	
if [ -z ${MYSQL_ADDR} ]
then
    MYSQL_ADDR=${CC_ADDR}
fi


# Verification (if -y isn't specified)
cat << CONFIG
OpenStack will be installed with these options:

  Installation: ${INSTALL}

  # Networking
  Public Interface = ${PUBLIC_INTERFACE}
  >> Public Floating network = ${FLOATING_RANGE}
  
  Tenant ${TENANCY} Network Details
  Networking: VLAN (${VLAN_START})
  Private Interface = ${PRIVATE_INTERFACE}
  >> Private Network: ${VMNET} ${NUM_NETWORKS} ${NETWORK_SIZE}

  # Services
  Cloud Controller (API, Keystone + Glance) = ${CC_ADDR}
  MySQL Address = ${MYSQL_ADDR}
  Virtualization Type: ${VIRT}

  Accounts
	Administrator
	=============
	Username: admin
	Password: ${DEFAULT_USER_PASSWORD}
	Role: Admin

	Example User
	============
	Username: ${ADMIN}
	Password: ${DEFAULT_USER_PASSWORD}
	Role: Member, Admin
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
		NOVA_PACKAGES="nova-api nova-objectstore nova-scheduler nova-network nova-compute nova-cert glance keystone openstack-dashboard memcached python-memcache novnc nova-consoleauth nova-console"
		EXTRA_PACKAGES="euca2ools unzip qemu ntp python-dateutil"
		MYSQL_INSTALL=1
		GLANCE_INSTALL=1
		KEYSTONE_INSTALL=1
		RABBITMQ_INSTALL=1
		HORIZON_INSTALL=1
		;;
	controller)
		NOVA_PACKAGES="nova-api nova-objectstore nova-scheduler nova-network nova-compute nova-cert glance keystone openstack-dashboard memcached python-memcache novnc nova-consoleauth nova-console"
		EXTRA_PACKAGES="euca2ools unzip qemu ntp python-dateutil"
		MYSQL_INSTALL=1
		GLANCE_INSTALL=1
		KEYSTONE_INSTALL=1
		RABBITMQ_INSTALL=1
		HORIZON_INSTALL=1
		;;
	compute|node)
		NOVA_PACKAGES="nova-compute nova-network nova-api python-keystone"
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
	# If -M was specified then skip to remote_mysql_install
	if  [[ ${LOCAL_MYSQL_INSTALL} -eq 1  ]]
	then
		local_mysql_install
	else
		remote_mysql_install
	fi
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
	"all"|"single"|"controller")
		# Configure the networking for this environment
		echo "Configuring OpenStack VM Network: ${VMNET} ${NUM_NETWORKS} ${NETWORK_SIZE}"
		nova-manage db sync
		nova-manage network create vmnet --fixed_range_v4=${VMNET} --network_size=${NETWORK_SIZE} --bridge_interface=${PRIVATE_INTERFACE}
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
