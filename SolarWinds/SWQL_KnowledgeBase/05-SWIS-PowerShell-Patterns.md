# SWIS PowerShell Patterns and Best Practices

This document covers practical patterns for automating SolarWinds Orion using the SwisPowerShell module. Each section is self-contained and can be referenced independently.

---

## Installing and Importing the SwisPowerShell Module

The **SwisPowerShell** module is the official PowerShell interface for the SolarWinds Information Service (SWIS). It is published on the PowerShell Gallery and provides cmdlets for querying, creating, updating, and deleting objects in the Orion platform.

```powershell
# Install from PowerShell Gallery (one-time setup)
Install-Module -Name SwisPowerShell -Scope CurrentUser

# If behind a proxy or on an older system, you may need to trust the repository first
Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
Install-Module -Name SwisPowerShell -Scope CurrentUser -Force

# Import the module into the current session
Import-Module SwisPowerShell

# Verify installation and list available cmdlets
Get-Command -Module SwisPowerShell
```

### Available Cmdlets

| Cmdlet | Purpose |
|---|---|
| `Connect-Swis` | Establish an authenticated connection to the Orion server |
| `Get-SwisData` | Execute a SWQL query and return result rows |
| `Get-SwisObject` | Retrieve a single object by its SWIS URI |
| `Set-SwisObject` | Update properties on an existing object by URI |
| `New-SwisObject` | Create a new object in the Orion database |
| `Remove-SwisObject` | Delete an object by its SWIS URI |
| `Invoke-SwisVerb` | Call a verb (action/method) on a SWIS entity |

### Updating the Module

```powershell
# Check current version
(Get-Module SwisPowerShell -ListAvailable).Version

# Update to latest
Update-Module -Name SwisPowerShell

# If upgrading from a very old version, remove and reinstall
Remove-Module SwisPowerShell -Force -ErrorAction SilentlyContinue
Install-Module -Name SwisPowerShell -Scope CurrentUser -Force
```

---

## SWIS Connection Patterns (Connect-Swis)

All SWIS operations require a connection object returned by `Connect-Swis`. There are four authentication methods, each suited to different use cases.

### Method 1: Credential Object (Interactive Use)

Best for ad-hoc scripts where a user is present to enter credentials. The `Get-Credential` cmdlet displays a secure prompt dialog.

```powershell
$creds = Get-Credential -Message "Enter SolarWinds Orion credentials"
$swis = Connect-Swis -Hostname 'orion.company.com' -Credential $creds
```

### Method 2: Username and Password (Scripted/Automated)

Suitable for quick testing or environments where credentials are injected by a secret manager. Avoid hardcoding passwords in production scripts.

```powershell
$swis = Connect-Swis -Hostname 'orion.company.com' -Username 'admin' -Password '<password>'
```

### Method 3: Trusted / Windows Integrated Authentication

Uses the current Windows identity (Kerberos/NTLM). The running account must have a corresponding SolarWinds user mapped to a Windows account. No credentials are passed on the command line.

```powershell
$swis = Connect-Swis -Hostname 'orion.company.com' -Trusted
```

This is the preferred method for scheduled tasks running under a domain service account.

### Method 4: Certificate Authentication (Local Orion Server Only)

Connects using the Orion server's own certificate. This only works when the script runs directly on the Orion server itself. No username or password is needed.

```powershell
$swis = Connect-Swis -Certificate
```

Use this for scripts that run as local scheduled tasks on the Orion polling engine.

### Secure Credential Storage Pattern

For automated scripts that cannot use `-Trusted`, store credentials in an encrypted configuration file. The encryption is tied to the Windows user profile and machine, so the file can only be decrypted by the same user on the same machine.

