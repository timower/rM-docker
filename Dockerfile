# Global config
ARG toltec_image=ghcr.io/toltec-dev/base:v3.1
ARG rm2_stuff_tag=v0.1.2
ARG fw_version=3.5.2.1807
ARG linux_release=5.8.18

# By default use a cached linux kernel. To build locally pass:
#  --build-arg linux_image=linux-build
ARG linux_image=ghcr.io/timower/rm-docker-linux:main

# Step 1: Build Linux for the emulator
FROM $toltec_image AS linux-builder

RUN apt-get update && \
    apt-get install -y --no-install-recommends bison bc lzop libssl-dev flex && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

ARG linux_release

RUN curl -o linux.tar.xz https://cdn.kernel.org/pub/linux/kernel/v5.x/linux-$linux_release.tar.xz && \
    mkdir -p /opt/linux && cd /opt/linux && tar -xf /linux.tar.xz && rm /linux.tar.xz

WORKDIR /opt/linux/linux-$linux_release

# Add a device tree with machine name set to 'reMarkable 2.0'
ADD ./imx7d-rm.dts arch/arm/boot/dts/
RUN sed -i 's/imx7d-sbc-imx7.dtb/imx7d-sbc-imx7.dtb imx7d-rm.dtb/' arch/arm/boot/dts/Makefile

# Default imx7 config, enable uinput and disable all modules
RUN make O=imx7 ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- imx_v6_v7_defconfig && \
    sed -i 's/# CONFIG_INPUT_UINPUT is not set/CONFIG_INPUT_UINPUT=y/' imx7/.config && \
    sed -i 's/=m/=n/' imx7/.config

# Build, Copy the output files and clean
RUN make O=imx7 ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- -j $(nproc) && \
    cp imx7/arch/arm/boot/zImage /opt && \
    cp imx7/arch/arm/boot/dts/imx7d-rm.dtb /opt && \
    rm -rf imx7

# This container just needs to kernel and device tree
FROM scratch AS linux-build
COPY --from=linux-builder /opt/zImage /opt/imx7d-rm.dtb /

# Use the linux image from build arg (from first stage or cached)
FROM $linux_image AS linux-image

# Step 2: rootfs
FROM linuxkit/guestfs:f85d370f7a3b0749063213c2dd451020e3a631ab AS rootfs

WORKDIR /opt
ARG TARGETARCH

COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/

