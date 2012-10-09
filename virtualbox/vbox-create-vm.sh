#!/bin/bash

# Create VirtualBox Machine
VboxManage createvm --name openstack1 --ostype Ubuntu_64 --register
VBoxManage modifyvm openstack1 --memory 2048 --nic1 nat --nic2 hostonly --hostonlyadapter2 vboxnet0 --nic3 hostonly --hostonlyadapter3 vboxnet1

# Create CD-Drive and Attach ISO
VBoxManage storagectl openstack1 --name "IDE Controller" --add ide --controller PIIX4 --hostiocache on --bootable on VBoxManage storageattach openstack1 --storagectl "IDE Controller" --type dvddrive --port 0 --device 0 --medium Downloads/ubuntu-12.04-server-amd64.iso

# Create and attach SATA Interface and Hard Drive
VBoxManage storagectl openstack1 --name "SATA Controller" --add sata --controller IntelAHCI --hostiocache on --bootable on 
VBoxManage createhd --filename openstack1.vdi --size 20480 
VBoxManage storageattach openstack1 --storagectl "SATA Controller" --port 0 --device 0 --type hdd --medium openstack1.vdi


