# SWIS PowerShell Operations Cookbook

> Consolidated reference for PowerShell scripts that use the SolarWinds Information Service (SWIS) API.
> These scripts automate common SolarWinds platform operations: alert import/export, dashboard management, group replication, node migration, map uploads, port testing, SNMP credential updates, and more.

---

### Script: export ALERTS.ps1

**Purpose**: Export all enabled alert configurations from a SolarWinds Orion server to individual XML files for backup or migration.
**SWIS Operations Used**: `Connect-Swis`, `Get-SwisData`, `Invoke-SwisVerb`

Key code patterns:
```powershell
# Connect using SwisSnapin with credential prompts
$swis = Connect-Swis -Hostname $hostname -Username $username -Password $plainPassword

# Query all enabled alert IDs
$AlertList = Get-SwisData $swis "SELECT AlertId FROM Orion.AlertConfigurations WHERE Enabled = True"

# Export each alert to XML using the Orion.AlertConfigurations Export verb
$ExportedAlert = Invoke-SwisVerb $swis Orion.AlertConfigurations Export @($alertid)
Set-Content -Path $filename -Value $ExportedAlert.InnerText
```

**How to use**: Run the script, enter Orion server hostname, username, and password when prompted. Exported alert XML files are saved to an "Alerts Exports" subfolder next to the script, named with the alert title and ID.

---

### Script: Imports ALERTS.ps1

**Purpose**: Import alert configurations from XML files into a SolarWinds Orion server, restoring previously exported alerts.
**SWIS Operations Used**: `Connect-Swis`, `Invoke-SwisVerb`

Key code patterns:
```powershell
# Connect to SWIS
$swis = Connect-Swis -Hostname $hostname -Username $username -Password $plainPassword

# Read each XML file and import via the Orion.AlertConfigurations Import verb
$AlertXml = Get-Content $filePath -Raw
$importResult = Invoke-SwisVerb $swis Orion.AlertConfigurations Import @($AlertXml)
```

**How to use**: Place alert XML files in an "AlertExports" folder alongside the script. Run the script, enter credentials when prompted, and all XML files in that folder will be imported as alert configurations.

---

### Script: export all DASHBOARDS.ps1

**Purpose**: Export all Modern Dashboards from a SolarWinds Orion server to individual JSON files.
**SWIS Operations Used**: `Connect-Swis`, `Get-SwisData`, `Invoke-SwisVerb`

Key code patterns:
```powershell
$SwisConnection = Connect-Swis -Hostname $serverAddress -Credential $credential

# Query all top-level dashboard IDs
$Swql = "SELECT DashboardID FROM Orion.Dashboards.Instances WHERE ParentID IS NULL"
$DashboardIds = Get-SwisData -SwisConnection $SwisConnection -Query $Swql

# Export each dashboard using the Export verb
$dashboardData = Invoke-SwisVerb -SwisConnection $SwisConnection -EntityName "Orion.Dashboards.Instances" -Verb "Export" -Arguments $id
$dashboardObject = $dashboardData.'#text' | ConvertFrom-Json
$dashboardObject | ConvertTo-Json -Depth 25 | Out-File -FilePath $filePath
```

**How to use**: Run the script, enter server address and credentials. All dashboards are exported as JSON files to an "ExportDashboard" folder in the current directory.

---

### Script: import DASHBOARDS.ps1

**Purpose**: Import Modern Dashboard JSON files into a SolarWinds Orion server.
**SWIS Operations Used**: `Connect-Swis`, `Invoke-SwisVerb`

Key code patterns:
```powershell
$SwisConnection = Connect-Swis -Hostname $serverAddress -Credential $credential

# Read each JSON file and import via the Import verb
$dashboardJsonContent = Get-Content -Path $file.FullName -Raw
Invoke-SwisVerb -SwisConnection $SwisConnection -EntityName "Orion.Dashboards.Instances" -Verb "Import" -Arguments ($dashboardJsonContent)
```

