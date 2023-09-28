#!/bin/sh
echo "Waiting for ssh to come up..."
while ! ssh -o StrictHostKeyChecking=no root@localhost true
do
  sleep 1
done
echo "Done!"
