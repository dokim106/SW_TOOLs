# SWIS CRUD Operations Reference

## SWIS Create Operation (New-SwisObject)

Creating new entities in SolarWinds via PowerShell.

- **Cmdlet:** `New-SwisObject`
- **Parameters:** SwisConnection, EntityType (string), Properties (hashtable)
- **Returns:** The SWIS URI of the newly created entity
- **Key behavior:** The entity type must match a writable SWIS entity. Required properties vary by entity type; omitting a required property produces an error from the Information Service.

### SWIS Create Examples

```powershell
# Create a new poller for a node
$pollerUri = New-SwisObject $swis -EntityType 'Orion.Pollers' -Properties @{
    PollerType    = 'N.Details.SNMP.Generic'
    NetObject     = 'N:1'
    NetObjectType = 'N'
    NetObjectID   = 1
}

# Create a custom property value
New-SwisObject $swis -EntityType 'Orion.NodesCustomProperties' -Properties @{
    NodeID      = 42
    City        = 'Dallas'
    Environment = 'Production'
}

# Create a new credential set
$credUri = New-SwisObject $swis -EntityType 'Orion.Credential' -Properties @{
    Name            = 'SNMPv2-ReadOnly'
    CredentialType  = 'SolarWinds.Orion.Core.Models.Credentials.SnmpCredentialsV2'
    CredentialOwner = 'Orion'
}
```

### SWIS Create via REST API

```
POST https://{host}:17778/SolarWinds/InformationService/v3/Json/Create/{EntityType}
Content-Type: application/json
Body: { "City": "Dallas", "Environment": "Production" }
```

The REST response returns the URI of the created entity as a plain string.

---

## SWIS Read Operation (Get-SwisObject)

Reading entity properties by SWIS URI.

- **Cmdlet:** `Get-SwisObject`
- **Parameters:** SwisConnection, Uri (string)
- **Returns:** PSObject with all entity properties
- **Key behavior:** Retrieves a single entity by its full SWIS URI. For bulk or filtered reads, use `Get-SwisData` with a SWQL query instead.

### SWIS Read Examples

```powershell
# Read node properties by URI
$node = Get-SwisObject $swis -Uri 'swis://localhost/Orion/Orion.Nodes/NodeID=1'
$node.Caption
$node.IPAddress
$node.Status

# Read custom properties for a specific node
$customProps = Get-SwisObject $swis -Uri 'swis://localhost/Orion/Orion.Nodes/NodeID=1/CustomProperties'
$customProps.City
$customProps.Environment

# Read a specific interface
$iface = Get-SwisObject $swis -Uri 'swis://localhost/Orion/Orion.NPM.Interfaces/InterfaceID=5'
$iface.InterfaceName
$iface.InBandwidth
```

### SWIS Read vs SWQL Query (Get-SwisData)

```powershell
# Query-based reading (preferred for bulk/filtered reads)
$nodes = Get-SwisData $swis "SELECT NodeID, Caption, IPAddress FROM Orion.Nodes WHERE Vendor='Cisco'"

# Get-SwisObject reads ONE entity by URI; Get-SwisData runs a SWQL query returning rows
# Use Get-SwisData when you need filtering, joins, aggregations, or multiple rows
# Use Get-SwisObject when you already have the URI and want all properties
```

### SWIS Read via REST API

```
GET https://{host}:17778/SolarWinds/InformationService/v3/Json/swis://localhost/Orion/Orion.Nodes/NodeID=1
```

---

## SWIS Update Operation (Set-SwisObject)

Updating entity properties by SWIS URI.

- **Cmdlet:** `Set-SwisObject`
- **Parameters:** SwisConnection, Uri (string, accepts pipeline input), Properties (hashtable)
- **Key behavior:** Only the properties specified in the hashtable are updated; all other properties remain unchanged. Supports pipeline input for bulk updates.

### SWIS Update Examples