**How to use**: Place dashboard JSON files in an "ExportDashboard" folder in the current directory. Run the script, enter credentials. Each JSON file is imported as a new Modern Dashboard.

---

### Script: import export DASHBOARDS.ps1

**Purpose**: Full-featured Modern Dashboard import/export toolkit with duplicate detection, system dashboard handling, force-overwrite support, and file name sanitization. Authored by Kevin M. Sparenberg.
**SWIS Operations Used**: `Connect-Swis`, `Get-SwisData`, `Invoke-SwisVerb`

Key code patterns:
```powershell
# Export: query dashboards, export via verb, save as JSON
$Swql = "SELECT DashboardID FROM Orion.Dashboards.Instances WHERE ParentID IS NULL AND IsSystem = 'FALSE'"
$DashboardId = Get-SwisData -SwisConnection $SwisConnection -Query $Swql
$DashboardText = Invoke-SwisVerb -SwisConnection $SwisConnection -EntityName Orion.Dashboards.Instances -Verb Export -Arguments $d
$DashboardObject | ConvertTo-Json -Depth $JsonDepth -Compress:$Compress | Out-File -FilePath $ExportFilePath

# Import: check for duplicates via UniqueKey, then import
$Swql = "SELECT DisplayName, UniqueKey FROM Orion.Dashboards.Instances WHERE ParentID IS NULL"
$Dashboards = Get-SwisData -SwisConnection $SwisConnection -Query $Swql
Invoke-SwisVerb -SwisConnection $SwisConnection -EntityName "Orion.Dashboards.Instances" -Verb "Import" -Arguments ($TemplateObject | ConvertTo-Json -Depth $JsonDepth -Compress)
```

**How to use**: Import the script to get two functions: `Export-ModernDashboard` and `Import-ModernDashboard`. Both accept a `-SwisConnection` parameter and support `-Force`, `-IncludeSystem`, `-IncludeId`, and `-Compress` switches. Also includes the `Remove-InvalidFileNameChars` utility function for safe file naming. Requires PowerShell v7+ and SwisPowerShell v3.0+.

---

### Script: SWIS to SolarWinds samples.ps1

**Purpose**: Interactive sample script demonstrating basic dashboard export and import operations using the SWIS API, with a file dialog for selecting import files.
**SWIS Operations Used**: `Connect-Swis`, `Get-SwisData`, `Invoke-SwisVerb`

Key code patterns:
```powershell
# Download OrionSDK helper functions from GitHub
Invoke-WebRequest "https://raw.githubusercontent.com/solarwinds/OrionSDK/master/Samples/PowerShell/functions/func_ModernDashboards.ps1" -OutFile "func_ModernDashboards.ps1"

# Connect to SWIS
Connect-Swis -Credential $OrionCredentials -Hostname $serverHostname

# Export a dashboard by ID
$exportedDashboard = Get-SwisData $SwisConnection -Query "SELECT Uri, Definition FROM Orion.Dashboards.Instances WHERE Id=@id" -Parameters @{id=$dashboardId}

# Import a dashboard from JSON file
Invoke-SwisVerb $SwisConnection Orion.Dashboards.Instances CreateDashboard $dashboardJson
```

**How to use**: Run the script, choose "export" or "import" at the prompt. For export, provide a dashboard ID. For import, select a JSON file via the Windows file dialog. Downloads OrionSDK helper functions automatically.

---

### Script: export sam application TEMPLATES.ps1

**Purpose**: Export all SAM (Server & Application Monitor) application templates to XML files for backup.
**SWIS Operations Used**: `Connect-Swis`, `Get-SwisData`, `Invoke-SwisVerb`

Key code patterns:
```powershell
$swis = Connect-Swis -Credential $credential -Hostname $hostname

# Query all application templates with instance counts
$templates = Get-SwisData $swis @"
SELECT at.name AS template, at.ApplicationTemplateID, a.name, COUNT(*) AS instances
FROM Orion.APM.ApplicationTemplate at
LEFT JOIN Orion.APM.Application a ON a.ApplicationTemplateID = at.ApplicationTemplateID
GROUP BY at.name, a.name, at.ApplicationTemplateID
"@

# Export each template to XML
$templateXML = Invoke-SwisVerb $swis "Orion.APM.ApplicationTemplate" "ExportTemplate" $template.ApplicationTemplateID
$templateXML | Export-Clixml ($TempPath + "$namecleanup.xml")
```

