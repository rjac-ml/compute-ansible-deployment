# Azure VM Access

How to connect to and run commands on Azure VMs deployed by the compute-ansible vm-extended module. VMs are on private subnets with no public IP.

## Options

| Method | Cost | Interactive Shell | SSH Keys Needed | Setup |
|--------|------|-------------------|-----------------|-------|
| `az vm run-command` | Free | No (fire-and-forget) | No | None — uses VM Agent (pre-installed) |
| Azure Serial Console | Free | Yes (emergency) | No | Enable boot diagnostics |
| `az ssh vm` (AAD SSH) | Free | Yes | No (uses Entra ID) | Install `ssh` extension |
| Azure Bastion | ~$140/mo | Yes (browser SSH) | No | Deploy Bastion subnet + host |

## Recommended: `az vm run-command` (Free, No SSH)

The closest equivalent to AWS SSM Session Manager's `run-command`. Works via the Azure VM Agent (pre-installed on all Azure VMs), communicates over port 443, no SSH keys or public IP needed.

### Run a command on a VM

```bash
az vm run-command invoke \
  --resource-group "compute-ansible-dev-bluemesh-dev-rg" \
  --name "compute-ansible-dev-bluemesh-dev-node-1-1" \
  --command-id RunShellScript \
  --scripts "hostname && cat /etc/compute-ansible/peers.json"
```

### Run a script on a VM

```bash
az vm run-command invoke \
  --resource-group "compute-ansible-dev-bluemesh-dev-rg" \
  --name "compute-ansible-dev-bluemesh-dev-node-1-1" \
  --command-id RunShellScript \
  --scripts @my-script.sh
```

### Run on all VMs in a deployment

```bash
RESOURCE_GROUP="compute-ansible-dev-bluemesh-dev-rg"

for VM_NAME in $(az vm list --resource-group "$RESOURCE_GROUP" --query "[].name" -o tsv); do
  echo "=== $VM_NAME ==="
  az vm run-command invoke \
    --resource-group "$RESOURCE_GROUP" \
    --name "$VM_NAME" \
    --command-id RunShellScript \
    --scripts "hostname && uptime" \
    --query "value[0].message" -o tsv
done
```

### Limitations

- Output is capped at 4 KB
- Execution timeout is 90 minutes
- Not interactive — you send a script and get output back
- One command at a time per VM

## Alternative: `az ssh vm` (Interactive Shell via Entra ID)

For interactive access without managing SSH keys. Uses your Azure AD/Entra ID identity.

### One-time setup

```bash
az extension add --name ssh
```

### Connect to a VM

```bash
az ssh vm \
  --resource-group "compute-ansible-dev-bluemesh-dev-rg" \
  --name "compute-ansible-dev-bluemesh-dev-node-1-1"
```

This requires the VM to be reachable from your network (direct or via VPN/peering). For VMs on private subnets with no public IP, you need either:
- A VPN/ExpressRoute connection to the VNet
- Or Azure Bastion (see below)

### Enable AAD SSH on the VM

The VM needs the AAD SSH extension. Add this to the vm-extended module if you want to use `az ssh vm`:

```bash
az vm extension set \
  --resource-group "compute-ansible-dev-bluemesh-dev-rg" \
  --vm-name "compute-ansible-dev-bluemesh-dev-node-1-1" \
  --name AADSSHLoginForLinux \
  --publisher Microsoft.Azure.ActiveDirectory
```

## Alternative: Azure Serial Console (Emergency Access)

Free, works even when the VM is unresponsive. Requires boot diagnostics to be enabled.

### Enable boot diagnostics

```bash
az vm boot-diagnostics enable \
  --resource-group "compute-ansible-dev-bluemesh-dev-rg" \
  --name "compute-ansible-dev-bluemesh-dev-node-1-1"
```

### Access via Portal

Azure Portal → VM → Help → Serial Console

This gives a direct terminal connection to the VM's serial port — useful for debugging boot issues or when SSH/networking is broken.

## Alternative: Azure Bastion (Managed Jump Host)

Fully managed SSH/RDP gateway. Most feature-complete but expensive (~$140/mo for Basic SKU).

Only recommended if you need frequent interactive shell access across many VMs. For occasional access, `az vm run-command` + Serial Console covers most needs.

## Comparison with AWS

| AWS | Azure |
|-----|-------|
| SSM Session Manager (free, interactive) | `az vm run-command` (free, non-interactive) |
| SSM Run Command | `az vm run-command` (same concept) |
| EC2 Instance Connect | `az ssh vm` (Entra ID auth) |
| No direct equivalent | Azure Serial Console |
| No direct equivalent | Azure Bastion ($140/mo) |

The main gap: Azure has no free interactive shell equivalent to SSM Session Manager. `az vm run-command` is the workhorse for automation, and `az ssh vm` via Entra ID is the closest to interactive access without managing keys.

## Justfile Recipe

Use this to run commands on VMs:

```bash
just azure-run-command dev eastus bluemesh node-1-1 "hostname && uptime"
```

## References

- https://learn.microsoft.com/en-us/azure/virtual-machines/linux/run-command
- https://learn.microsoft.com/en-us/azure/virtual-machines/linux/login-using-aad
- https://learn.microsoft.com/en-us/troubleshoot/azure/virtual-machines/linux/serial-console-linux
- https://learn.microsoft.com/en-us/azure/bastion/bastion-overview
