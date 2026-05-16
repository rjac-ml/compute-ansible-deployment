# Azure OIDC Federation for GitHub Actions

Set up workload identity federation so GitHub Actions can authenticate with Azure using OIDC — zero stored secrets.

## Prerequisites

- Completed [01-subscription-setup.md](01-subscription-setup.md) and [02-state-backend-setup.md](02-state-backend-setup.md)
- GitHub repository: `next-signal/compute-ansible-machines`

## Steps

### 1. Capture identifiers

```bash
AZURE_TENANT_ID=$(az account show --query tenantId -o tsv)
AZURE_SUBSCRIPTION_ID=$(az account show --query id -o tsv)
```

### 2. Create App Registration

```bash
APP_DISPLAY_NAME="next-signal-github-actions"

AZURE_CLIENT_ID=$(az ad app create \
  --display-name "$APP_DISPLAY_NAME" \
  --query appId -o tsv)

AZURE_APP_OBJECT_ID=$(az ad app show \
  --id "$AZURE_CLIENT_ID" \
  --query id -o tsv)

echo "Client ID: $AZURE_CLIENT_ID"
echo "App Object ID: $AZURE_APP_OBJECT_ID"
```

### 3. Create Service Principal

```bash
az ad sp create --id "$AZURE_CLIENT_ID"

AZURE_PRINCIPAL_ID=$(az ad sp show \
  --id "$AZURE_CLIENT_ID" \
  --query id -o tsv)

echo "Principal ID: $AZURE_PRINCIPAL_ID"
```

### 4. Create Federated Credential (all branches)

This uses Flexible Federated Identity Credentials with wildcard matching, so any branch in any `compute-ansible-*` repo can authenticate:

```bash
az rest --method POST \
  --url "https://graph.microsoft.com/beta/applications/${AZURE_APP_OBJECT_ID}/federatedIdentityCredentials" \
  --body "{
    \"name\": \"github-all-refs\",
    \"issuer\": \"https://token.actions.githubusercontent.com\",
    \"audiences\": [\"api://AzureADTokenExchange\"],
    \"claimsMatchingExpression\": {
      \"value\": \"claims['sub'] matches 'repo:next-signal/compute-ansible-*:*'\",
      \"languageVersion\": 1
    }
  }"
```

To verify:

```bash
az rest --method GET \
  --url "https://graph.microsoft.com/beta/applications/${AZURE_APP_OBJECT_ID}/federatedIdentityCredentials"
```

### 5. Assign RBAC roles

```bash
# Contributor at subscription scope (create/manage all resources)
az role assignment create \
  --assignee-object-id "$AZURE_PRINCIPAL_ID" \
  --assignee-principal-type ServicePrincipal \
  --role "Contributor" \
  --scope "/subscriptions/$AZURE_SUBSCRIPTION_ID"

# Storage Blob Data Contributor on state storage (read/write state files via Azure AD)
az role assignment create \
  --assignee-object-id "$AZURE_PRINCIPAL_ID" \
  --assignee-principal-type ServicePrincipal \
  --role "Storage Blob Data Contributor" \
  --scope "/subscriptions/$AZURE_SUBSCRIPTION_ID/resourceGroups/compute-ansible-tfstate-dev/providers/Microsoft.Storage/storageAccounts/smeshdeveastus"
```

### 6. Set GitHub Variables

These are non-sensitive identifiers — store as **Variables** (not Secrets):

Variables are suffixed with the account name (e.g., `_DEV`, `_STAGE`) so each account can have its own credentials:

```
GitHub repo → Settings → Secrets and Variables → Actions → Variables tab

AZURE_CLIENT_ID_DEV       = <AZURE_CLIENT_ID from step 2>
AZURE_TENANT_ID_DEV       = <AZURE_TENANT_ID from step 1>
AZURE_SUBSCRIPTION_ID_DEV = <AZURE_SUBSCRIPTION_ID from step 1>
```

Or via CLI:

```bash
ACCOUNT="DEV"  # or STAGE, PROD
gh variable set "AZURE_CLIENT_ID_${ACCOUNT}" --body "$AZURE_CLIENT_ID"
gh variable set "AZURE_TENANT_ID_${ACCOUNT}" --body "$AZURE_TENANT_ID"
gh variable set "AZURE_SUBSCRIPTION_ID_${ACCOUNT}" --body "$AZURE_SUBSCRIPTION_ID"
```

### 7. Verify

Test from a GitHub Actions workflow:

```yaml
permissions:
  id-token: write
  contents: read

steps:
  - uses: azure/login@v3
    with:
      client-id: ${{ vars.AZURE_CLIENT_ID }}
      tenant-id: ${{ vars.AZURE_TENANT_ID }}
      subscription-id: ${{ vars.AZURE_SUBSCRIPTION_ID }}

  - run: az account show --output table
```

## How it works

1. GitHub's OIDC provider mints a short-lived JWT with claims like `sub: repo:next-signal/compute-ansible-machines:ref:refs/heads/main`
2. `azure/login` (or `ARM_USE_OIDC=true`) exchanges that JWT with Microsoft Entra ID
3. Entra ID validates the issuer, audience, and subject against the federated credential
4. If valid, returns a short-lived Azure access token

No client secret is stored anywhere — authentication relies entirely on the OIDC token exchange.

## For Terraform/Terragrunt

No `azure/login` step is needed. Set environment variables instead:

```yaml
env:
  ARM_USE_OIDC: "true"
  ARM_USE_AZUREAD: "true"
  ARM_CLIENT_ID: ${{ vars.AZURE_CLIENT_ID }}
  ARM_TENANT_ID: ${{ vars.AZURE_TENANT_ID }}
  ARM_SUBSCRIPTION_ID: ${{ vars.AZURE_SUBSCRIPTION_ID }}
```

The azurerm provider and backend read these automatically and exchange the GitHub OIDC token directly.

## References

- https://learn.microsoft.com/en-us/azure/developer/github/connect-from-azure-openid-connect
- https://learn.microsoft.com/en-us/entra/workload-id/workload-identities-flexible-federated-identity-credentials
- https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/guides/service_principal_oidc
