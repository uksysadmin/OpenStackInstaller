#!/bin/bash

# Really simple (and gung-ho) script to remove OpenStack
apt-get remove nova-compute nova-network nova-api nova-objectstore keystone glance nova-scheduler
mysql -uroot -popenstack -e "drop database nova;"
mysql -uroot -popenstack -e "drop database glance;"
mysql -uroot -popenstack -e "drop database keystone;"
apt-get autoremove
