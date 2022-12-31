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

if [ $# -lt 1 ]
then
    echo "Using default directory ${OUTDIR} for output"
else
    OUTDIR=$1
    echo "Using passed directory ${OUTDIR} for output"
fi

mkdir -p ${OUTDIR} 

if [ $? -ne 0 ]
then
    echo "fail: The directory ${OUTDIR} could not be created"
    exit 1
fi

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

    make ARCH=${ARCH} \
         CROSS_COMPILE=${CROSS_COMPILE} \
         mrproper
    make ARCH=${ARCH} \
         CROSS_COMPILE=${CROSS_COMPILE} \
         defconfig
    make -j4 \
         ARCH=${ARCH} \
         CROSS_COMPILE=${CROSS_COMPILE} \
         all
    make ARCH=${ARCH} \
         CROSS_COMPILE=${CROSS_COMPILE} \
         modules
    make ARCH=${ARCH} \
         CROSS_COMPILE=${CROSS_COMPILE} \
         dtbs
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

mkdir ${OUTDIR}/rootfs
cd ${OUTDIR}/rootfs
mkdir bin dev etc home lib proc sbin sys tmp usr var
mkdir usr/bin usr/lib usr/sbin
mkdir -p var/log
cd ${OUTDIR}/rootfs
sudo chown -R root:root *

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

sudo make ARCH=${ARCH} \
          CROSS_COMPILE=${CROSS_COMPILE} \
          CONFIG_PREFIX=${OUTDIR}/rootfs \
          PATH=$PATH \
          install

cd ${OUTDIR}/rootfs

echo "Library dependencies"
${CROSS_COMPILE}readelf -a bin/busybox | grep "program interpreter"
${CROSS_COMPILE}readelf -a bin/busybox | grep "Shared library"

SYSROOT=$(${CROSS_COMPILE}gcc -print-sysroot)
echo "SYSROOT=$SYSROOT"

mkdir -p lib64

sudo cp $SYSROOT/lib64/ld-2.31.so        lib64
sudo cp $SYSROOT/lib64/libm-2.31.so      lib64
sudo cp $SYSROOT/lib64/libresolv-2.31.so lib64
sudo cp $SYSROOT/lib64/libc-2.31.so      lib64

sudo cp -a $SYSROOT/lib/ld-linux-aarch64.so.1 lib
sudo cp -a $SYSROOT/lib64/libm.so.6      lib64
sudo cp -a $SYSROOT/lib64/libresolv.so.2 lib64
sudo cp -a $SYSROOT/lib64/libc.so.6      lib64

cd ${OUTDIR}/rootfs
sudo mknod -m 666 dev/null c 1 3
sudo mknod -m 666 dev/console c 5 1

echo "Clean and build the writer utility"
cd ${FINDER_APP_DIR}
make clean
make CROSS_COMPILE=${CROSS_COMPILE} \
     all

sudo cp writer ${OUTDIR}/rootfs/home
sudo cp finder.sh ${OUTDIR}/rootfs/home
sudo cp finder-test.sh ${OUTDIR}/rootfs/home
sudo cp autorun-qemu.sh ${OUTDIR}/rootfs/home
sudo cp conf/username.txt ${OUTDIR}/rootfs/home
sudo cp conf/assignment.txt ${OUTDIR}/rootfs/home

cd ${OUTDIR}/rootfs
sudo chown -R root:root *

find . -print0 | cpio --null --create --verbose --format=newc | gzip > ../initramfs.cpio.gz