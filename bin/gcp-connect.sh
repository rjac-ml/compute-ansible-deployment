#!/bin/bash
# Connect to GCP GKE cluster
# Usage: ./bin/gcp-connect.sh [environment] [color] [region]
# Example: ./bin/gcp-connect.sh dev blue us-central1

set -euo pipefail

ENVIRONMENT="${1:-dev}"
COLOR="${2:-blue}"
REGION="${3:-us-central1}"
PROJECT_ID="TBD"
CLUSTER_NAME="compute-ansible-${ENVIRONMENT}-${COLOR}"

echo "Connecting to GKE cluster: ${CLUSTER_NAME} (project: ${PROJECT_ID}, region: ${REGION})"

gcloud container clusters get-credentials "${CLUSTER_NAME}" \
  --region "${REGION}" \
  --project "${PROJECT_ID}"

# Create a short alias context (like aws eks --alias)
GKE_CONTEXT="gke_${PROJECT_ID}_${REGION}_${CLUSTER_NAME}"
ALIAS="gcp-${ENVIRONMENT}-${COLOR}"

kubectl config set-context "${ALIAS}" \
  --cluster="${GKE_CONTEXT}" \
  --user="${GKE_CONTEXT}" &>/dev/null
kubectl config use-context "${ALIAS}" &>/dev/null
echo "Context aliased to: ${ALIAS}"

echo "Connected. Testing access..."
kubectl get nodes