**How to use**: Run the script, enter hostname and credentials. Templates are exported as XML files to a "TemplateExports" subfolder. Includes automatic logging with 31-day log rotation.

---

### Script: import GROUPS from CSV's database_table.ps1

**Purpose**: Bulk-create SolarWinds groups from a CSV file using the SWIS Container API.
**SWIS Operations Used**: `Connect-Swis`, `Invoke-SwisVerb`

Key code patterns:
```powershell
$swis = Connect-Swis -Hostname $hostname -Credential $cred

# Import groups from CSV and create each via SWIS verb
$groupsToImport = Import-Csv -Path $csvFilePath

$emptyMembersXml = ([xml]"<ArrayOfMemberDefinitionInfo xmlns='http://schemas.solarwinds.com/2008/Orion' />").DocumentElement

$groupId = (Invoke-SwisVerb $swis "Orion.Container" "CreateContainer" @(
    $group.Name,
    $group.Owner,
    60,       # Refresh frequency
    0,        # Status rollup mode (0 = Mixed shows warning)
    $group.Description,
    $group.PollingEnabled,
    $emptyMembersXml
)).InnerText
```

**How to use**: Prepare a CSV file with columns: Name, Owner, Description, PollingEnabled. Run the script, enter the server hostname and CSV file path when prompted. Each row creates a new empty group.

---

### Script: replicate GROUPS.ps1

**Purpose**: Replicate all groups (including members, sub-groups, nodes, and interfaces) from a source SolarWinds server to a destination server.
**SWIS Operations Used**: `Connect-Swis`, `Get-SwisData`, `Invoke-SwisVerb`

Key code patterns:
```powershell
# Connect to both source and destination
$swissource = Connect-Swis -Hostname $SourceServer -Credential $sourcecred
$swisdest = Connect-Swis -Hostname $DestinationServer -Credential $destcred

# Query all groups and their member definitions from source
$Groups = Get-SwisData -SwisConnection $swissource -Query "SELECT ContainerID, Name, Description, Owner, Frequency, StatusCalculator, RollupType, IsDeleted, PollingEnabled FROM Orion.Container WHERE ContainerID IN (SELECT ContainerID FROM Orion.ContainerMemberDefinition WHERE Entity = 'Orion.Groups')"

# Resolve node members by IP address on destination
$DestinationNodeQuery = 'Select NodeID, Caption from Orion.Nodes where IPAddress = ''' + $IP + ''''
$NodeInDestination = Get-SwisData -SwisConnection $swisdest -Query $DestinationNodeQuery

# Create group with members on destination
$groupId = (Invoke-SwisVerb $swisdest "Orion.Container" "CreateContainer" @(
    $($Group).Name, "Core", $($Group).Frequency, $($Group).StatusCalculator,
    $($Group).Description, "true", "",
    ([xml]@("<ArrayOfMemberDefinitionInfo xmlns='http://schemas.solarwinds.com/2008/Orion'>",
        [string]($members | % { "<MemberDefinitionInfo><Name>$($_.Name)</Name><Definition>$($_.Definition)</Definition></MemberDefinitionInfo>" }),
        "</ArrayOfMemberDefinitionInfo>"
    )).DocumentElement
)).InnerText

# Add member definitions to the group
Invoke-SwisVerb $swisdest "Orion.Container" "AddDefinitions" @($groupId, $membersXml)
```

**How to use**: Edit the `$SourceServer` and `$DestinationServer` variables at the top of the script. Run the script, enter credentials for both servers. Groups, their node members (matched by IP address), interface members (matched by InterfaceIndex), and sub-groups are replicated to the destination.

---

### Script: Upload-MAPFilesToSolarWinds.ps1

