#!/bin/bash

# Source in configuration file
if [[ -f openstack.conf ]]
then
        . openstack.conf
else
        echo "Configuration file not found. Please create openstack.conf"
        exit 1
fi

configure_package_archive() {
	#echo "deb http://ubuntu-cloud.archive.canonical.com/ubuntu precise-updates/folsom main" | sudo tee -a /etc/apt/sources.list.d/folsom.list
	sudo rm -f /etc/apt/sources.list.d/folsom.list
	echo "deb http://ubuntu-cloud.archive.canonical.com/ubuntu precise-proposed/folsom main" | sudo tee -a /etc/apt/sources.list.d/folsom.list
	# sudo apt-key adv --recv-keys --keyserver keyserver.ubuntu.com 5EDB1B62EC4926EA
	sudo apt-get -y install ubuntu-cloud-keyring
	sudo apt-get update
	echo "grub-pc grub-pc/install_devices multiselect /dev/sda" | sudo debconf-set-selections
	echo "grub-pc grub-pc/install_devices_disks_changed multiselect /dev/sda" | sudo debconf-set-selections
	sudo apt-get -y upgrade
}

install_base_packages() {
	sudo apt-get -y install vlan bridge-utils ntp python-mysqldb
}

system_tuning() {
	sudo sed -i 's/^#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/g' /etc/sysctl.conf
	# Set OVS_EXTERNAL_INTERFACE up properly
	sudo ifconfig $OVS_EXTERNAL_INTERFACE 0.0.0.0 up
	sudo ifconfig $OVS_EXTERNAL_INTERFACE promisc
}

# Main
configure_package_archive
install_base_packages
system_tuning
