#!/bin/sh

set -eux

ROOTFS=$1
FW_VERSION=${2:-""}

# Extract major.minor version for comparison
get_version_parts() {
    echo "$1" | cut -d '.' -f 1,2
}

# Check if firmware version is >= 3.12
should_skip_dhcpcd() {
    if [ -z "$FW_VERSION" ]; then
        return 1  # Don't skip if no version provided
    fi

    version_parts=$(get_version_parts "$FW_VERSION")
    major=$(echo "$version_parts" | cut -d '.' -f 1)
    minor=$(echo "$version_parts" | cut -d '.' -f 2)

    if [ "$major" -gt 3 ] || ([ "$major" -eq 3 ] && [ "$minor" -ge 12 ]); then
        return 0  # Skip dhcpcd modification
    else
        return 1  # Don't skip
    fi
}

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

mount /dev/sda4 /home
cp-a /etc/skel /home/root

ln-s /dev/null /etc/systemd/system/remarkable-fail.service

GFS

# Handle dhcpcd.service modification for firmware versions < 3.12
if ! should_skip_dhcpcd; then
    echo "Modifying dhcpcd.service for firmware version $FW_VERSION"
    guestfish --rw --add rootfs.qcow2 <<DHCPCD_GFS
run
mount /dev/sda2 /
download /lib/systemd/system/dhcpcd.service /tmp/dhcpcd.service
! sed -i 's/wlan/eth/' /tmp/dhcpcd.service
upload /tmp/dhcpcd.service /lib/systemd/system/dhcpcd.service
DHCPCD_GFS
else
    echo "Skipping dhcpcd.service modification for firmware version $FW_VERSION (>= 3.12)"
fi