```powershell
# --- One-time setup: create the encrypted config file ---
$pwdSecure = Read-Host "Enter Orion password" -AsSecureString
$pwdEncStr = ConvertFrom-SecureString $pwdSecure

$config = @{
    Host     = 'orion.company.com'
    User     = 'admin'
    Password = $pwdEncStr
}
$config | ConvertTo-Json | Out-File 'C:\Scripts\orion_config.json'

# --- Runtime: load credentials from the config file ---
$config = Get-Content 'C:\Scripts\orion_config.json' | ConvertFrom-Json
$pwdSecStr = ConvertTo-SecureString $config.Password
$creds = New-Object System.Management.Automation.PSCredential($config.User, $pwdSecStr)
$swis = Connect-Swis -Hostname $config.Host -Credential $creds
```

### Connection Validation Pattern

Always verify the connection is working before proceeding with operations:

```powershell
try {
    $swis = Connect-Swis -Hostname $hostname -Credential $creds
    # Quick validation query
    $test = Get-SwisData $swis "SELECT TOP 1 NodeID FROM Orion.Nodes"
    Write-Host "Connected to $hostname successfully."
}
catch {
    Write-Error "Failed to connect to SolarWinds at $hostname : $($_.Exception.Message)"
    exit 1
}
```

---

## SWIS Query Execution Pattern (Get-SwisData)

`Get-SwisData` executes a SWQL query against the Orion database and returns the results as PowerShell objects. This is the most frequently used cmdlet in SWIS automation.

### Basic Query

```powershell
$results = Get-SwisData $swis "SELECT Caption, IPAddress, Status FROM Orion.Nodes"
```

The returned `$results` is an array of `PSObject` instances with properties matching the selected columns.

### Parameterized Queries (Preventing SWQL Injection)

Always use parameterized queries when incorporating user input or variable data into queries. Parameters are passed as a hashtable and referenced with `@paramName` in the query.

```powershell
# Single parameter
$results = Get-SwisData $swis "SELECT Caption, IPAddress FROM Orion.Nodes WHERE Vendor = @v" @{ v = 'Cisco' }

# Multiple parameters
$results = Get-SwisData $swis @"
SELECT Caption, IPAddress, Status
FROM Orion.Nodes
WHERE Vendor = @vendor AND Status = @status
"@ @{ vendor = 'Cisco'; status = 1 }

# Parameter with LIKE clause
$results = Get-SwisData $swis "SELECT Caption FROM Orion.Nodes WHERE Caption LIKE @pattern" @{ pattern = '%router%' }
```

### Robust Error Handling Wrapper

```powershell
function Invoke-SwqlQuery {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $SwisConnection,
        [Parameter(Mandatory)] [string] $Query,
        [hashtable] $Parameters = @{}
    )

    try {
        if ($Parameters.Count -gt 0) {
            $results = Get-SwisData $SwisConnection -Query $Query -Parameters $Parameters -ErrorAction Stop
        }
        else {
            $results = Get-SwisData $SwisConnection -Query $Query -ErrorAction Stop
        }

        if (-not $results) {
            Write-Verbose "Query returned no results."
            return @()
        }

        return $results
    }
    catch {
        Write-Warning "SWQL query failed: $($_.Exception.Message)"
        Write-Verbose "Query was: $Query"
        return $null
    }
}

# Usage
$nodes = Invoke-SwqlQuery -SwisConnection $swis -Query "SELECT NodeID, Caption FROM Orion.Nodes WHERE Vendor = @v" -Parameters @{ v = 'Cisco' }
```

### Processing and Iterating Results

```powershell
# Iterate through results
$nodes = Get-SwisData $swis "SELECT NodeID, Caption, IPAddress, Status FROM Orion.Nodes"
foreach ($node in $nodes) {
    $statusText = switch ($node.Status) {
        1 { 'Up' }
        2 { 'Down' }
        3 { 'Warning' }
        default { "Unknown ($($node.Status))" }
    }
    Write-Host "$($node.Caption) ($($node.IPAddress)): $statusText"
}
```

### Exporting Results

