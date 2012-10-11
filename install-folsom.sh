#!/bin/bash

# Run the installations
./folsom-common.sh
./folsom-keystone.sh
./folsom-glance.sh
./folsom-quantum.sh
./folsom-cinder.sh
./folsom-nova.sh
./folsom-horizon.sh

# Creates a demo network for the admin tenant
# Hard coded IPs in script which gets pulled by git for time being
if [[ -f adminrc ]]
then
	. adminrc
	./folsom-quantum-createnetwork.sh
fi
