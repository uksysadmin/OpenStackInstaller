#!/bin/bash

case $1 in
	"controller")
		# Run the installations
		./install-common.sh 2>&1 >> /tmp/install.log
		./install-mysql.sh 2>&1 >> /tmp/install.log
		./install-keystone.sh 2>&1 >> /tmp/install.log
		./install-glance.sh 2>&1 >> /tmp/install.log
		# ./install-quantum.sh 2>&1 >> /tmp/install.log
		./install-cinder.sh 2>&1 >> /tmp/install.log
		./install-nova.sh 2>&1 >> /tmp/install.log
		./install-horizon.sh 2>&1 >> /tmp/install.log
		# Creates a demo network for the admin tenant
		# Hard coded IPs in script which gets pulled by git for time being
		#if [[ -f adminrc ]]
		#then
		#	. adminrc
		#	./install-quantum-createnetwork.sh 2>&1 >> /tmp/install.log
		#fi
		;;
	"compute")
		# Run the installations
		./install-common.sh 2>&1 >> /tmp/install.log
		# ./install-quantum-agent.sh 2>&1 >> /tmp/install.log
		./install-compute.sh 2>&1 >> /tmp/install.log
		;;
	*)
		echo "Error. Need to specify: controller or compute"
		exit 1
		;;
esac