```powershell
# Export to CSV
$results = Get-SwisData $swis "SELECT Caption, IPAddress, Vendor, MachineType FROM Orion.Nodes"
$results | Export-Csv -Path 'C:\Reports\nodes_inventory.csv' -NoTypeInformation

# Export to JSON
$results | ConvertTo-Json -Depth 5 | Out-File 'C:\Reports\nodes_inventory.json'

# Export to HTML report
$results | ConvertTo-Html -Title "Node Inventory" -PreContent "<h1>SolarWinds Node Report</h1>" |
    Out-File 'C:\Reports\nodes_inventory.html'
```

### Handling Large Result Sets

For queries that return thousands of rows, consider paging:

```powershell
$pageSize = 500
$offset = 0
$allResults = @()

do {
    $page = Get-SwisData $swis @"
SELECT Caption, IPAddress, Status
FROM Orion.Nodes
ORDER BY Caption ASC
WITH ROWS $($offset + 1) TO $($offset + $pageSize)
"@
    if ($page) {
        $allResults += $page
        $offset += $pageSize
    }
} while ($page -and $page.Count -eq $pageSize)

Write-Host "Total nodes retrieved: $($allResults.Count)"
```

---

## SWIS Bulk Update Pattern

Bulk updates in SolarWinds PowerShell follow a two-step pattern: query for the SWIS URIs of the objects to modify, then apply property changes to each URI using `Set-SwisObject`.

### Basic Bulk Update with ForEach Loop

```powershell
# Change poll interval for all Cisco nodes currently set to 300 seconds
$uris = Get-SwisData $swis "SELECT Uri FROM Orion.Nodes WHERE Vendor = 'Cisco' AND PollInterval = 300"

$count = 0
foreach ($uri in $uris) {
    Set-SwisObject $swis -Uri $uri -Properties @{ PollInterval = 120 }
    $count++
}
Write-Host "Updated poll interval on $count nodes."
```

### Pipeline Approach (Concise)

When the query returns only URIs, you can pipe directly into `Set-SwisObject`:

```powershell
Get-SwisData $swis "SELECT Uri FROM Orion.Nodes WHERE PollInterval = 300" |
    ForEach-Object { Set-SwisObject $swis -Uri $_ -Properties @{ PollInterval = 120 } }
```

### Bulk Update Custom Properties

Custom properties are stored on a child object at `{NodeUri}/CustomProperties`:

```powershell
$nodeUris = Get-SwisData $swis "SELECT Uri FROM Orion.Nodes WHERE Vendor = 'Cisco'"
foreach ($uri in $nodeUris) {
    Set-SwisObject $swis -Uri "$uri/CustomProperties" -Properties @{
        Environment = 'Production'
        ManagedBy   = 'NetworkTeam'
        Region      = 'US-East'
    }
}
```

### Bulk Update with Progress Reporting

For large operations, include progress feedback and error resilience:

```powershell
$uris = Get-SwisData $swis "SELECT Uri, Caption FROM Orion.Nodes WHERE Location IS NULL"
$total = $uris.Count
$current = 0
$errors = @()

foreach ($item in $uris) {
    $current++
    Write-Progress -Activity "Updating node custom properties" `
        -Status "$current of $total - $($item.Caption)" `
        -PercentComplete (($current / $total) * 100)

    try {
        Set-SwisObject $swis -Uri "$($item.Uri)/CustomProperties" -Properties @{
            Location = 'Unassigned'
        }
    }
    catch {
        $errors += [PSCustomObject]@{
            Caption = $item.Caption
            Uri     = $item.Uri
            Error   = $_.Exception.Message
        }
    }
}

Write-Progress -Activity "Updating node custom properties" -Completed
Write-Host "Updated $($total - $errors.Count) of $total nodes."
if ($errors.Count -gt 0) {
    Write-Warning "$($errors.Count) nodes failed to update:"
    $errors | Format-Table -AutoSize
}
```