**Purpose**: Upload OrionMap files and associated images (background/thumbnail JPGs) to the SolarWinds database, bypassing Network Atlas and the web UI.
**SWIS Operations Used**: `Connect-Swis`, `Get-SwisData`, `New-SwisObject`, `Remove-SwisObject`

Key code patterns:
```powershell
$SwisConnection = Connect-Swis -Hostname $SolarWindsHostName -Credential $SwisCredential

# Query existing maps from the database
$SwqlQuery = @"
SELECT FileId, FileName, FileType, Uri
FROM Orion.MapStudioFiles
WHERE FileType IN ($OrionMapFileType,$JpgFileType,$ThumbJpgFileType) AND IsDeleted = False AND FileName IN ({0})
"@
$ExistingMapInformation = Get-SwisData -SwisConnection $SwisConnection -Query $SwqlQuery

# Replace existing map: delete old, create new with same FileId
Remove-SwisObject -SwisConnection $SwisConnection -Uri $ExistingMap.Uri
New-SwisObject -SwisConnection $SwisConnection -EntityType 'Orion.MapStudioFiles' -Properties @{
    FileId=$ExistingMap.FileId; FileName=$FileName; TimeStamp=$(Get-Date).DateTime;
    FileData=$bytes; Owner=$SwisCredential.UserName; IsDeleted=$false; FileType=$FileType
}
```

**How to use**: Place OrionMap files and their associated JPG images in a "MapFilesToUpload" subfolder. Images must share the same base name as their map file (e.g., `MyMap.OrionMap`, `MyMap.jpg`, `MyMap.thumb.jpg`). Run the script, enter SWIS credentials. The script uploads images first, links them to map files by updating BackgroundImageName/ThumbnailImageName references, then uploads the maps. Existing maps with the same filename are replaced while preserving their FileId.

---

### Script: SolarWinds required TCP PORTS.ps1

**Purpose**: Test connectivity to all SolarWinds-required TCP and UDP ports against one or more target hosts, producing a categorized open/closed/unreachable report.
**SWIS Operations Used**: None (network connectivity testing utility)

Key code patterns:
```powershell
# Define all SolarWinds ports with descriptions
$portDescriptions = [ordered]@{
    22     = "SSH - Secure Shell (agent install on Linux/Unix)"
    443    = "HTTPS - secure web/API traffic"
    161    = "SNMP (UDP) - device polling"
    162    = "SNMP Traps (UDP) - trap ingestion"
    1433   = "SQL Server default (DB)"
    5671   = "RabbitMQ TLS / HA encrypted messaging"
    17774  = "SolarWinds SWIS API (HTTPS)"
    17777  = "SolarWinds Orion Module Engine (OME)"
    17778  = "SolarWinds Agent - command/control"
    # ... additional ports
}

# Test TCP ports using Test-NetConnection, UDP via custom Test-Udp function
$ok = Test-NetConnection -ComputerName $ip -Port ([int]$port) -InformationLevel Quiet
```

**How to use**: Run the script, enter comma-separated IP addresses or hostnames to test. The script tests all SolarWinds-required ports (TCP and UDP) and displays results grouped as Open, Closed/No-Response, and Unreachable.

---

### Script: update SNMPv2 to snmpv3 for nodes.ps1

**Purpose**: Bulk-update nodes from SNMPv2 to SNMPv3 credentials using the SWIS API.
**SWIS Operations Used**: `Connect-Swis`, `Get-SwisData`, `Set-SwisObject`

Key code patterns:
```powershell
$swis = Connect-Swis -Hostname "<SolarWinds server>" -Credential (Get-Credential)

# Query SNMP v2 nodes from a specific vendor
$query = "SELECT TOP 1000 n.caption AS [Node], n.ip_address AS [ip_address], n.uri AS [uri]
FROM Orion.Nodes n
WHERE n.vendor='net-snmp' AND n.Status = 1 AND n.SNMPVersion='2'"
$nodes = Get-SwisData -SwisConnection $swis -Query $query

# Update each node's SNMP properties to v3
$properties = @{
    SNMPVersion      = '3'
    SNMPV3Username   = 'sw-mon'
    SNMPV3PrivMethod = 'AES128'
    SNMPV3PrivKey    = 'xxxxx'
    SNMPV3AuthMethod = 'SHA1'
    SNMPV3AuthKey    = 'xxxxx'
    SNMPV3PrivKeyIsPwd = $TRUE
    SNMPV3AuthKeyIsPwd = $TRUE
}
Set-SwisObject $swis $($node.uri) $properties
```

