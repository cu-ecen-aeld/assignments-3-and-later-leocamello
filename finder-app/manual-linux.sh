#!/bin/bash
# Script outline to install and build kernel.
# Author: Siddhant Jajoo.

set -e
set -u

OUTDIR=/tmp/aeld
KERNEL_REPO=git://git.kernel.org/pub/scm/linux/kernel/git/stable/linux-stable.git
KERNEL_VERSION=v5.1.10
BUSYBOX_VERSION=1_33_1
FINDER_APP_DIR=$(realpath $(dirname $0))
ARCH=arm64
CROSS_COMPILE=aarch64-none-linux-gnu-
SYSROOT=$(${CROSS_COMPILE}gcc -print-sysroot)

if [ $# -lt 1 ]
then
	echo "Using default directory ${OUTDIR} for output"
else
	OUTDIR=$1
	echo "Using passed directory ${OUTDIR} for output"
fi

mkdir -p ${OUTDIR}

cd "$OUTDIR"
if [ ! -d "${OUTDIR}/linux-stable" ]; then
    #Clone only if the repository does not exist.
	echo "CLONING GIT LINUX STABLE VERSION ${KERNEL_VERSION} IN ${OUTDIR}"
	git clone ${KERNEL_REPO} --depth 1 --single-branch --branch ${KERNEL_VERSION}
fi
if [ ! -e ${OUTDIR}/linux-stable/arch/${ARCH}/boot/Image ]; then
    cd linux-stable
    echo "Checking out version ${KERNEL_VERSION}"
    git checkout ${KERNEL_VERSION}

    echo "Assignment 3 QEMU build - clean"
    make ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} mrproper
    
    echo "Assignment 3 QEMU build - defconfig"
    make ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} defconfig
    
    echo "Assignment 3 QEMU build - vmlinux"
    make -j4 ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} all
    
    echo "Assignment 3 QEMU build - modules"
    make ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} modules
    
    echo "Assignment 3 QEMU build - devicetree"
    make ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} dtbs
fi

echo "Adding the Image in outdir"
cp ${OUTDIR}/linux-stable/arch/${ARCH}/boot/Image ${OUTDIR}

echo "Creating the staging directory for the root filesystem"
cd "$OUTDIR"
if [ -d "${OUTDIR}/rootfs" ]
then
	echo "Deleting rootfs directory at ${OUTDIR}/rootfs and starting over"
    sudo rm  -rf ${OUTDIR}/rootfs
fi

echo "Creating a folder tree"

mkdir ${OUTDIR}/rootfs
cd ${OUTDIR}/rootfs

mkdir bin dev etc home lib lib64 proc sbin sys tmp usr var
mkdir usr/bin usr/lib usr/sbin
mkdir home/conf

mkdir -p var/log

echo "Make the contents owned by root"

cd ${OUTDIR}/rootfs
sudo chown -R root:root *

echo "Building Busybox"
cd "$OUTDIR"
if [ ! -d "${OUTDIR}/busybox" ]
then
    git clone git://busybox.net/busybox.git
    cd busybox
    git checkout ${BUSYBOX_VERSION}

    make distclean
    make defconfig
else
    cd busybox
fi

echo "Installing Busybox"
sudo make ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} CONFIG_PREFIX=${OUTDIR}/rootfs PATH=$PATH install

cd ${OUTDIR}/rootfs

echo "Library dependencies"
${CROSS_COMPILE}readelf -a bin/busybox | grep "program interpreter"
${CROSS_COMPILE}readelf -a bin/busybox | grep "Shared library"

cd ${OUTDIR}/rootfs

echo "Copying Busybox Shared libraries to ${SYSROOT}"
sudo cp -a ${SYSROOT}/lib/ld-linux-aarch64.so.1 lib
sudo cp -a ${SYSROOT}/lib64/ld-2.31.so lib64
sudo cp -a ${SYSROOT}/lib64/libresolv.so.2 lib64
sudo cp -a ${SYSROOT}/lib64/libresolv-2.31.so lib64
sudo cp -a ${SYSROOT}/lib64/libm.so.6 lib64
sudo cp -a ${SYSROOT}/lib64/libm-2.31.so lib64
sudo cp -a ${SYSROOT}/lib64/libc.so.6 lib64
sudo cp -a ${SYSROOT}/lib64/libc-2.31.so lib64

echo "Devices"
cd ${OUTDIR}/rootfs
sudo mknod -m 666 dev/null c 1 3
sudo mknod -m 600 dev/console c 5 1

echo "Building Finder app"
cd ${FINDER_APP_DIR}
make clean
make CROSS_COMPILE=${CROSS_COMPILE} all

echo "Copying Finder app to rootfs home"
sudo cp ${FINDER_APP_DIR}/writer ${OUTDIR}/rootfs/home
sudo cp ${FINDER_APP_DIR}/writer.sh ${OUTDIR}/rootfs/home
sudo cp ${FINDER_APP_DIR}/finder.sh ${OUTDIR}/rootfs/home
sudo cp ${FINDER_APP_DIR}/finder-test.sh ${OUTDIR}/rootfs/home
sudo cp ${FINDER_APP_DIR}/autorun-qemu.sh ${OUTDIR}/rootfs/home

sudo cp ${FINDER_APP_DIR}/conf/assignment.txt ${OUTDIR}/rootfs/home/conf
sudo cp ${FINDER_APP_DIR}/conf/username.txt ${OUTDIR}/rootfs/home/conf

cd ${OUTDIR}/rootfs
sudo chown -R root:root *

cd ${OUTDIR}/rootfs
find . | cpio -H newc -ov --owner root:root > ../initramfs.cpio
cd ..
gzip initramfs.cpio