### Bulk Status Change (Unmanage/Remanage Nodes)

```powershell
# Unmanage a set of nodes for a maintenance window
$nodeIds = Get-SwisData $swis @"
SELECT NodeID FROM Orion.Nodes
WHERE Caption LIKE '%lab%'
"@

$start = [DateTime]::UtcNow
$end = $start.AddHours(4)

foreach ($nodeId in $nodeIds) {
    Invoke-SwisVerb $swis 'Orion.Nodes' 'Unmanage' @(
        "N:$nodeId",
        $start,
        $end,
        $false   # $false = Unmanage; $true = Remanage
    )
}
Write-Host "Unmanaged $($nodeIds.Count) lab nodes until $end UTC."
```

---

## SWIS Dashboard Export and Import Pattern

SolarWinds dashboards (Views) can be exported and imported through SWIS verbs. This is useful for migrating dashboards between environments or maintaining version-controlled backups.

### Export All Dashboards

```powershell
$exportDir = 'C:\SolarWinds\DashboardBackups'
if (-not (Test-Path $exportDir)) { New-Item -Path $exportDir -ItemType Directory | Out-Null }

$dashboards = Get-SwisData $swis @"
SELECT ViewID, ViewTitle, ViewType
FROM Orion.Views
WHERE ViewType = 'dashboard'
"@

foreach ($dash in $dashboards) {
    $export = Invoke-SwisVerb $swis 'Orion.Views' 'Export' @($dash.ViewID)
    $safeName = $dash.ViewTitle -replace '[\\/:*?"<>|]', '_'
    $export.InnerXml | Out-File "$exportDir\$safeName.json" -Encoding UTF8
    Write-Host "Exported: $($dash.ViewTitle)"
}

Write-Host "Exported $($dashboards.Count) dashboards to $exportDir"
```

### Export a Single Dashboard by Name

```powershell
$viewTitle = 'Network Overview'
$viewId = Get-SwisData $swis "SELECT ViewID FROM Orion.Views WHERE ViewTitle = @t" @{ t = $viewTitle }

if ($viewId) {
    $export = Invoke-SwisVerb $swis 'Orion.Views' 'Export' @($viewId)
    $export.InnerXml | Out-File "C:\SolarWinds\$viewTitle.json" -Encoding UTF8
    Write-Host "Dashboard exported successfully."
}
else {
    Write-Warning "Dashboard '$viewTitle' not found."
}
```

### Import a Dashboard

```powershell
$dashJson = Get-Content 'C:\SolarWinds\DashboardBackups\Network_Overview.json' -Raw
$result = Invoke-SwisVerb $swis 'Orion.Views' 'Import' @($dashJson)
Write-Host "Dashboard imported. Result: $($result.InnerXml)"
```

### Migrate Dashboards Between Orion Servers

```powershell
# Connect to source and destination
$swisSource = Connect-Swis -Hostname 'orion-dev.company.com' -Trusted
$swisDest   = Connect-Swis -Hostname 'orion-prod.company.com' -Trusted

# Export from source
$dashboards = Get-SwisData $swisSource "SELECT ViewID, ViewTitle FROM Orion.Views WHERE ViewType = 'dashboard'"

foreach ($dash in $dashboards) {
    $export = Invoke-SwisVerb $swisSource 'Orion.Views' 'Export' @($dash.ViewID)

    try {
        Invoke-SwisVerb $swisDest 'Orion.Views' 'Import' @($export.InnerXml)
        Write-Host "Migrated: $($dash.ViewTitle)"
    }
    catch {
        Write-Warning "Failed to migrate '$($dash.ViewTitle)': $($_.Exception.Message)"
    }
}
```

---

## SWIS Alert Export and Import Pattern

Alert configurations can be backed up and restored through the `Orion.AlertConfigurations` entity. This is critical for disaster recovery and for promoting alerts across dev/staging/production environments.