**How to use**: Edit the connection details, SWQL filter (vendor, status), and SNMPv3 credential properties in the script. Run the script to update all matching nodes from SNMPv2 to SNMPv3. The script processes nodes with a 400ms delay between updates to avoid overwhelming the API.

---

### Script: migration_ScriptSolarwindsPlatforms-v1.7 1.ps1

**Purpose**: Full platform migration script that copies nodes (SNMP v1/v2, SNMPv3, WMI, Agent), interfaces, volumes, pollers, custom properties, groups, and NCM associations from a source SolarWinds instance to a destination instance. Authored by Author Name (OurTeam).
**SWIS Operations Used**: `Connect-Swis`, `Get-SwisData`, `Get-SwisObject`, `New-SwisObject`, `Set-SwisObject`, `Invoke-SwisVerb`

Key code patterns:
```powershell
# Connect to source and destination
$source = Connect-Swis -Credential $SourceCred -Hostname $SourceHost
$target = Connect-Swis -Credential $DestinationCred -Hostname $destinationHost

# Copy custom properties from source to destination
$AllCustomProperties = Get-SwisData $source "SELECT Table, Field, DataType, MaxLength, StorageMethod, Description, TargetEntity, Mandatory, Default, DisplayName FROM Orion.CustomProperty"
Invoke-SwisVerb -Swis $target Orion.NodesCustomProperties CreateCustomProperty $CPProps

# Copy node with all properties
$sourceNodeProps = Get-SwisData $source "SELECT AgentPort, Allow64BitCounters, Caption, Community, ... FROM Orion.Nodes WHERE NodeID = @nodeid" @{nodeid=$sourceNode.NodeId}
$newUri = New-SwisObject $target -EntityType "Orion.Nodes" -Properties $targetNodeProps
Set-SwisObject $target ($newUri+"/CustomProperties") @{ MigratedByAPI="true" }

# Copy pollers for each node
$pollerTypes = Get-SwisData $source "SELECT PollerType FROM Orion.Pollers WHERE NetObject=@netobject" @{netobject='N:' + $sourceNode.NodeID}
New-SwisObject $target -EntityType "Orion.Pollers" -Properties $poller

# Copy interfaces and their custom properties
$newIfUri = New-SwisObject $target -EntityType "Orion.NPM.Interfaces" -Properties $targetIfProps
Set-SwisObject $target ($newIfUri+"/CustomProperties") $targetIFCPs

# Copy volumes
$newVolUri = New-SwisObject $target -EntityType "Orion.Volumes" -Properties $targetVolProps

# Add node to NCM if it was in NCM on source
Invoke-SwisVerb $target Cirrus.Nodes AddNodeToNCM $newNode.NodeID

# Create groups with members using container verbs
Invoke-SwisVerb $target "Orion.Container" "CreateContainer" @(...)
Invoke-SwisVerb $target "Orion.Container" "CreateContainerwithParent" @(...)
```

**How to use**: Edit the `$SourceHost`, `$SourceUser`, `$SourcePass`, `$destinationHost`, `$DestinationUser`, and `$DestinationPass` variables. The script migrates in phases: (1) custom properties, (2) SNMP v1/v2 nodes with interfaces/volumes/pollers, (3) SNMPv3 nodes, (4) WMI nodes, (5) Agent nodes, (6) groups with members. Each migrated node gets a `MigratedByAPI=true` custom property. Includes helper functions for IP-to-GUID conversion, engine load balancing, and group member definition rewriting. Requires the SwisPowerShell module.

---



