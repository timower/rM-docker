reMarkable 2 Docker image
=========================

This repo contains a docker file for building a container containing an emulator
for the remarkable 2 OS.

Usage
-----

```shell
> docker build --tag rm-docker https://github.com/timower/rM-docker.git
> docker run --rm -v rm-data:/opt/root -p 2222:22 -it rm-docker
reMarkable login:
# Now login using the root account, no password
# Or ssh:
> ssh root@localhost -p 2222
```

Targets
-------

### qemu-base

Use `docker build --target qemu-base` to build a basic qemu image.

### qemu-toltec

The `qemu-toltec` target will install [toltec](https://toltec-dev.org/) in
the image.

### qemu-rm2fb

The `qemu-rm2fb` target (which is the default) will include a framebuffer
emulator from [rm2-stuff](https://github.com/timower/rM2-stuff/tree/dev).

X11 forwarding can be used to view the framebuffer:
```shell
> xhost + local: # Only if you're on Wayland WM instead of X11.
> docker run --rm -it \
  --volume /tmp/.X11-unix:/tmp/.X11-unix \
  --volume $HOME/.Xauthority:/root/.Xauthority \
  --env DISPLAY \
  --hostname "$(hostnamectl hostname)" \
  --publish 2222:22 \
  rm-docker
```

References
----------

Largely based on https://gist.github.com/matteodelabre/92599920b46e5fac9daf58670d367950