```powershell
# Update a single node caption
Set-SwisObject $swis -Uri 'swis://localhost/Orion/Orion.Nodes/NodeID=1' -Properties @{
    Caption = 'CoreSwitch-01'
}

# Bulk update via pipeline - change poll interval for all nodes currently at 300s
Get-SwisData $swis "SELECT Uri FROM Orion.Nodes WHERE PollInterval=300" |
    Set-SwisObject $swis -Properties @{ PollInterval = 120 }

# Update custom properties for a node
Set-SwisObject $swis -Uri 'swis://localhost/Orion/Orion.Nodes/NodeID=1/CustomProperties' -Properties @{
    City       = 'Austin'
    Department = 'Engineering'
}

# Change community string for SNMP-monitored nodes
$uris = Get-SwisData $swis "SELECT Uri FROM Orion.Nodes WHERE ObjectSubType='SNMP' AND Community='oldstring'"
foreach ($uri in $uris) {
    Set-SwisObject $swis -Uri $uri -Properties @{ Community = 'newstring' }
}

# Update interface custom bandwidth
Set-SwisObject $swis -Uri 'swis://localhost/Orion/Orion.NPM.Interfaces/InterfaceID=10' -Properties @{
    CustomBandwidth  = 1000000000
    InBandwidth      = 1000000000
    OutBandwidth     = 1000000000
}
```

### SWIS Update via REST API

```
POST https://{host}:17778/SolarWinds/InformationService/v3/Json/swis://localhost/Orion/Orion.Nodes/NodeID=1
Content-Type: application/json
Body: { "Caption": "CoreSwitch-01" }
```

Note: Updates use POST (not PUT or PATCH) in the SWIS REST API.

---

## SWIS Delete Operation (Remove-SwisObject)

Deleting entities by SWIS URI.

- **Cmdlet:** `Remove-SwisObject`
- **Parameters:** SwisConnection, Uri (string, accepts pipeline input)
- **Returns:** Nothing on success
- **CAUTION:** Deletion is permanent with no undo. Deleting a node removes all associated pollers, interfaces, volumes, and historical data.

### SWIS Delete Examples

```powershell
# Delete a specific poller
Remove-SwisObject $swis -Uri 'swis://localhost/Orion/Orion.Pollers/PollerID=123'

# Delete multiple interfaces matching criteria (e.g., Status=4 means "down")
Get-SwisData $swis "SELECT Uri FROM Orion.NPM.Interfaces WHERE Status=4" |
    Remove-SwisObject $swis

# Delete a node and all its child objects
$nodeUri = Get-SwisData $swis "SELECT Uri FROM Orion.Nodes WHERE Caption='DecommissionedHost'"
Remove-SwisObject $swis -Uri $nodeUri

# Delete all pollers for a specific node before re-adding
Get-SwisData $swis "SELECT Uri FROM Orion.Pollers WHERE NetObjectID=1 AND NetObjectType='N'" |
    Remove-SwisObject $swis
```

### SWIS Delete via REST API

```
DELETE https://{host}:17778/SolarWinds/InformationService/v3/Json/swis://localhost/Orion/Orion.Nodes/NodeID=1
```

### SWIS Delete Safety Pattern

```powershell
# Always preview before bulk delete
$targets = Get-SwisData $swis "SELECT Uri, Caption FROM Orion.Nodes WHERE LastSync < ADDDAY(-90, GETUTCDATE())"
Write-Host "About to delete $($targets.Count) nodes:"
$targets | Format-Table Caption, Uri
$confirm = Read-Host "Type YES to confirm deletion"
if ($confirm -eq 'YES') {
    $targets.Uri | Remove-SwisObject $swis
    Write-Host "Deleted $($targets.Count) nodes."
}
```

---

## SWIS Invoke Verb Operations (Invoke-SwisVerb)

Execute methods (verbs) on SWIS entity types. Verbs perform actions that do not fit the standard CRUD model, such as unmanaging nodes, acknowledging alerts, or creating groups.

- **Cmdlet:** `Invoke-SwisVerb`
- **Parameters:** SwisConnection, EntityName (string), Verb (string), Arguments (array)
- **Returns:** An XmlElement containing the verb's response (if any)
- **Key behavior:** Arguments must be passed as an array. For a single-element array argument, use the `,` (comma) operator to prevent PowerShell from unwrapping it.

### SWIS Invoke Verb: Unmanage / Remanage a Node

