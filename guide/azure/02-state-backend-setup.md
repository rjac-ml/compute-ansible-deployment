# Azure State Backend Setup

Create the Azure Storage Account and blob container for Terraform state.

## Prerequisites

- Completed [01-subscription-setup.md](01-subscription-setup.md)
- Resource group `compute-ansible-tfstate-dev` exists in eastus

## Naming Convention

Storage Account names are globally unique across all of Azure, max 24 chars, lowercase alphanumeric only (no hyphens).

Format: `smesh<account><region>`

| Account | Region | Storage Account Name |
|---------|--------|---------------------|
| dev | eastus | `smeshdeveastus` |
| dev | westus2 | `smeshdevwestus2` |
| stage | eastus | `smeshstageeastus` |
| prod | eastus | `smeshprodeastus` |

## Steps

### 1. Verify the name is available

```bash
az storage account check-name --name smeshdeveastus
```

### 2. Create the storage account

```bash
az storage account create \
  --name "smeshdeveastus" \
  --resource-group "compute-ansible-tfstate-dev" \
  --location "eastus" \
  --sku Standard_LRS \
  --min-tls-version TLS1_2 \
  --allow-blob-public-access false \
  --https-only true
```

### 3. Create the blob container

```bash
az storage container create \
  --name "tfstate" \
  --account-name "smeshdeveastus" \
  --auth-mode login
```

### 4. Grant yourself data-plane access

```bash
# Get your user object ID
USER_OBJECT_ID=$(az ad signed-in-user show --query id -o tsv)

# Grant Storage Blob Data Contributor on the container
az role assignment create \
  --role "Storage Blob Data Contributor" \
  --assignee-object-id "$USER_OBJECT_ID" \
  --assignee-principal-type User \
  --scope "/subscriptions/$(az account show --query id -o tsv)/resourceGroups/compute-ansible-tfstate-dev/providers/Microsoft.Storage/storageAccounts/smeshdeveastus/blobServices/default/containers/tfstate"
```

### 5. Verify

```bash
az storage container list \
  --account-name "smeshdeveastus" \
  --auth-mode login \
  --output table
```

## Adding a New Region

Each region needs its own storage account. Repeat steps 1-5 with the new region name:

```bash
# Example: eastus2
az storage account create \
  --name "smeshdeveastus2" \
  --resource-group "compute-ansible-tfstate-dev" \
  --location "eastus2" \
  --sku Standard_LRS \
  --min-tls-version TLS1_2 \
  --allow-blob-public-access false \
  --https-only true

az storage container create \
  --name "tfstate" \
  --account-name "smeshdeveastus2" \
  --auth-mode login
```

Grant the CI/CD service principal access (same as step 4, different storage account):

```bash
az role assignment create \
  --role "Storage Blob Data Contributor" \
  --assignee-object-id "<service-principal-object-id>" \
  --assignee-principal-type ServicePrincipal \
  --scope "/subscriptions/$(az account show --query id -o tsv)/resourceGroups/compute-ansible-tfstate-dev/providers/Microsoft.Storage/storageAccounts/smeshdeveastus2"
```

## Locking

Azure blob storage uses native blob leases for state locking — no additional configuration needed.

If a lock gets stuck (rare), break it with:

```bash
az storage blob lease break \
  --account-name "smeshdeveastus" \
  --container-name "tfstate" \
  --blob-name "<state-key-path>"
```

## Next

Proceed to [03-oidc-federation.md](03-oidc-federation.md).