### Export All Alert Configurations

```powershell
$alertIds = Get-SwisData $swis "SELECT AlertID FROM Orion.AlertConfigurations"

if (-not $alertIds) {
    Write-Warning "No alert configurations found."
    return
}

# Export expects an array of AlertIDs
$exportResult = Invoke-SwisVerb $swis 'Orion.AlertConfigurations' 'Export' @(, $alertIds)

$backupPath = "C:\SolarWinds\Backups\alerts_backup_$(Get-Date -Format 'yyyyMMdd_HHmmss').xml"
$exportResult.InnerXml | Out-File $backupPath -Encoding UTF8
Write-Host "Exported $($alertIds.Count) alerts to $backupPath"
```

### Export Specific Alerts by Name Pattern

```powershell
$alertIds = Get-SwisData $swis @"
SELECT AlertID FROM Orion.AlertConfigurations
WHERE Name LIKE '%CPU%' OR Name LIKE '%Memory%'
"@

$exportResult = Invoke-SwisVerb $swis 'Orion.AlertConfigurations' 'Export' @(, $alertIds)
$exportResult.InnerXml | Out-File 'C:\SolarWinds\Backups\cpu_memory_alerts.xml' -Encoding UTF8
Write-Host "Exported $($alertIds.Count) CPU/Memory alerts."
```

### Import Alerts to Another Server

```powershell
$swisTarget = Connect-Swis -Hostname 'orion-prod.company.com' -Trusted

$alertXml = Get-Content 'C:\SolarWinds\Backups\alerts_backup.xml' -Raw
$importResult = Invoke-SwisVerb $swisTarget 'Orion.AlertConfigurations' 'Import' @($alertXml)
Write-Host "Import result: $($importResult.InnerXml)"
```

### Alert Backup Rotation Script

```powershell
# Keep the last 30 days of alert backups
$backupDir = 'C:\SolarWinds\Backups\Alerts'
if (-not (Test-Path $backupDir)) { New-Item -Path $backupDir -ItemType Directory | Out-Null }

# Export current alerts
$alertIds = Get-SwisData $swis "SELECT AlertID FROM Orion.AlertConfigurations"
$exportResult = Invoke-SwisVerb $swis 'Orion.AlertConfigurations' 'Export' @(, $alertIds)
$exportResult.InnerXml | Out-File "$backupDir\alerts_$(Get-Date -Format 'yyyyMMdd').xml" -Encoding UTF8

# Remove backups older than 30 days
Get-ChildItem $backupDir -Filter '*.xml' |
    Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-30) } |
    Remove-Item -Force

Write-Host "Alert backup completed. Older backups cleaned up."
```

---

## SWIS Group/Container Management Pattern

Groups (containers) in SolarWinds organize nodes and other objects for monitoring, reporting, and dependency mapping. Groups can have static members (explicitly added) or dynamic members (defined by a filter expression that auto-populates).

### Create a Group with Dynamic Membership

```powershell
# Define dynamic members using a filter expression
$memberDefinition = @"
<ArrayOfMemberDefinitionInfo xmlns='http://schemas.solarwinds.com/2008/Orion'>
  <MemberDefinitionInfo>
    <Name>Cisco Devices</Name>
    <Definition>filter:/Orion.Nodes[Vendor='Cisco']</Definition>
  </MemberDefinitionInfo>
</ArrayOfMemberDefinitionInfo>
"@

$containerId = (Invoke-SwisVerb $swis 'Orion.Container' 'CreateContainer' @(
    "Cisco Network Devices",  # Name
    "admin",                  # Owner
    60,                       # RefreshFrequency (seconds)
    0,                        # StatusCalculator: 0=Best, 1=Mixed, 2=Worst
    "Auto-created group for all Cisco devices",  # Description
    $true,                    # PollingEnabled
    $memberDefinition         # Members XML
)).InnerText

Write-Host "Created group with ContainerID: $containerId"
```

