# azure-tools

Utility scripts for Azure and Microsoft Graph administration.

## Prerequisites

- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli) installed and logged in (`az login`)
- [jq](https://jqlang.github.io/jq/) installed
- Sufficient Entra ID permissions (Global Admin or Privileged Role Administrator)

## Tools

### grant-graph-permission.sh

Grant Microsoft Graph API application permissions to a service principal (e.g. a Managed Identity).

```bash
./scripts/bash/grant-graph-permission.sh <service-principal-id> <permission> [permission2 ...]
```

**Arguments:**

| Argument | Description |
|----------|-------------|
| `service-principal-id` | Object ID of the service principal (find in Entra ID > Enterprise Applications, or on the resource's Identity tab) |
| `permission` | One or more Graph application permission names (case-sensitive, e.g. `Mail.Send`, `User.Read.All`) |

**Examples:**

```bash
# Grant a single permission
./scripts/bash/grant-graph-permission.sh <service-principal-object-id> Mail.Send

# Grant multiple permissions at once
./scripts/bash/grant-graph-permission.sh <service-principal-object-id> Mail.Send User.Read.All

# Run directly from GitHub without cloning
curl -sL https://raw.githubusercontent.com/tignis/azure-tools/refs/heads/main/scripts/bash/grant-graph-permission.sh \
  | bash -s -- <service-principal-object-id> Mail.Send
```

Permission names are resolved automatically against Microsoft Graph's published app roles, so you don't need to look up role IDs manually.

### Running from Azure Cloud Shell

1. Open [Azure Cloud Shell](https://shell.azure.com). If it starts in PowerShell, type `bash`.
2. Paste the command below, replacing the Object ID and permission(s):

```bash
curl -sL https://raw.githubusercontent.com/tignis/azure-tools/refs/heads/main/scripts/bash/grant-graph-permission.sh \
  | bash -s -- <service-principal-object-id> Mail.Send
```

> **Watch out for copy-paste issues:**
> - Make sure there are no extra line breaks after pasting.
> - If you see `bash: curl: command not found`, there may be an invisible zero-width character at the start of the line. This can happen when copying from rendered HTML or Markdown. Delete the line and retype `curl` manually.

### Finding the Object ID for a Managed Identity

1. In the Azure portal, go to **Entra ID > Enterprise Applications**
2. Search for the application name (e.g. the name of your resource)
3. Remove the default **Application Type** filter so Managed Identities are visible
4. Click the entry marked "Managed by Microsoft" in the Certificate & Expiry Status column
5. Copy the **Object ID** from the overview page — this is the value to pass as `<service-principal-object-id>`
