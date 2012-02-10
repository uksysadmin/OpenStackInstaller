#!/bin/bash

# Simple script to download Ubuntu Oneiric 11.10 from ubuntu.com
# and publish to cloud environment for use

ARCH=i386
DISTRO=ubuntu
CODENAME=oneiric
VERSION=11.10
TARBALL=${DISTRO}-${VERSION}-server-cloudimg-${ARCH}.tar.gz

TMPAREA=/tmp/__upload

mkdir -p ${TMPAREA}

if [ ! -f ${TMPAREA}/${TARBALL} ]
then
	wget -O ${TMPAREA}/${TARBALL} http://uec-images.ubuntu.com/releases/${CODENAME}/release/${TARBALL}
fi

if [ -f ${TMPAREA}/${TARBALL} ]
then
	cd ${TMPAREA}
	tar zxf ${TARBALL}
	DISTRO_IMAGE=$(ls *-${ARCH}.img)
	DISTRO_KERNEL=$(ls *-${ARCH}-vmlinuz-virtual)

	KERNEL=$(glance -A 999888777666 add name="${DISTRO} ${VERSION} ${ARCH} Kernel" disk_format=aki container_format=aki distro="${DISTRO} ${VERSION}" is_public=true < ${DISTRO_KERNEL} | cut -d':' -f2 | awk '{print $1}')

	AMI=$(glance -A 999888777666 add name="${DISTRO} ${VERSION} ${ARCH} Server" disk_format=ami container_format=ami distro="${DISTRO} ${VERSION}" kernel_id=${KERNEL} is_public=true < ${DISTRO_IMAGE})

	echo "${DISTRO} ${VERSION} ${ARCH} now available in Glance (${AMI})"

	rm -f /tmp/__upload/*{.img,-vmlinuz-virtual,loader,floppy}
else
	echo "Tarball not found!"
fi