### Create a Group with Multiple Dynamic Member Types

```powershell
$memberDefinition = @"
<ArrayOfMemberDefinitionInfo xmlns='http://schemas.solarwinds.com/2008/Orion'>
  <MemberDefinitionInfo>
    <Name>Production Routers</Name>
    <Definition>filter:/Orion.Nodes[Vendor='Cisco' AND MachineType LIKE '%Router%']</Definition>
  </MemberDefinitionInfo>
  <MemberDefinitionInfo>
    <Name>Production Switches</Name>
    <Definition>filter:/Orion.Nodes[Vendor='Cisco' AND MachineType LIKE '%Switch%']</Definition>
  </MemberDefinitionInfo>
  <MemberDefinitionInfo>
    <Name>Production Interfaces</Name>
    <Definition>filter:/Orion.NPM.Interfaces[Status=1]</Definition>
  </MemberDefinitionInfo>
</ArrayOfMemberDefinitionInfo>
"@

$containerId = (Invoke-SwisVerb $swis 'Orion.Container' 'CreateContainer' @(
    "Production Network Infrastructure",
    "admin",
    120,
    2,   # WorstStatus - group shows worst member status
    "All production Cisco routers, switches, and active interfaces",
    $true,
    $memberDefinition
)).InnerText

Write-Host "Created production group: ContainerID $containerId"
```

### Add a Static Member to an Existing Group

```powershell
# Get the container ID for the target group
$containerId = Get-SwisData $swis "SELECT ContainerID FROM Orion.Container WHERE Name = @n" @{ n = 'Critical Servers' }

# Get the node URI you want to add
$nodeUri = Get-SwisData $swis "SELECT Uri FROM Orion.Nodes WHERE Caption = @c" @{ c = 'web-server-01' }

if ($containerId -and $nodeUri) {
    Invoke-SwisVerb $swis 'Orion.Container' 'AddDefinition' @(
        $containerId,
        "web-server-01",   # Member name
        "Orion.Nodes",     # Entity type
        $nodeUri,           # URI of the member
        $false              # IsDynamic = false (static member)
    )
    Write-Host "Added web-server-01 to Critical Servers group."
}
```

### Delete a Group

```powershell
$containerId = Get-SwisData $swis "SELECT ContainerID FROM Orion.Container WHERE Name = @n" @{ n = 'Old Test Group' }

if ($containerId) {
    Invoke-SwisVerb $swis 'Orion.Container' 'DeleteContainer' @($containerId)
    Write-Host "Deleted container $containerId."
}
```

### List All Groups and Their Member Counts

```powershell
$groups = Get-SwisData $swis @"
SELECT c.ContainerID, c.Name, c.Description, c.StatusDescription,
       COUNT(cm.ContainerMemberID) AS MemberCount
FROM Orion.Container c
LEFT JOIN Orion.ContainerMembers cm ON c.ContainerID = cm.ContainerID
GROUP BY c.ContainerID, c.Name, c.Description, c.StatusDescription
ORDER BY c.Name
"@

$groups | Format-Table ContainerID, Name, MemberCount, StatusDescription -AutoSize
```

---

## SWIS Module Detection Pattern

Before running module-specific queries (e.g., SAM application monitors, NCM config downloads), verify that the required module is installed on the Orion platform. This prevents confusing errors when a query references an entity that does not exist.

### Check All SolarWinds Modules

