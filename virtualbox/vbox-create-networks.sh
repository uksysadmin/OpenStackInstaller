#!/bin/bash

# Public Network  vboxnet0 (172.16.0.0/16)
VBoxManage hostonlyif create
VBoxManage hostonlyif ipconfig vboxnet0 --ip 172.16.0.254 --netmask 255.255.0.0

# Private Network vboxnet1 (10.0.0.0/8)
VBoxManage hostonlyif create
VBoxManage hostonlyif ipconfig vboxnet1 --ip 10.0.0.254 --netmask 255.0.0.0
