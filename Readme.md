reMarkable 2 Docker image
=========================

This repo contains a docker file for building a container containing an emulator
for the remarkable 2 OS.

Usage
-----

```
> docker build -t rm-docker .
> docker run --rm -v rm-data:/opt/root -p 2222:22 -it rm-docker
# Lots of boot messages...
Codex Linux 3.1.266-2 reMarkable ttymxc0

reMarkable login:

# Now login using the root account, no password
# Or ssh:
ssh root@localhost -p 2222
```

TODO
----

 * Add rm2fb from [rm2-stuff](https://github.com/timower/rM2-stuff/tree/dev)

References
----------

Largely based on https://gist.github.com/matteodelabre/92599920b46e5fac9daf58670d367950
