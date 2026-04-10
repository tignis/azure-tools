<#
.SYNOPSIS
    Grant a service principal access to a SharePoint site via Sites.Selected.

.DESCRIPTION
    Two-step process:
      1. Grant Sites.Selected Graph app role to the service principal
      2. Grant site-level permission (read/write/fullcontrol) on a specific site

    Run directly from GitHub:
      irm "https://raw.githubusercontent.com/tignis/azure-tools/refs/heads/main/scripts/powershell/grant-site-access.ps1" `
          -OutFile grant-site-access.ps1
      ./grant-site-access.ps1 `
          -SpObjectId "<service-principal-object-id>" `
          -AppId "<application-client-id>" `
          -SiteId "<tenant>.sharepoint.com,<site-guid>,<web-guid>"

.PARAMETER AppName
    Azure Web App name (to look up managed identity). Use with -ResourceGroup.

.PARAMETER ResourceGroup
    Resource group of the web app.

.PARAMETER SpObjectId
    Service principal object ID (skip web app lookup).

.PARAMETER AppId
    Application (client) ID (skip web app lookup).

.PARAMETER SiteId
    SharePoint site ID in format: hostname,site-guid,web-guid
    Find it at: https://<tenant>.sharepoint.com/sites/<name>/_api/site/id (site guid)
                https://<tenant>.sharepoint.com/sites/<name>/_api/web/id  (web guid)

.PARAMETER Role
    Site permission: read, write, or fullcontrol (default: fullcontrol)

.PARAMETER DisplayName
    Display name for the permission entry.

.PARAMETER SkipAppRole
    Skip granting Sites.Selected app role (if already granted).

.EXAMPLE
    ./grant-site-access.ps1 -SpObjectId "abc123" -AppId "def456" -SiteId "contoso.sharepoint.com,guid1,guid2"

.EXAMPLE
    ./grant-site-access.ps1 -AppName my-web-app -ResourceGroup my-rg -SiteId "contoso.sharepoint.com,guid1,guid2" -Role read
#>

param(
    [string]$AppName,
    [string]$ResourceGroup,
    [string]$SpObjectId,
    [string]$AppId,
    [Parameter(Mandatory)][string]$SiteId,
    [ValidateSet("read","write","fullcontrol")][string]$Role = "fullcontrol",
    [string]$DisplayName,
    [switch]$SkipAppRole
)

$ErrorActionPreference = "Stop"

# --- Resolve service principal ---
if (-not $SpObjectId -or -not $AppId) {
    if (-not $AppName -or -not $ResourceGroup) {
        Write-Error "Provide -AppName + -ResourceGroup, or -SpObjectId + -AppId"
        return
    }

    Write-Host "Looking up managed identity for $AppName..." -ForegroundColor Cyan
    $PrincipalId = az webapp identity show --resource-group $ResourceGroup --name $AppName --query principalId -o tsv 2>$null
    if (-not $PrincipalId) {
        Write-Error "Could not get managed identity for $AppName in $ResourceGroup"
        return
    }

    if (-not $SpObjectId) { $SpObjectId = az ad sp show --id $PrincipalId --query id -o tsv }
    if (-not $AppId) { $AppId = az ad sp show --id $PrincipalId --query appId -o tsv }
}

if (-not $DisplayName) { $DisplayName = if ($AppName) { $AppName } else { $AppId } }

Write-Host ""
Write-Host "  SP Object ID: $SpObjectId"
Write-Host "  App ID:       $AppId"
Write-Host "  Site:         $SiteId"
Write-Host "  Role:         $Role"
Write-Host ""

# --- Connect to Microsoft Graph ---
Write-Host "Connecting to Microsoft Graph..." -ForegroundColor Cyan
$Scopes = @("Application.ReadWrite.All", "AppRoleAssignment.ReadWrite.All", "Sites.FullControl.All")
Write-Host "  Scopes: $($Scopes -join ', ')" -ForegroundColor Gray

