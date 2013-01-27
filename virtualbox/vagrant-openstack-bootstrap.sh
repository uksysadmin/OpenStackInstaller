#!/bin/bash

# Ensure git is installed
sudo apt-get update
sudo apt-get -y install git

# git clone OpenStackInstaller
git clone https://github.com/uksysadmin/OpenStackInstaller.git
cd OpenStackInstaller
git checkout grizzly
sed -i 's/192.168.1.12/172.16.0.201/g' openstack.conf
./install-grizzly.sh
