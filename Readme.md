reMarkable 2 Docker image
=========================

This repo contains a docker file for building a container containing an emulator
for the remarkable 2 OS.

Usage
-----

```
> docker build -t rm-docker .
> docker run -it rm-docker
# Lots of boot messages...
Codex Linux 3.1.266-2 reMarkable ttymxc0

reMarkable login:

# Now login using the root account, no password
```

TODO
----

 * Optimize rootfs building, currently lots of diskspace (8G) is used
   * libguestfs and guestfish might help here
 * Fix `/etc/fstab` and `dhcpcd.service`, should also be possible using `guestfish`
 * Volume mount the rootfs image, so changes can be persisted
 * Forward some ports, to enable ssh access