# Install dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      git \
      build-essential \
      pkg-config \
      fuse \
      libfuse-dev \
      libz-dev && \
    apt-get clean && rm -rf /var/lib/apt/lists/* && \
    uv venv --python 3.13

ARG fw_version
RUN uv pip install https://github.com/Jayy001/codexctl.git && \
    .venv/bin/codexctl download $fw_version --hardware rm2 --out /tmp/firmware && \
    .venv/bin/codexctl extract --out /opt/rootfs.ext4 /tmp/firmware/* && \
    rm -rf /tmp/firmware

# Make the rootfs image
ADD make_rootfs.sh /opt
RUN ./make_rootfs.sh /opt/rootfs.ext4 $fw_version

# Step3: Qemu!
FROM debian:bookworm AS qemu-debug

RUN apt-get update && \
    apt-get install --no-install-recommends -y qemu-system-arm qemu-utils ssh netcat-openbsd && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /opt/root

COPY --from=linux-image /zImage /opt
COPY --from=linux-image /imx7d-rm.dtb /opt
COPY --from=rootfs /opt/rootfs.qcow2 /opt/root

ADD bin /opt/bin
ENV PATH=/opt/bin:$PATH

FROM qemu-debug AS qemu-base

# First boot, disable xochitl and reboot service, and save state
RUN run_vm -serial null -daemonize && \
    wait_ssh && \
    in_vm systemctl mask remarkable-fail && \
    in_vm systemctl mask xochitl && \
    save_vm

# Mount to presist rootfs
VOLUME /opt/root

# SSH access
EXPOSE 2222/tcp
# Qemu monitor TCP port
EXPOSE 5555/tcp
# For rm2fb
EXPOSE 8888/tcp

CMD run_vm -nographic

FROM qemu-base AS qemu-toltec

# Install toltec:
#  * Firsts make sure the time is synced, so https works correctly.
#  * Next, make sure home is mounted, as xochitl does it since they introduced encrypted data.
#  * Finally, download and run the bootstrap script.
RUN run_vm -serial null -daemonize && \
    wait_ssh && \
    in_vm 'while ! timedatectl status | grep "synchronized: yes"; do sleep 1; done' && \
    in_vm 'systemctl is-active home.mount || mount /dev/mmcblk2p4 /home' && \
    in_vm wget https://raw.githubusercontent.com/timower/toltec/refs/heads/feat/wget-update/scripts/bootstrap/bootstrap && \
    in_vm env bash bootstrap --force && \
    save_vm

# Step 4: Build rm2fb-emu for the debian host...
FROM debian:bookworm AS rm2fb-host

RUN apt-get update && \
    apt-get install -y --no-install-recommends git clang cmake ninja-build libsdl2-dev libevdev-dev libsystemd-dev xxd git-lfs && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

ARG rm2_stuff_tag
RUN mkdir -p /opt && \
    git clone https://github.com/timower/rM2-stuff.git /opt/rm2-stuff && \
    cd /opt/rm2-stuff && git reset --hard $rm2_stuff_tag && git lfs pull
WORKDIR /opt/rm2-stuff

RUN cmake --preset dev-host && cmake --build build/host --target rm2fb-emu

# Step 5: Integrate
FROM qemu-toltec AS qemu-rm2fb

RUN mkdir -p /opt/rm2fb

COPY --from=rm2fb-host /opt/rm2-stuff/build/host/tools/rm2fb-emu/rm2fb-emu /opt/bin

ARG rm2_stuff_tag
RUN run_vm -serial null -daemonize && \
    wait_ssh && \
    in_vm wget https://github.com/timower/rM2-stuff/releases/download/$rm2_stuff_tag/rm2display.ipk && \
    in_vm opkg install rm2display.ipk && \
    save_vm

RUN apt-get update && \
    apt-get install -y --no-install-recommends libevdev2 libsdl2-2.0-0 && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

CMD run_xochitl

FROM nixpkgs/nix-flakes AS nix-kernel
ADD . /src

RUN nix build '/src#kernel' -o /run/rm-kernel && \
    nix-collect-garbage

FROM nix-kernel AS nix-rootfs

ARG fw_version
RUN nix build "/src#\"rootfs-$fw_version\"" -o /run/rm-rootfs && \
    nix-collect-garbage

FROM nix-rootfs AS nix-emu

ARG fw_version
RUN nix build "/src#\"rm-emu-$fw_version\"" -o /result && \
    nix profile install /result && \
    nix-collect-garbage && \
    rm -rf /src

CMD run_vm

FROM rm-emu:$fw_version AS nix-start

# First boot, disable xochitl and reboot service, and save state
RUN run_vm -serial null -daemonize && \
    wait_ssh && \
    in_vm systemctl mask remarkable-fail && \
    in_vm systemctl mask xochitl && \
    save_vm

FROM nix-start AS nix-toltec

# Install toltec:
#  * Firsts make sure the time is synced, so https works correctly.
#  * Next, make sure home is mounted, as xochitl does it since they introduced encrypted data.
#  * Finally, download and run the bootstrap script.
RUN run_vm -serial null -daemonize && \
    wait_ssh && \
    in_vm 'while ! timedatectl status | grep "synchronized: yes"; do sleep 1; done' && \
    in_vm 'systemctl is-active home.mount || mount /dev/mmcblk2p4 /home' && \
    in_vm wget https://raw.githubusercontent.com/timower/toltec/refs/heads/feat/wget-update/scripts/bootstrap/bootstrap && \
    in_vm env bash bootstrap --force && \
    save_vm


