#!/bin/bash
# Grant Microsoft Graph API permissions to a Service Principal (e.g. Managed Identity)
#
# Usage:
#   ./scripts/grant-graph-permission.sh <service-principal-id> <permission> [permission2 ...]
#
# Examples:
#   ./scripts/grant-graph-permission.sh 2718d9ac-bdc4-4066-9b8a-940edf614e19 Mail.Send
#   ./scripts/grant-graph-permission.sh 2718d9ac-bdc4-4066-9b8a-940edf614e19 Mail.Send User.Read.All
#
# The service-principal-id is the Object ID of the service principal, which you
# can find in Entra ID -> Enterprise Applications, or on the resource's Identity tab.
#
# Permission names are resolved automatically against Microsoft Graph's published app roles.
#
# Prerequisites:
#   - Azure CLI installed and logged in (az login)
#   - Sufficient permissions (Global Admin or Privileged Role Administrator)
#   - jq installed

set -euo pipefail

SP_ID="${1:-}"
shift 2>/dev/null || true
PERMISSIONS=("$@")

if [ -z "$SP_ID" ] || [ ${#PERMISSIONS[@]} -eq 0 ]; then
    echo "Usage: $0 <service-principal-id> <permission> [permission2 ...]"
    echo ""
    echo "Examples:"
    echo "  $0 2718d9ac-bdc4-4066-9b8a-940edf614e19 Mail.Send"
    echo "  $0 2718d9ac-bdc4-4066-9b8a-940edf614e19 Mail.Send User.Read.All"
    exit 1
fi

GRAPH_APP_ID="00000003-0000-0000-c000-000000000000"

echo "=== Grant Graph API Permissions ==="
echo "Service Principal: $SP_ID"
echo "Permissions: ${PERMISSIONS[*]}"
echo ""

# Step 1: Get the Microsoft Graph service principal and its app roles
echo "Looking up Microsoft Graph service principal and available roles..."
GRAPH_SP=$(az ad sp show --id "$GRAPH_APP_ID" -o json 2>/dev/null)

if [ -z "$GRAPH_SP" ]; then
    echo "ERROR: Could not find Microsoft Graph service principal in this tenant"
    exit 1
fi

GRAPH_SP_ID=$(echo "$GRAPH_SP" | jq -r '.id')
echo "  Graph SP ID: $GRAPH_SP_ID"
echo ""

# Step 2: For each permission, resolve the name to a role ID and assign it
ERRORS=0
for PERM in "${PERMISSIONS[@]}"; do
    echo "--- $PERM ---"

    # Look up the appRoleId by matching the permission value
    ROLE_ID=$(echo "$GRAPH_SP" | jq -r --arg perm "$PERM" '.appRoles[] | select(.value == $perm) | .id' 2>/dev/null)

    if [ -z "$ROLE_ID" ]; then
        echo "  ERROR: '$PERM' is not a valid Microsoft Graph application permission"
        echo "  Hint: permission names are case-sensitive (e.g. Mail.Send, not mail.send)"
        ERRORS=$((ERRORS + 1))
        echo ""
        continue
    fi

    echo "  Role ID: $ROLE_ID"

    # Assign the role
    BODY=$(jq -n \
        --arg principalId "$SP_ID" \
        --arg resourceId "$GRAPH_SP_ID" \
        --arg appRoleId "$ROLE_ID" \
        '{principalId: $principalId, resourceId: $resourceId, appRoleId: $appRoleId}')

    RESULT=$(az rest --method POST \
        --uri "https://graph.microsoft.com/v1.0/servicePrincipals/$SP_ID/appRoleAssignments" \
        --headers "Content-Type=application/json" \
        --body "$BODY" \
        -o json 2>&1) && RC=0 || RC=$?

    if [ $RC -eq 0 ]; then
        echo "  Granted successfully"
        echo "$RESULT" | jq -r '"  Assignment ID: \(.id)"' 2>/dev/null || true
    else
        echo "  Failed to grant"
        echo "$RESULT"
        ERRORS=$((ERRORS + 1))
    fi
    echo ""
done

echo "=== Done ==="
if [ $ERRORS -gt 0 ]; then
    echo "$ERRORS permission(s) failed. See errors above."
    exit 1
fi
