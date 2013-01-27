#!/bin/bash

# Source in configuration file
if [[ -f openstack.conf ]]
then
        . openstack.conf
else
        echo "Configuration file not found. Please create openstack.conf"
        exit 1
fi

install_mysql() {
	echo "mysql-server-5.5 mysql-server/root_password password $MYSQL_ROOT_PASS" | sudo debconf-set-selections
	echo "mysql-server-5.5 mysql-server/root_password_again password $MYSQL_ROOT_PASS" | sudo debconf-set-selections
	echo "mysql-server-5.5 mysql-server/root_password seen true" | sudo debconf-set-selections
	echo "mysql-server-5.5 mysql-server/root_password_again seen true" | sudo debconf-set-selections

	sudo apt-get -y install mysql-server python-mysqldb
}

configure_mysql() {
	sudo sed -i "s/bind-address.*/bind-address     = $MYSQL_SERVER/" /etc/mysql/my.cnf
	sudo service mysql restart
}

recreate_databases() {
	# MySQL
	# Create database
	for d in nova glance cinder keystone quantum
	do
		mysql -uroot -p$MYSQL_ROOT_PASS -e "drop database if exists $d;"
		mysql -uroot -p$MYSQL_ROOT_PASS -e "create database $d;"
		mysql -uroot -p$MYSQL_ROOT_PASS -e "grant all privileges on $d.* to $d@\"localhost\" identified by \"$MYSQL_DB_PASS\";"
		mysql -uroot -p$MYSQL_ROOT_PASS -e "grant all privileges on $d.* to $d@\"%\" identified by \"$MYSQL_DB_PASS\";"
	done
}

# Main
install_mysql
configure_mysql
recreate_databases