try {
    Connect-MgGraph -Scopes $Scopes -UseDeviceCode -ErrorAction Stop
} catch {
    Write-Host "Connection failed: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Install the module if needed: Install-Module Microsoft.Graph -Scope CurrentUser" -ForegroundColor Yellow
    return
}

# --- Step 1: Grant Sites.Selected app role ---
$GraphAppId = "00000003-0000-0000-c000-000000000000"
$SitesSelectedRoleId = "883ea226-0bf2-4a8f-9f9d-92c9162a727d"

if (-not $SkipAppRole) {
    Write-Host "Step 1: Granting Sites.Selected app role..." -ForegroundColor Blue

    $GraphSp = Get-MgServicePrincipal -Filter "appId eq '$GraphAppId'"

    # Check if already granted
    $Existing = Invoke-MgGraphRequest -Method GET `
        -Uri "https://graph.microsoft.com/v1.0/servicePrincipals/$SpObjectId/appRoleAssignments" `
        -ErrorAction SilentlyContinue

    $AlreadyGranted = $Existing.value | Where-Object {
        $_.resourceId -eq $GraphSp.Id -and $_.appRoleId -eq $SitesSelectedRoleId
    }

    if ($AlreadyGranted) {
        Write-Host "  Already granted" -ForegroundColor Yellow
    } else {
        try {
            Invoke-MgGraphRequest -Method POST `
                -Uri "https://graph.microsoft.com/v1.0/servicePrincipals/$SpObjectId/appRoleAssignedTo" `
                -Body @{
                    principalId = $SpObjectId
                    resourceId  = $GraphSp.Id
                    appRoleId   = $SitesSelectedRoleId
                } | Out-Null
            Write-Host "  Granted" -ForegroundColor Green
        } catch {
            if ($_.Exception.Message -match "already exists|Permission being assigned") {
                Write-Host "  Already granted" -ForegroundColor Yellow
            } else {
                Write-Host "  Failed: $($_.Exception.Message)" -ForegroundColor Red
                return
            }
        }
    }
} else {
    Write-Host "Step 1: Skipped (-SkipAppRole)" -ForegroundColor Gray
}

# --- Step 2: Grant site-level permission ---
Write-Host "Step 2: Granting $Role on site..." -ForegroundColor Blue

# Check existing permissions
try {
    $ExistingPerms = Invoke-MgGraphRequest -Method GET `
        -Uri "https://graph.microsoft.com/v1.0/sites/$SiteId/permissions"
} catch {
    Write-Host "  Failed to read site permissions: $($_.Exception.Message)" -ForegroundColor Red
    return
}

$ExistingPerm = $ExistingPerms.value | Where-Object {
    $_.grantedToIdentitiesV2.application.id -contains $AppId
}

if ($ExistingPerm) {
    $CurrentRoles = $ExistingPerm.roles -join ", "
    Write-Host "  Already has permission (id: $($ExistingPerm.id), roles: $CurrentRoles)" -ForegroundColor Yellow
    $yn = Read-Host "  Update to '$Role'? (y/n) [n]"
    if ($yn -match "^[Yy]$") {
        Invoke-MgGraphRequest -Method PATCH `
            -Uri "https://graph.microsoft.com/v1.0/sites/$SiteId/permissions/$($ExistingPerm.id)" `
            -Body @{ roles = @($Role) } | Out-Null
        Write-Host "  Updated to $Role" -ForegroundColor Green
    }
} else {
    try {
        $Response = Invoke-MgGraphRequest -Method POST `
            -Uri "https://graph.microsoft.com/v1.0/sites/$SiteId/permissions" `
            -Body @{
                roles = @($Role)
                grantedToIdentities = @(@{
                    application = @{
                        id          = $AppId
                        displayName = $DisplayName
                    }
                })
            }
        Write-Host "  Granted $Role (id: $($Response.id))" -ForegroundColor Green
    } catch {
        Write-Host "  Failed: $($_.Exception.Message)" -ForegroundColor Red
        return
    }
}

Write-Host ""
Write-Host "Done - $DisplayName has $Role on site" -ForegroundColor Green
Write-Host ""
