#!/bin/sh

set -eux

ROOTFS=$1

qemu-img create -f raw rootfs.img 8G

sfdisk rootfs.img <<SFD
label: dos
label-id: 0xc410b303
device: /dev/nbd0
unit: sectors
sector-size: 512

/dev/nbd0p1 : start=        2048, size=       40960, type=83
/dev/nbd0p2 : start=       43008, size=      552960, type=83
/dev/nbd0p3 : start=      595968, size=      552960, type=83
/dev/nbd0p4 : start=     1148928, size=    13793280, type=83
SFD

# Create the fat boot partition
dd if=/dev/zero of=boot.img bs=512 count=40960
mkfs.vfat boot.img
dd if=boot.img of=rootfs.img bs=512 count=40960 seek=2048 conv=notrunc
rm boot.img

# Make the home partition
mkfs.ext4 -O ^orphan_file rootfs.img -E offset=$(( 1148928 * 512 )) 6735M

# Copy over the filesystems
dd if=$ROOTFS  of=rootfs.img bs=512 count=552960 seek=43008  conv=notrunc,sparse
# dd if=$ROOTFS  of=rootfs.img bs=512 count=552960 seek=595968 conv=notrunc,sparse

qemu-img convert -f raw -O qcow2 rootfs.img rootfs.qcow2
rm rootfs.img
