# Azure Subscription Setup

One-time setup for the `compute-ansible-dev` Azure subscription.

## Prerequisites

- Azure tenant (Entra ID) exists
- Azure CLI installed: https://learn.microsoft.com/en-us/cli/azure/install-azure-cli

## Steps

### 1. Login to Azure

```bash
az login
```

### 2. Create or identify subscription

If you already have a subscription, list them:

```bash
az account list --output table
```

To create a new subscription (requires billing account access):

```bash
az account create \
  --display-name "compute-ansible-dev" \
  --offer-type MS-AZR-0017P
```

### 3. Set the active subscription

```bash
az account set --subscription "compute-ansible-dev"
```

### 4. Record identifiers

```bash
# Subscription ID
az account show --query id -o tsv

# Tenant ID
az account show --query tenantId -o tsv
```

Save these values — they go into `azure/dev/account.hcl`:

```hcl
locals {
  account         = "dev"
  subscription_id = "<subscription-id-from-above>"
  tenant_id       = "<tenant-id-from-above>"
}
```

### 5. Register resource providers

New subscriptions don't have resource providers enabled. Register the ones needed for infrastructure deployment:

```bash
az provider register --namespace Microsoft.Storage
az provider register --namespace Microsoft.Compute
az provider register --namespace Microsoft.Network
az provider register --namespace Microsoft.ManagedIdentity
```

Wait ~1-2 minutes, then verify:

```bash
az provider show --namespace Microsoft.Storage --query registrationState -o tsv
az provider show --namespace Microsoft.Compute --query registrationState -o tsv
az provider show --namespace Microsoft.Network --query registrationState -o tsv
az provider show --namespace Microsoft.ManagedIdentity --query registrationState -o tsv
```

All should say `Registered` before proceeding.

### 6. Create resource group for Terraform state

```bash
az group create \
  --name "compute-ansible-tfstate-dev" \
  --location "eastus"
```

### 7. Verify

```bash
az group show --name "compute-ansible-tfstate-dev" --output table
```

### Note: Multi-region state

The resource group for state (`compute-ansible-tfstate-dev`) is created once. All regional storage accounts (`smeshdeveastus`, `smeshdeveastus2`, etc.) live in this same resource group. See [02-state-backend-setup.md](02-state-backend-setup.md) for adding new regions.

**AWS vs Azure state approach:**
- **AWS**: One S3 bucket per account, serves all regions (S3 is global). Backend region is hardcoded to where the bucket lives (`us-east-1`).
- **Azure**: One storage account per account+region (storage accounts are regional). Each new region needs a new storage account.

## Next

Proceed to [02-state-backend-setup.md](02-state-backend-setup.md).
