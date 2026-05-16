# Quickstart: New Directory Layout & Service Discovery

## After Implementation

### Deploy a versionmesh (e.g., bluemesh in dev)

```bash
# Plan (local, read-only)
just aws-plan dev us-east-1 bluemesh

# Apply (via GitHub Actions — dispatch aws-kubernetes-provision.yaml)
# Inputs: account=dev, region=us-east-1, cluster=bluemesh
```

### Deploy shared resources (admin-only, local)

```bash
just aws-apply-shared dev
```

### Create a new versionmesh (e.g., redmesh)

```bash
# 1. Copy an existing versionmesh directory
cp -r aws/dev/us-east-1/bluemesh aws/dev/us-east-1/redmesh

# 2. Adjust inputs in each terragrunt.hcl if needed (VPC CIDR, instance counts)
# The versionmesh name is auto-derived from the directory path — no manual rename needed

# 3. Plan
just aws-plan dev us-east-1 redmesh
```

### Verify service discovery from an instance

```bash
# Connect via SSM
just aws-ssm dev us-east-1 bluemesh cp-1

# On the instance — discover peers
DEPLOYMENT_CODE=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" | \
  xargs -I{} curl -s -H "X-aws-ec2-metadata-token: {}" \
  http://169.254.169.254/latest/meta-data/tags/instance/deployment_code)

aws ec2 describe-instances \
  --filters "Name=tag:deployment_code,Values=$DEPLOYMENT_CODE" \
            "Name=instance-state-name,Values=running" \
  --query "Reservations[].Instances[].[Tags[?Key=='Name'].Value|[0],PrivateIpAddress,Tags[?Key=='Role'].Value|[0]]" \
  --output table --region us-east-1

# Check auto-generated peers file
cat /etc/compute-ansible/peers.json
```

### Validate the restructure

```bash
# Format check
just fmt

# Module validation
just validate

# Plan from new layout (should succeed with correct provider/state config)
just aws-plan dev us-east-1 bluemesh
```
