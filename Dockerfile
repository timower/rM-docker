# Global config
ARG toltec_image=ghcr.io/toltec-dev/base:v3.1
ARG rm2_stuff_tag=v0.1.2
ARG fw_version=3.5.2.1807
ARG linux_release=5.8.18

# Step 1: Build Linux for the emulator
FROM $toltec_image as linux-build

RUN apt-get update && \
    apt-get install -y bison bc lzop libssl-dev flex

ARG linux_release

RUN curl -o linux.tar.xz https://cdn.kernel.org/pub/linux/kernel/v5.x/linux-$linux_release.tar.xz && \
    mkdir -p /opt/linux && cd /opt/linux && tar -xf /linux.tar.xz && rm /linux.tar.xz

WORKDIR /opt/linux/linux-$linux_release

# Add a device tree with machine name set to 'reMarkable 2.0'
RUN cp arch/arm/boot/dts/imx7d-sbc-imx7.dts arch/arm/boot/dts/imx7d-rm.dts && \
    sed -i 's/CompuLab SBC-iMX7/reMarkable 2.0/' arch/arm/boot/dts/imx7d-rm.dts && \
    sed -i 's/imx7d-sbc-imx7.dtb/imx7d-sbc-imx7.dtb imx7d-rm.dtb/' arch/arm/boot/dts/Makefile

# Default imx7 config, enable uinput and disable all modules
RUN make O=imx7 ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- imx_v6_v7_defconfig && \
    sed -i 's/# CONFIG_INPUT_UINPUT is not set/CONFIG_INPUT_UINPUT=y/' imx7/.config && \
    sed -i 's/=m/=n/' imx7/.config

# Build, Copy the output files and clean
RUN make O=imx7 ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- -j $(nproc) && \
    cp imx7/arch/arm/boot/zImage /opt && \
    cp imx7/arch/arm/boot/dts/imx7d-rm.dtb /opt && \
    rm -rf imx7

# Step 2: rootfs
FROM linuxkit/guestfs:f85d370f7a3b0749063213c2dd451020e3a631ab AS rootfs

WORKDIR /opt
ARG TARGETARCH

# Install dependencies
ADD https://github.com/jqlang/jq/releases/download/jq-1.7/jq-linux-${TARGETARCH} \
    /usr/local/bin/jq

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      git \
      python3 \
      python3-protobuf && \
    chmod +x /usr/local/bin/jq && \
    git clone https://github.com/ddvk/stuff.git /opt/stuff

ENV PROTOCOL_BUFFERS_PYTHON_IMPLEMENTATION=python

ADD get_update.sh /opt
ADD updates.json /opt

ARG fw_version
RUN /opt/get_update.sh download $fw_version && \
    python3 /opt/stuff/extractor/extractor.py /opt/fw.signed /opt/rootfs.ext4

# Make the rootfs image
ADD make_rootfs.sh /opt
RUN ./make_rootfs.sh /opt/rootfs.ext4

# Step3: Qemu!
FROM debian:bookworm AS qemu-debug

RUN apt-get update && \
    apt-get install --no-install-recommends -y qemu-system-arm qemu-utils ssh netcat-openbsd

RUN mkdir -p /opt/root

COPY --from=linux-build /opt/zImage /opt
COPY --from=linux-build /opt/imx7d-rm.dtb /opt
COPY --from=rootfs /opt/rootfs.qcow2 /opt/root

ADD bin /opt/bin
ENV PATH=/opt/bin:$PATH

FROM qemu-debug as qemu-base

# First boot, disable xochitl and reboot service, and save state
RUN run_vm -serial null -daemonize && \
    wait_ssh && \
    in_vm systemctl mask remarkable-fail && \
    in_vm systemctl mask xochitl && \
    save_vm

# Mount to presist rootfs
VOLUME /opt/root

# SSH access
EXPOSE 22/tcp
# Qemu monitor TCP port
EXPOSE 5555/tcp
# For rm2fb
EXPOSE 8888/tcp

CMD run_vm -nographic

FROM qemu-base AS qemu-toltec

RUN run_vm -serial null -daemonize && \
    wait_ssh && \
    in_vm 'while ! timedatectl status | grep "synchronized: yes"; do sleep 1; done' && \
    in_vm wget https://raw.githubusercontent.com/toltec-dev/toltec/testing/scripts/bootstrap/bootstrap && \
    in_vm env toltec_branch=testing bash bootstrap --force && \
    save_vm

# Step 4: Build rm2fb-emu for the debian host...
FROM debian:bookworm AS rm2fb-host

RUN apt-get update && \
    apt-get install -y git clang cmake ninja-build libsdl2-dev libevdev-dev libsystemd-dev

RUN apt-get install -y xxd git-lfs

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
    apt-get install -y libevdev2 libsdl2-2.0-0

CMD run_xochitl
