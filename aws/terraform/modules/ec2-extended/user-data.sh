#!/bin/bash
set -euxo pipefail

DEPLOYMENT_CODE="${deployment_code}"
DATA_DEVICE="/dev/xvdf"

# --- Install dependencies ---
dnf install -y jq

# --- Wait for and mount data volume ---
while [ ! -b "$DATA_DEVICE" ]; do
  echo "Waiting for data volume $DATA_DEVICE..."
  sleep 2
done
mkfs.xfs "$DATA_DEVICE"
mkdir -p /data
mount "$DATA_DEVICE" /data
echo "$DATA_DEVICE /data xfs defaults,nofail 0 2" >> /etc/fstab

# --- Set hostname via IMDS instance tags ---
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
NAME_TAG=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/tags/instance/Name 2>/dev/null || echo "")
REGION=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/placement/region)

if [ -n "$NAME_TAG" ]; then
  hostnamectl set-hostname "$NAME_TAG"
fi

# --- Peer discovery via deployment_code tag ---
mkdir -p /etc/compute-ansible

if [ -n "$DEPLOYMENT_CODE" ]; then
  RETRIES=0
  MAX_RETRIES=10
  PEERS="[]"

  while [ "$RETRIES" -lt "$MAX_RETRIES" ]; do
    PEERS=$(aws ec2 describe-instances \
      --filters "Name=tag:deployment_code,Values=$DEPLOYMENT_CODE" \
                "Name=instance-state-name,Values=running" \
      --query 'Reservations[].Instances[].{name: Tags[?Key==`Name`].Value | [0], ip: PrivateIpAddress}' \
      --output json --region "$REGION" 2>/dev/null || echo "[]")

    PEER_COUNT=$(echo "$PEERS" | jq length)
    if [ "$PEER_COUNT" -gt 1 ]; then
      break
    fi

    RETRIES=$((RETRIES + 1))
    echo "Waiting for peers (attempt $RETRIES/$MAX_RETRIES, found $PEER_COUNT)..."
    sleep 5
  done

  echo "$PEERS" | jq '.' > /etc/compute-ansible/peers.json
  echo "Discovered $(echo "$PEERS" | jq length) peers, written to /etc/compute-ansible/peers.json"
else
  echo "[]" > /etc/compute-ansible/peers.json
fi

echo "Instance setup complete."
