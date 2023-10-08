#!/bin/sh

set -eux

ROOTFS=$1
TARGET=$2

mkdir -p "$TARGET"

guestfish --ro --blocksize=512 --add rootfs.ext4 <<GFS
run
mount /dev/sda /
copy-out / $TARGET
GFS

