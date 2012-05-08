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

DIR=$(dirname $(basename $0))
CONFIG=${DIR}/configuration


# Source in functions
. ${DIR}/functions/functions.sh

# Defaults
# Source in defaults
. ${DIR}/defaults

# Process Command Line
while getopts N:s:n:p:f:P:F:V:C:A:v:t:M:h opts
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
    M)
	MYSQL_ADDR=${OPTARG}
	LOCAL_MYSQL_INSTALL=0
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
_NETWORK=$(/sbin/route -n | grep ${PUBLIC_INTERFACE} | egrep -v -e "UG" -e "169\.254" | awk '{print $1}')
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

# Check if configuration file exists already - if so, ask to overwrite


cat << CONFIG
OpenStack will be configured with these options:

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

  Administrator
  =============
  Username: admin
  Password: ${DEFAULT_USER_PASSWORD}
  Role: Admin

  Example User
  ============
  Username: ${ADMIN}
  Password: ${DEFAULT_USER_PASSWORD}
  Role: Member

CONFIG

if [[ -f $CONFIG ]]
then
	# Ask user to overwrite config file?
        echo "Configuration already exists, overwrite? [y/N]"
        read YESNO
	A=$(echo $YESNO | tr '[A-Z]' '[a-z]')
        if [ "${A}" = "y" ]
        then
                echo "Overwriting!"
	else
		echo "Aborting!"
		exit 1
        fi
fi	

# Write out $CONFIG
cat > $CONFIG << EOF
NETWORK_SIZE=${NETWORK_SIZE}
NUM_NETWORKS=${NUM_NETWORKS}
PUBLIC_INTERFACE=${PUBLIC_INTERFACE}
FLOATING_RANGE=${FLOATING_RANGE}
PRIVATE_INTERFACE=${PRIVATE_INTERFACE}
VMNET=${VMNET}
VLAN_START=${VLAN_START}
CC_ADDR=${CC_ADDR}
USER=${USER}
VIRT=${VIRT}
TENANCY=${TENANCY}
MYSQL_ADDR=${MYSQL_ADDR}
LOCAL_MYSQL_INSTALL=${LOCAL_MYSQL_INSTALL}
MYSQL_PASS=${MYSQL_PASS}
KEYSTONE_ADMIN_TOKEN=${KEYSTONE_ADMIN_TOKEN}
EOF
