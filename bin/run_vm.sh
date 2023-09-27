#!/bin/sh

set -eu

LOAD_STATE=""

if qemu-img snapshot -l /opt/root/rootfs.qcow2 | grep main > /dev/null
then
  LOAD_STATE="-loadvm main"
fi

echo "Staring..."
qemu-system-arm \
    -machine mcimx7d-sabre \
    -cpu cortex-a9 \
    -smp 2 \
    -m 2048 \
    -kernel /opt/zImage \
    -dtb /opt/imx7d-rm.dtb \
    -drive if=sd,file=/opt/root/rootfs.qcow2,format=qcow2,index=2 \
    -append "console=ttymxc0 rootfstype=ext4 root=/dev/mmcblk1p2 rw rootwait init=/sbin/init" \
    -nic user,hostfwd=tcp::22-:22,hostfwd=tcp::8888-:8888 \
    -monitor tcp::5555,server=on,wait=off \
    -parallel null -display none \
    $LOAD_STATE \
    "$@"