```powershell
# Map of friendly module names to their internal identifiers
$modules = @{
    'NPM'  = 'NPM'
    'SAM'  = 'APM'
    'NCM'  = 'NCM'
    'IPAM' = 'IPAM'
    'UDT'  = 'UDT'
    'VNQM' = 'VoIP'
    'WPM'  = 'SEUM'
    'NTA'  = 'NTA'
    'VMAN' = 'VIM'
    'LA'   = 'OLM'
    'SCM'  = 'SCM'
    'SRM'  = 'SRM'
}

$installedModules = @()

foreach ($module in $modules.GetEnumerator()) {
    $count = Get-SwisData $swis "SELECT COUNT(*) AS Installed FROM Orion.InstalledModule WHERE Name = '$($module.Value)'"
    if ($count -eq 1) {
        Write-Host "[Installed]     $($module.Key) ($($module.Value))" -ForegroundColor Green
        $installedModules += $module.Key
    }
    else {
        Write-Host "[Not Installed] $($module.Key) ($($module.Value))" -ForegroundColor DarkGray
    }
}

Write-Host "`nInstalled modules: $($installedModules -join ', ')"
```

### Guard Clause for Module-Specific Queries

Use this pattern at the top of scripts that depend on a specific module:

```powershell
function Test-SwisModuleInstalled {
    param(
        [Parameter(Mandatory)] $SwisConnection,
        [Parameter(Mandatory)] [string] $ModuleName
    )

    $count = Get-SwisData $SwisConnection "SELECT COUNT(*) AS C FROM Orion.InstalledModule WHERE Name = @m" @{ m = $ModuleName }
    return ($count -eq 1)
}

# Example: guard an NCM script
if (-not (Test-SwisModuleInstalled $swis 'NCM')) {
    Write-Error "NCM module is not installed. This script requires Network Configuration Manager."
    exit 1
}

# Safe to run NCM-specific queries
$configs = Get-SwisData $swis "SELECT NodeID, DownloadTime, ConfigType FROM NCM.ConfigArchive"
```

### Retrieve Module Version Information

```powershell
$moduleInfo = Get-SwisData $swis @"
SELECT Name, Description, Version, InstallDate
FROM Orion.InstalledModule
ORDER BY Name
"@

$moduleInfo | Format-Table Name, Version, InstallDate -AutoSize
```

---

## SWIS Error Handling Best Practices

Robust error handling is essential for production SolarWinds automation scripts. Network issues, credential expiration, invalid queries, and missing entities can all cause failures that need graceful handling.

### Connection Error Handling

```powershell
function Connect-SwisReliable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Hostname,
        [PSCredential] $Credential,
        [switch] $Trusted,
        [int] $MaxRetries = 3,
        [int] $RetryDelaySeconds = 10
    )

    for ($attempt = 1; $attempt -le $MaxRetries; $attempt++) {
        try {
            if ($Trusted) {
                $swis = Connect-Swis -Hostname $Hostname -Trusted
            }
            elseif ($Credential) {
                $swis = Connect-Swis -Hostname $Hostname -Credential $Credential
            }
            else {
                throw "Either -Credential or -Trusted must be specified."
            }

            # Validate connection with a lightweight query
            $null = Get-SwisData $swis "SELECT TOP 1 NodeID FROM Orion.Nodes" -ErrorAction Stop
            Write-Verbose "Connected to $Hostname on attempt $attempt."
            return $swis
        }
        catch {
            Write-Warning "Connection attempt $attempt of $MaxRetries failed: $($_.Exception.Message)"
            if ($attempt -lt $MaxRetries) {
                Start-Sleep -Seconds $RetryDelaySeconds
            }
        }
    }

    throw "Failed to connect to $Hostname after $MaxRetries attempts."
}

# Usage
try {
    $swis = Connect-SwisReliable -Hostname 'orion.company.com' -Trusted -MaxRetries 3
}
catch {
    Write-Error $_.Exception.Message
    exit 1
}
```

### Query Error Handling

```powershell
# Basic try/catch around a query
try {
    $data = Get-SwisData $swis -Query $query -ErrorAction Stop
}
catch {
    Write-Warning "SWQL Error: $($_.Exception.Message)"
}

