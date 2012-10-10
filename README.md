OpenStackInstaller
==================

Now with added Folsom! Bring out the gimp! :)

VAGRANT + VIRTUALBOX
====================
Check out this post on using these installation scripts with Vagrant and VirtualBox http://uksysadmin.wordpress.com/2012/10/09/easy-openstack-folsom-with-virtualbox-and-vagrant/

1. Check out these scripts using Git
2. Check out the 'folsom' branch
3. Change to the 'virtualbox' directory
4. Type: 'vagrant up'

- Explore the scripts and Vagrantfile to ensure the settings match your environment

ON REAL HARDWARE...
===================
If you prefer to do it for real...

GETTING READY
=============
Create a VM or have available a server with specs similar to below:

        * 2vCPU
        * 2048 Mb Ram
        * 20Gb Hard Disk (/dev/sda)
	* 20Gb Hard Disk (/dev/sdb) for Cinder
        * 2 Nics - eth0 Public, eth1 Private



HOW TO DO IT
============
1. Clone the OpenStackInstaller

        * $ git clone https://github.com/uksysadmin/OpenStackInstaller.git

2. Check out the 'folsom' branch

        * $ cd OpenStackInstaller
        * $ git checkout folsom

3. Edit 'openstack.conf' file that describes your environment. By default this is defined as follows:

        * eth0 has been defined as 192.168.1.12/16
        * eth1 will be your private interface
        * Quantum will be used (need to tidy up configs on this)
        * Private range defined: 10.0.0.0/24
        * Floating range is 192.168.2.0/24
        * Hardware virtualization is defined (kvm)
	* Installation will partition /dev/sdb and create LVM volume by default

	Note: To disable Cinder creating a partition on /dev/sdb comment out:

	CINDER_DEVICE=/dev/sdb

	WARNING! Do NOT set this to be your boot disk, e.g. /dev/sda

4. Run the installer:

        * $ ./install-folsom.sh

   This will ask you for the password of the current user to gain sudo privileges

5. Once complete:

        * $ sudo nova-manage service list

        * http://192.168.1.12/horizon


Kevin Jackson http://about.me/kevjackson

THANKS
======
Huge thanks to Atul Jha (koolhead17) and Emilien Macchi (EmilenM) post http://my1.fr/blog/first-guide-to-deploy-openstack-folsom-on-ubuntu-12-04/