```powershell
# Unmanage a node for 24 hours (maintenance window)
$now   = [DateTime]::UtcNow
$later = $now.AddDays(1)
Invoke-SwisVerb $swis 'Orion.Nodes' 'Unmanage' @("N:1", $now, $later, "false")

# Remanage the node immediately
Invoke-SwisVerb $swis 'Orion.Nodes' 'Remanage' @("N:1")

# Unmanage multiple nodes
$nodeIds = Get-SwisData $swis "SELECT NodeID FROM Orion.Nodes WHERE Caption LIKE 'DR-%'"
foreach ($id in $nodeIds) {
    Invoke-SwisVerb $swis 'Orion.Nodes' 'Unmanage' @("N:$id", $now, $later, "false")
}
```

### SWIS Invoke Verb: Acknowledge an Alert

```powershell
# Acknowledge a single alert
Invoke-SwisVerb $swis 'Orion.AlertActive' 'Acknowledge' @(@(42), "Acknowledged by automation script")

# Acknowledge multiple active alerts
$alertObjectIds = Get-SwisData $swis "SELECT AlertObjectID FROM Orion.AlertActive WHERE AlertMessage LIKE '%disk%'"
if ($alertObjectIds.Count -gt 0) {
    Invoke-SwisVerb $swis 'Orion.AlertActive' 'Acknowledge' @($alertObjectIds, "Bulk acknowledge - disk alerts")
}
```

### SWIS Invoke Verb: Create a Container (Group)

```powershell
# Define group members via XML
$memberXml = @"
<ArrayOfMemberDefinitionInfo xmlns='http://schemas.solarwinds.com/2008/Orion'>
  <MemberDefinitionInfo>
    <Name>Windows Servers</Name>
    <Definition>filter:/Orion.Nodes[Vendor='Windows']</Definition>
  </MemberDefinitionInfo>
</ArrayOfMemberDefinitionInfo>
"@

$containerId = (Invoke-SwisVerb $swis 'Orion.Container' 'CreateContainer' @(
    "My Group",           # Name
    "owner",              # Owner
    60,                   # RefreshFrequency
    0,                    # StatusCalculator (0 = worst status)
    "Group description",  # Description
    $true,                # Polling enabled
    $memberXml            # Member definitions
)).InnerText

Write-Host "Created container with ID: $containerId"
```

### SWIS Invoke Verb: Export and Import Alerts

```powershell
# Export all alert configurations
$alertIds = Get-SwisData $swis "SELECT AlertID FROM Orion.AlertConfigurations"
$exportXml = Invoke-SwisVerb $swis 'Orion.AlertConfigurations' 'Export' @(,$alertIds)
$exportXml.InnerXml | Out-File 'C:\Backup\alerts_export.xml'

# Import alerts from backup
$importXml = Get-Content 'C:\Backup\alerts_export.xml' -Raw
Invoke-SwisVerb $swis 'Orion.AlertConfigurations' 'Import' @($importXml)
```

### SWIS Invoke Verb: Node Discovery

```powershell
# Start a discovery using a saved discovery profile
$profileId = Get-SwisData $swis "SELECT ProfileID FROM Orion.DiscoveryProfiles WHERE Name='My Discovery'"
Invoke-SwisVerb $swis 'Orion.Discovery' 'StartDiscovery' @($profileId)
```

### SWIS Invoke Verb: Mute and Unmute Alerts

```powershell
# Mute alerts on a node (suppress alerting during maintenance)
$now   = [DateTime]::UtcNow
$until = $now.AddHours(4)
Invoke-SwisVerb $swis 'Orion.AlertSuppression' 'SuppressAlerts' @(@("N:1"), $until)

# Resume alerting
Invoke-SwisVerb $swis 'Orion.AlertSuppression' 'ResumeAlerts' @(,@("N:1"))
```

---

## SWIS REST API Endpoints Reference

All SWIS REST API endpoints are available under the base URL:

```
https://{host}:17778/SolarWinds/InformationService/v3/Json/
```

Authentication uses HTTP Basic (username/password) over HTTPS.

### SWIS REST Endpoint Summary