# Distinguish between different error types
try {
    $data = Get-SwisData $swis -Query "SELECT BadColumn FROM Orion.Nodes" -ErrorAction Stop
}
catch [System.ServiceModel.FaultException] {
    Write-Warning "SWQL syntax or schema error: $($_.Exception.Message)"
}
catch [System.ServiceModel.CommunicationException] {
    Write-Warning "Communication error (network/timeout): $($_.Exception.Message)"
}
catch {
    Write-Warning "Unexpected error: $($_.Exception.GetType().FullName) - $($_.Exception.Message)"
}
```

### Checking for Empty Results

```powershell
$results = Get-SwisData $swis "SELECT NodeID FROM Orion.Nodes WHERE Caption = 'NonExistentHost'"

if (-not $results -or @($results).Count -eq 0) {
    Write-Warning "No matching nodes found."
}
else {
    Write-Host "Found $(@($results).Count) matching node(s)."
}
```

**Important:** Wrap `$results` in `@()` when checking `.Count` because a single result is returned as a scalar, not an array. Using `@($results).Count` ensures correct behavior regardless of how many rows are returned.

### Verb Invocation Error Handling

```powershell
try {
    $result = Invoke-SwisVerb $swis 'Orion.Nodes' 'Unmanage' @(
        "N:$nodeId", $start, $end, $false
    )
    Write-Host "Verb executed successfully. Result: $($result.InnerXml)"
}
catch {
    Write-Warning "Invoke-SwisVerb failed: $($_.Exception.Message)"
}
```

### Comprehensive Script Template with SWIS Error Handling

A complete template that combines all error handling patterns:

```powershell
#Requires -Module SwisPowerShell

[CmdletBinding()]
param(
    [string] $OrionHost = 'orion.company.com',
    [string] $OutputPath = 'C:\Reports'
)

$ErrorActionPreference = 'Stop'

# --- Connect ---
try {
    $swis = Connect-Swis -Hostname $OrionHost -Trusted
    $null = Get-SwisData $swis "SELECT TOP 1 NodeID FROM Orion.Nodes"
    Write-Verbose "Connected to $OrionHost"
}
catch {
    Write-Error "Connection failed: $($_.Exception.Message)"
    exit 1
}

# --- Query ---
$query = @"
SELECT n.NodeID, n.Caption, n.IPAddress, n.Vendor, n.Status,
       n.CPULoad, n.PercentMemoryUsed
FROM Orion.Nodes n
WHERE n.Status <> 1
ORDER BY n.Caption
"@

try {
    $downNodes = Get-SwisData $swis -Query $query -ErrorAction Stop
}
catch {
    Write-Error "Query failed: $($_.Exception.Message)"
    exit 1
}

# --- Process results ---
if (-not $downNodes -or @($downNodes).Count -eq 0) {
    Write-Host "All nodes are up. No report generated."
    exit 0
}

Write-Host "Found $(@($downNodes).Count) node(s) not in Up status."

# --- Export ---
if (-not (Test-Path $OutputPath)) { New-Item -Path $OutputPath -ItemType Directory | Out-Null }
$reportFile = Join-Path $OutputPath "down_nodes_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
$downNodes | Export-Csv -Path $reportFile -NoTypeInformation
Write-Host "Report saved to $reportFile"
```

### Common SWIS Errors and Solutions

| Error | Cause | Solution |
|---|---|---|
| `The remote server returned an error: (401) Unauthorized` | Invalid credentials or expired password | Verify credentials; check account is not locked |
| `Could not find entity` | Referencing an entity from an uninstalled module | Use module detection pattern before querying |
| `Unknown column` | Typo in column name or column does not exist in schema | Use SWQL Studio to verify schema and column names |
| `The request channel timed out` | Query too large or server under heavy load | Add filters, use `TOP N`, or increase timeout |
| `Cannot connect to the remote server` | Orion server unreachable or SWIS service stopped | Verify network connectivity and SolarWinds services |
