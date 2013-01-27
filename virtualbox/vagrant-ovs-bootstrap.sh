#!/bin/bash

# Ensure git is installed
sudo apt-get update
sudo apt-get -y install git

# git clone OpenStackInstaller
git clone https://github.com/uksysadmin/OpenStackInstaller.git
cd OpenStackInstaller
git checkout grizzly
./install-ovs.sh
