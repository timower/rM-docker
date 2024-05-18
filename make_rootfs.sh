#!/bin/sh

set -eux

ROOTFS=$1

qemu-img create -f qcow2 rootfs.qcow2 8G

guestfish --rw --blocksize=512 --add rootfs.qcow2 <<GFS
run

part-init /dev/sda mbr
part-add /dev/sda p 2048    43007
part-add /dev/sda p 43008   595967
part-add /dev/sda p 595968  1148927
part-add /dev/sda p 1148928 14942207

mkfs vfat /dev/sda1
upload $ROOTFS /dev/sda2
mkfs ext4 /dev/sda3
mkfs ext4 /dev/sda4

mount /dev/sda2 /

download /etc/fstab /tmp/fstab
! sed -i 's/mmcblk2/mmcblk1/' /tmp/fstab
upload /tmp/fstab /etc/fstab

download /lib/systemd/system/dhcpcd.service /tmp/dhcpcd.service
! sed -i 's/wlan/eth/' /tmp/dhcpcd.service
upload /tmp/dhcpcd.service /lib/systemd/system/dhcpcd.service

mount /dev/sda4 /home
cp-a /etc/skel /home/root

ln-s /dev/null /etc/systemd/system/remarkable-fail.service

GFS

