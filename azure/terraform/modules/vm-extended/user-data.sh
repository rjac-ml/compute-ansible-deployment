#!/bin/bash
set -euxo pipefail

DEPLOYMENT_CODE="${deployment_code}"
DATA_DEVICE="/dev/sdc"

# --- Install dependencies ---
apt-get update -y
apt-get install -y jq

# --- Wait for and mount data disk ---
while [ ! -b "$DATA_DEVICE" ]; do
  echo "Waiting for data disk $DATA_DEVICE..."
  sleep 2
done

if ! blkid "$DATA_DEVICE" > /dev/null 2>&1; then
  mkfs.xfs "$DATA_DEVICE"
fi

mkdir -p /data
mount "$DATA_DEVICE" /data
echo "$DATA_DEVICE /data xfs defaults,nofail 0 2" >> /etc/fstab

# --- Set hostname via IMDS ---
VM_NAME=$(curl -s -H "Metadata:true" \
  "http://169.254.169.254/metadata/instance/compute/name?api-version=2021-02-01&format=text")
if [ -n "$VM_NAME" ]; then
  hostnamectl set-hostname "$VM_NAME"
fi

# --- Write deployment info ---
mkdir -p /etc/compute-ansible
echo "{\"deployment_code\": \"$DEPLOYMENT_CODE\", \"hostname\": \"$VM_NAME\"}" > /etc/compute-ansible/identity.json

echo "Instance setup complete."
