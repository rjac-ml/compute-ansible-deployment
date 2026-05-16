# compute-ansible Platform Infrastructure
# Command runner for Terraform/Terragrunt operations
#
# Usage:
#   just --list                          Show all available recipes
#   just aws-plan dev us-east-1 bluemesh Plan the AWS dev bluemesh cluster
#   just aws-apply dev us-east-1 bluemesh Apply the AWS dev bluemesh cluster
#   just aws-apply-shared dev            Apply shared resources (admin only)

gcp_dir := "gcp/us-central1/compute-ansible"

# --- AWS Cluster Operations ---

# Plan AWS cluster changes
aws-plan account region versionmesh:
    cd aws/{{account}}/{{region}}/{{versionmesh}} && terragrunt plan --all --non-interactive

# Apply AWS cluster changes
aws-apply account region versionmesh:
    cd aws/{{account}}/{{region}}/{{versionmesh}} && terragrunt apply --all --non-interactive

# Destroy AWS cluster
aws-destroy account region versionmesh:
    cd aws/{{account}}/{{region}}/{{versionmesh}} && terragrunt destroy --all --non-interactive

# Init AWS cluster (download providers/modules)
aws-init account region versionmesh:
    cd aws/{{account}}/{{region}}/{{versionmesh}} && terragrunt init --all --non-interactive

# --- AWS Shared Operations (admin-only) ---

# Apply shared resources (OIDC, roles) — requires admin credentials
aws-apply-shared account:
    cd aws/{{account}}/shared && terragrunt apply --all --non-interactive

# Plan shared resources
aws-plan-shared account:
    cd aws/{{account}}/shared && terragrunt plan --all --non-interactive

# --- Azure Cluster Operations ---

# Plan Azure cluster changes
azure-plan account region versionmesh:
    cd azure/{{account}}/{{region}}/{{versionmesh}} && terragrunt plan --all --non-interactive

# Apply Azure cluster changes
azure-apply account region versionmesh:
    cd azure/{{account}}/{{region}}/{{versionmesh}} && terragrunt apply --all --non-interactive

# Destroy Azure cluster
azure-destroy account region versionmesh:
    cd azure/{{account}}/{{region}}/{{versionmesh}} && terragrunt destroy --all --non-interactive

# Init Azure cluster (download providers/modules)
azure-init account region versionmesh:
    cd azure/{{account}}/{{region}}/{{versionmesh}} && terragrunt init --all --non-interactive

# --- Azure Shared Operations (admin-only) ---

# Apply Azure shared resources (OIDC roles)
azure-apply-shared account:
    cd azure/{{account}}/shared && terragrunt apply --all --non-interactive

# Plan Azure shared resources
azure-plan-shared account:
    cd azure/{{account}}/shared && terragrunt plan --all --non-interactive

# --- Azure VM Access ---

# Run a command on an Azure VM via run-command (no SSH needed)
azure-run-command account region versionmesh node cmd:
    #!/usr/bin/env bash
    set -euo pipefail
    RG="compute-ansible-{{account}}-{{versionmesh}}-{{account}}-rg"
    VM_NAME="compute-ansible-{{account}}-{{versionmesh}}-{{account}}-{{node}}"
    echo "Running on ${VM_NAME} in ${RG}..."
    az vm run-command invoke \
      --resource-group "${RG}" \
      --name "${VM_NAME}" \
      --command-id RunShellScript \
      --scripts "{{cmd}}" \
      --query "value[0].message" -o tsv

# --- GCP Cluster Operations ---

# Plan GCP cluster changes
gcp-plan env color:
    cd {{gcp_dir}}/{{env}}/{{color}} && terragrunt plan --all --non-interactive

# Apply GCP cluster changes
gcp-apply env color:
    cd {{gcp_dir}}/{{env}}/{{color}} && terragrunt apply --all --non-interactive

# Destroy GCP cluster
gcp-destroy env color:
    cd {{gcp_dir}}/{{env}}/{{color}} && terragrunt destroy --all --non-interactive

# --- GCP Shared Operations (admin-only) ---

# Apply GCP shared resources (WIF) — requires admin credentials
gcp-apply-shared env:
    cd {{gcp_dir}}/{{env}} && terragrunt apply --all --non-interactive

# --- SSM Access ---

# Connect to an instance via SSM Session Manager
aws-ssm account region versionmesh instance:
    #!/usr/bin/env bash
    set -euo pipefail
    INSTANCE_ID=$(cd aws/{{account}}/{{region}}/{{versionmesh}}/ec2 && \
      terragrunt output -json instance_details | \
      jq -r '."{{instance}}".id')
    echo "Connecting to {{instance}} (${INSTANCE_ID})..."
    aws ssm start-session --target "${INSTANCE_ID}" --profile devops-compute-ansible

# --- Secrets / Bootstrap ---

# Sync OIDC role ARN to GitHub secret (run after aws-apply-shared)
aws-sync-oidc-secret account:
    #!/usr/bin/env bash
    set -euo pipefail
    SECRET_NAME="GH_ROLE_$(echo "{{account}}" | tr '[:lower:]' '[:upper:]')"
    echo "Fetching OIDC role ARN from shared/oidc..."
    ROLE_ARN=$(cd aws/{{account}}/shared/oidc && terragrunt output -raw github_actions_role_arn)
    echo "Setting GitHub secret ${SECRET_NAME} = ${ROLE_ARN}"
    echo "${ROLE_ARN}" | gh secret set "${SECRET_NAME}"
    echo "Done. Secret ${SECRET_NAME} set."

# --- Validation ---

# Format all Terraform files
fmt:
    terraform fmt -recursive aws/terraform/ azure/terraform/ gcp/terraform/

# Validate all Terraform modules
validate:
    #!/usr/bin/env bash
    set -euo pipefail
    for dir in $(find . -name "*.tf" -path "*/modules/*" -exec dirname {} \; | sort -u); do
        echo "Validating ${dir}..."
        (cd "${dir}" && terraform init -backend=false -input=false > /dev/null 2>&1 && terraform validate)
    done

# Check for leftover pixemilar references
check-rename:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "Checking for pixemilar references..."
    MATCHES=$(grep -rn "pixemilar" --include="*.hcl" --include="*.yaml" --include="*.yml" --include="*.sh" --include="*.md" --include="*.json" . | grep -v "_bck/" | grep -v "specs/001-\|specs/002-\|specs/003-" | grep -v ".git/" || true)
    if [ -n "${MATCHES}" ]; then
        echo "Found pixemilar references:"
        echo "${MATCHES}"
        exit 1
    fi
    echo "No pixemilar references found. Rename complete."
