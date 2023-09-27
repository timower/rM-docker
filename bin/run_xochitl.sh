#!/bin/sh

set -eux

# Start the VM
run_vm.sh -serial null -daemonize

# Make sure it's up
ssh -o StrictHostKeyChecking=no root@localhost 'true'

# Launch the TCP forwarding server
ssh -o StrictHostKeyChecking=no root@localhost './rm2fb-forward' &

# Make sure the server is running by waiting a bit :(
sleep 5

# Connect using the FB emulator
rm2fb-emu 127.0.0.1 8888 &

# Start xochitl
ssh -o StrictHostKeyChecking=no root@localhost 'LD_PRELOAD=/home/root/librm2fb_client.so /usr/bin/xochitl'