| Operation | HTTP Method | Endpoint                          |
|-----------|-------------|-----------------------------------|
| Query     | POST        | `/Query`                          |
| Create    | POST        | `/Create/{EntityType}`            |
| Read      | GET         | `/{Uri}`                          |
| Update    | POST        | `/{Uri}`                          |
| Delete    | DELETE      | `/{Uri}`                          |
| Invoke    | POST        | `/Invoke/{EntityType}/{Verb}`     |

### SWIS REST Query Body Format

```json
{
    "query": "SELECT Caption, IPAddress FROM Orion.Nodes WHERE NodeID=@id",
    "parameters": { "id": 1 }
}
```

### SWIS REST API PowerShell Examples

```powershell
# Establish a REST session (certificate validation may need bypassing in lab environments)
$cred = Get-Credential
$baseUrl = "https://orionserver:17778/SolarWinds/InformationService/v3/Json"

# Query via REST
$body = @{
    query      = "SELECT TOP 10 NodeID, Caption, IPAddress FROM Orion.Nodes"
    parameters = @{}
} | ConvertTo-Json

$response = Invoke-RestMethod -Uri "$baseUrl/Query" -Method POST -Body $body `
    -ContentType 'application/json' -Credential $cred

$response.results

# Create via REST
$createBody = @{
    NodeID      = 42
    City        = 'Dallas'
    Environment = 'Production'
} | ConvertTo-Json

Invoke-RestMethod -Uri "$baseUrl/Create/Orion.NodesCustomProperties" -Method POST `
    -Body $createBody -ContentType 'application/json' -Credential $cred

# Update via REST
$updateBody = @{ Caption = 'CoreSwitch-01' } | ConvertTo-Json
Invoke-RestMethod -Uri "$baseUrl/swis://localhost/Orion/Orion.Nodes/NodeID=1" -Method POST `
    -Body $updateBody -ContentType 'application/json' -Credential $cred

# Delete via REST
Invoke-RestMethod -Uri "$baseUrl/swis://localhost/Orion/Orion.Nodes/NodeID=99" -Method DELETE `
    -Credential $cred

# Invoke a verb via REST
$invokeBody = @("N:1", (Get-Date).ToUniversalTime(), (Get-Date).AddDays(1).ToUniversalTime(), "false") | ConvertTo-Json
Invoke-RestMethod -Uri "$baseUrl/Invoke/Orion.Nodes/Unmanage" -Method POST `
    -Body $invokeBody -ContentType 'application/json' -Credential $cred
```

---

## SWIS Connection Setup for CRUD Operations

Before performing any SWIS CRUD operations, a connection to the SolarWinds Information Service must be established. This section covers both the SwisPowerShell module approach and REST-based connectivity.

### SWIS Connection via SwisPowerShell Module

```powershell
# Import the module (install from PSGallery if not present)
if (-not (Get-Module -ListAvailable SwisPowerShell)) {
    Install-Module SwisPowerShell -Scope CurrentUser -Force
}
Import-Module SwisPowerShell

# Connect with Windows credentials (integrated authentication)
$swis = Connect-Swis -Hostname 'orionserver' -Trusted

# Connect with explicit credentials
$cred = Get-Credential
$swis = Connect-Swis -Hostname 'orionserver' -Credential $cred

# Connect and ignore certificate errors (lab/test environments only)
$swis = Connect-Swis -Hostname 'orionserver' -Credential $cred -IgnoreSslErrors
```

### SWIS Connection Verification

```powershell
# Verify the connection works with a simple query
$test = Get-SwisData $swis "SELECT TOP 1 NodeID, Caption FROM Orion.Nodes"
if ($test) {
    Write-Host "SWIS connection verified. Found node: $($test.Caption)"
} else {
    Write-Error "SWIS connection failed or no nodes found."
}
```

---

## SWIS CRUD Error Handling Patterns

Common error scenarios and how to handle them when performing SWIS CRUD operations.

### SWIS Error Handling in PowerShell

```powershell
# Wrap CRUD operations in try/catch for graceful error handling
try {
    $uri = New-SwisObject $swis -EntityType 'Orion.Pollers' -Properties @{
        PollerType    = 'N.Details.SNMP.Generic'
        NetObject     = 'N:999'
        NetObjectType = 'N'
        NetObjectID   = 999
    }
    Write-Host "Created poller: $uri"
}
catch {
    if ($_.Exception.Message -match 'does not exist') {
        Write-Warning "Target node does not exist. Verify NodeID before creating pollers."
    }
    elseif ($_.Exception.Message -match 'Violation of UNIQUE KEY') {
        Write-Warning "A poller of this type already exists for the specified node."
    }
    else {
        Write-Error "Unexpected error: $($_.Exception.Message)"
    }
}

