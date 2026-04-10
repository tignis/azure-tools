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
./scripts/bash/grant-graph-permission.sh 2718d9ac-bdc4-4066-9b8a-940edf614e19 Mail.Send

# Grant multiple permissions at once
./scripts/bash/grant-graph-permission.sh 2718d9ac-bdc4-4066-9b8a-940edf614e19 Mail.Send User.Read.All
```

Permission names are resolved automatically against Microsoft Graph's published app roles, so you don't need to look up role IDs manually.
