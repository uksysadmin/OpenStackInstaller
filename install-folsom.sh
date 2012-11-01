#!/bin/bash

# Run the installations
./folsom-common.sh 2>&1 >> /tmp/install.log
./folsom-keystone.sh 2>&1 >> /tmp/install.log
./folsom-glance.sh 2>&1 >> /tmp/install.log
./folsom-quantum.sh 2>&1 >> /tmp/install.log
./folsom-cinder.sh 2>&1 >> /tmp/install.log
./folsom-nova.sh 2>&1 >> /tmp/install.log
./folsom-horizon.sh 2>&1 >> /tmp/install.log

# Creates a demo network for the admin tenant
# Hard coded IPs in script which gets pulled by git for time being
if [[ -f adminrc ]]
then
	. adminrc
	./folsom-quantum-createnetwork.sh 2>&1 >> /tmp/install.log
fi