# Check if an entity exists before attempting update or delete
$exists = Get-SwisData $swis "SELECT Uri FROM Orion.Nodes WHERE NodeID=@id" @{ id = 42 }
if ($exists) {
    Set-SwisObject $swis -Uri $exists -Properties @{ Caption = 'UpdatedCaption' }
} else {
    Write-Warning "Node 42 not found. Skipping update."
}
```

### SWIS Common Error Messages

| Error Message Pattern | Cause | Resolution |
|----------------------|-------|------------|
| `Unable to connect` | Wrong hostname, port, or firewall | Verify hostname and port 17778 is open |
| `401 Unauthorized` | Invalid credentials | Check username/password or use `-Trusted` |
| `does not exist` | Invalid URI or deleted entity | Query for the entity first to verify it exists |
| `Violation of UNIQUE KEY` | Duplicate entity creation | Check if the entity already exists before creating |
| `Property X is required` | Missing mandatory property | Include all required properties in the hashtable |
| `Invalid entity type` | Typo in EntityType string | Use `Get-SwisData $swis "SELECT EntityType FROM Metadata.Entity"` to list valid types |

---

## SWIS Bulk Operations Patterns

Efficient patterns for performing SWIS CRUD operations at scale.

### SWIS Bulk Create Pattern

```powershell
# Bulk-create pollers for a list of nodes
$nodeIds = Get-SwisData $swis "SELECT NodeID FROM Orion.Nodes WHERE ObjectSubType='SNMP'"
$pollerTypes = @(
    'N.Details.SNMP.Generic',
    'N.Uptime.SNMP.Generic',
    'N.Cpu.SNMP.HrProcessorLoad',
    'N.Memory.SNMP.NetSnmpReal'
)

foreach ($nodeId in $nodeIds) {
    foreach ($poller in $pollerTypes) {
        try {
            New-SwisObject $swis -EntityType 'Orion.Pollers' -Properties @{
                PollerType    = $poller
                NetObject     = "N:$nodeId"
                NetObjectType = 'N'
                NetObjectID   = $nodeId
            } | Out-Null
        }
        catch {
            Write-Warning "Failed to add poller $poller to node $nodeId : $($_.Exception.Message)"
        }
    }
}
```

### SWIS Bulk Update Pattern

```powershell
# Update custom properties for nodes matching a filter
$uris = Get-SwisData $swis "
    SELECT n.Uri
    FROM Orion.Nodes n
    WHERE n.Caption LIKE 'NYC-%'
"

$count = 0
foreach ($uri in $uris) {
    Set-SwisObject $swis -Uri "$uri/CustomProperties" -Properties @{
        Site     = 'New York'
        Region   = 'US-East'
        Managed  = 'Yes'
    }
    $count++
}
Write-Host "Updated custom properties on $count nodes."
```

### SWIS Bulk Delete with Logging

```powershell
# Delete stale nodes with an audit log
$staleNodes = Get-SwisData $swis "
    SELECT Uri, Caption, IPAddress, LastSystemUpTimePollUtc
    FROM Orion.Nodes
    WHERE LastSystemUpTimePollUtc < ADDDAY(-30, GETUTCDATE())
"

$logPath = "C:\Logs\deleted_nodes_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
$staleNodes | Export-Csv -Path $logPath -NoTypeInformation
Write-Host "Logged $($staleNodes.Count) nodes to $logPath"

$confirm = Read-Host "Delete these $($staleNodes.Count) stale nodes? (YES/NO)"
if ($confirm -eq 'YES') {
    $staleNodes.Uri | Remove-SwisObject $swis
    Write-Host "Deletion complete."
}
```
