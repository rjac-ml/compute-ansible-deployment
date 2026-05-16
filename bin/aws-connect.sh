#!/bin/bash
# Connect to AWS EKS cluster
# Usage: ./bin/aws-connect.sh [account] [versionmesh] [role]
# Example: ./bin/aws-connect.sh dev bluemesh admin
#          ./bin/aws-connect.sh dev bluemesh developer

set -euo pipefail

ACCOUNT="${1:-dev}"
VERSIONMESH="${2:-bluemesh}"
ROLE="${3:-admin}"
PROFILE="devops-compute-ansible"
CLUSTER_NAME="compute-ansible-${ACCOUNT}-${VERSIONMESH}"
ROLE_NAME="${CLUSTER_NAME}-${ROLE}"

echo "Connecting to EKS cluster: ${CLUSTER_NAME} (role: ${ROLE_NAME})"

ROLE_ARN=$(aws iam get-role \
  --role-name "${ROLE_NAME}" \
  --query 'Role.Arn' \
  --output text \
  --profile "${PROFILE}")

aws eks update-kubeconfig \
  --name "${CLUSTER_NAME}" \
  --alias "${CLUSTER_NAME}" \
  --role-arn "${ROLE_ARN}" \
  --profile "${PROFILE}"

echo "Connected. Testing access..."
kubectl get nodes
