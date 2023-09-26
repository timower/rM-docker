# Step 1: Build Linux for the emulator
FROM ghcr.io/toltec-dev/base:v3.1 as linux-build

RUN apt-get update
RUN apt-get install -y bison bc lzop libssl-dev flex

ENV linux_release=5.8.18

RUN curl -o linux.tar.xz https://cdn.kernel.org/pub/linux/kernel/v5.x/linux-$linux_release.tar.xz && \
    mkdir -p /opt/linux && cd /opt/linux && tar -xf /linux.tar.xz && rm /linux.tar.xz

WORKDIR /opt/linux/linux-$linux_release

# Add a device tree with machine name set to 'reMarkable 2.0'
RUN cp arch/arm/boot/dts/imx7d-sbc-imx7.dts arch/arm/boot/dts/imx7d-rm.dts && \
    sed -i 's/CompuLab SBC-iMX7/reMarkable 2.0/' arch/arm/boot/dts/imx7d-rm.dts && \
    sed -i 's/imx7d-sbc-imx7.dtb/imx7d-sbc-imx7.dtb imx7d-rm.dtb/' arch/arm/boot/dts/Makefile

RUN make O=imx7 ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- imx_v6_v7_defconfig

# Enable uinput
RUN sed -i 's/# CONFIG_INPUT_UINPUT is not set/CONFIG_INPUT_UINPUT=y/' imx7/.config

ARG parallel=8
RUN make O=imx7 ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- -j$parallel

# Copy the output files
RUN cp imx7/arch/arm/boot/zImage /opt && \
    cp imx7/arch/arm/boot/dts/imx7d-rm.dtb /opt

# Step 2: rootfs
FROM python:3 as rootfs

RUN pip3 install protobuf

ENV PROTOCOL_BUFFERS_PYTHON_IMPLEMENTATION=python
RUN mkdir -p /opt/stuff && \
    git clone https://github.com/ddvk/stuff.git /opt/stuff

WORKDIR /opt

RUN git clone https://github.com/Jayy001/codexctl.git /opt/codexctl

# Download the firmware using codexctl
ARG fw_version=3.5.2.1807
RUN pip3 install -r /opt/codexctl/requirements.txt && \
    python /opt/codexctl/codexctl.py download $fw_version && \
    mv updates/*.signed /opt/fw.signed

# Extract the ext4 image
RUN python /opt/stuff/extractor/extractor.py /opt/fw.signed /opt/rootfs.ext4

# Add the template
RUN apt-get update && \
    apt-get install -y qemu-utils fdisk dosfstools
RUN apt-get install -y libguestfs-tools

ADD make_rootfs.sh /opt
RUN ./make_rootfs.sh /opt/rootfs.ext4

# Step3: Qemu!
FROM debian:bookworm AS qemu

RUN apt-get update && \
    apt-get install -y qemu-system-arm

RUN mkdir -p /opt/root

COPY --from=linux-build /opt/zImage /opt
COPY --from=linux-build /opt/imx7d-rm.dtb /opt
COPY --from=rootfs /opt/rootfs.qcow2 /opt/root

VOLUME /opt/root
EXPOSE 22/tcp
EXPOSE 8888/tcp

CMD qemu-system-arm \
    -machine mcimx7d-sabre \
    -cpu cortex-a9 \
    -smp 2 \
    -m 2048 \
    -kernel /opt/zImage \
    -dtb /opt/imx7d-rm.dtb \
    -drive if=sd,file=/opt/root/rootfs.qcow2,format=qcow2,index=2 \
    -append "console=ttymxc0 rootfstype=ext4 root=/dev/mmcblk1p2 rw rootwait init=/sbin/init" \
    -nic user,hostfwd=tcp::22-:22,hostfwd=tcp::8888-:8888 \
    -nographic
