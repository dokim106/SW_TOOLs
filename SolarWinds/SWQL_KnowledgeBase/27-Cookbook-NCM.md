# SWQL NCM (Network Configuration Manager) Query Cookbook

## SWQL NCM Queries

### Query: Approval Process Queue

/* Retrieves all pending configuration change approval requests, including the submitter, script details, approval status, and scheduled execution time. | Entities: `Cirrus.ApproveQueue` */

```sql
SELECT
  UserName,
  RequestType,
  Script,
  ConfigType,
  Reboot,
  DateTime,
  Comments,
  RequestStatus,
  ApprovedBy,
  RunAt,
  NCMJobID,
  StatusChangeTime,
  ExecutionType,
  DisplayName
FROM
  Cirrus.ApproveQueue
```


---

### Query: Comparison Criteria (Regex Rules)

/* Lists all configuration comparison regular expression rules, showing their title, pattern, enabled state, and .NET regex flag. Useful for auditing what lines are excluded or highlighted during config diffs. | Entities: `Cirrus.CompareRegExs` */

```sql
SELECT
  Title,
  RegEx,
  Enabled,
  DotNetRegEx
FROM
  Cirrus.CompareRegExs
ORDER BY
  Enabled
```


---

### Query: Comparison Criteria Count by Rule Type

/* Counts the number of enabled comparison regex rules grouped by whether they are single-line or block (multi-line) patterns. | Entities: `Cirrus.CompareRegExs` */

```sql
SELECT
  CASE
    WHEN IsBlock = true THEN 'Block (multi-line)'
    ELSE 'Single-line'
  END AS RuleType,
  CASE
    WHEN IsBlock = true THEN 'Patterns spanning multiple lines'
    ELSE 'Patterns matching single lines only'
  END AS TypeDescription,
  COUNT(*) AS RuleCount
FROM
  Cirrus.CompareRegExs
WHERE
  Enabled = true
GROUP BY
  CASE
    WHEN IsBlock = true THEN 'Block (multi-line)'
    ELSE 'Single-line'
  END,
  CASE
    WHEN IsBlock = true THEN 'Patterns spanning multiple lines'
    ELSE 'Patterns matching single lines only'
  END
ORDER BY
  RuleCount DESC
```


---

### Query: Config Change Templates Total Count

/* Returns the total number of configuration change templates (snippets) defined in NCM. | Entities: `Cirrus.ConfigSnippets` */

```sql
SELECT
  'Config Change Templates' AS [Name],
  COUNT(ID) AS [Total]
FROM
  Cirrus.ConfigSnippets
```


---

### Query: Config Change Templates Monthly and Total Counts

/* Provides a breakdown of configuration change templates by the month they were created, along with a grand total row, to show template creation trends over time. | Entities: `Cirrus.ConfigSnippets` */

```sql
SELECT
  'Total Templates'    AS MonthDescription,
  COUNT(ID)            AS TemplatesCount,
  9999                 AS SortYear,
  0                    AS SortMonth
FROM
  Cirrus.ConfigSnippets

UNION ALL
(
  SELECT
    CONCAT(
      CASE MONTH(Created)
        WHEN 1  THEN 'January'
        WHEN 2  THEN 'February'
        WHEN 3  THEN 'March'
        WHEN 4  THEN 'April'
        WHEN 5  THEN 'May'
        WHEN 6  THEN 'June'
        WHEN 7  THEN 'July'
        WHEN 8  THEN 'August'
        WHEN 9  THEN 'September'
        WHEN 10 THEN 'October'
        WHEN 11 THEN 'November'
        WHEN 12 THEN 'December'
      END,
      ' ',
      ToString(YEAR(Created))
    )                   AS MonthDescription,
    COUNT(ID)           AS TemplatesCount,
    YEAR(Created)       AS SortYear,
    MONTH(Created)      AS SortMonth
  FROM
    Cirrus.ConfigSnippets
  GROUP BY
    YEAR(Created),
    MONTH(Created)
)
ORDER BY
  SortYear DESC,
  SortMonth DESC
```


---

### Query: Config Types

/* Lists all NCM configuration types (e.g., Running, Startup) and whether each is a custom-defined type. | Entities: `NCM.ConfigTypes` */

```sql
SELECT
  Name,
  IsCustom AS [Is Custom]
FROM
  NCM.ConfigTypes
ORDER BY
  Id
```


---

### Query: Connection Profiles (SWQL Approach)

/* Summarizes NCM node connectivity by counting total nodes, login successes, connection refusals, and HTTPS usage from `Cirrus.NodeProperties`. | Entities: `Cirrus.NodeProperties` */

```sql
SELECT
  COUNT(NodeID) AS TotalNodeCount,
  SUM(CASE WHEN LoginStatus = 'Login OK' THEN 1 ELSE 0 END) AS LoginOKCount,
  SUM(CASE WHEN LoginStatus LIKE '%Connection Refused%' THEN 1 ELSE 0 END) AS ConnectionRefusedCount,
  SUM(CASE WHEN UseHTTPS = 'True' THEN 1 ELSE 0 END) AS HTTPSCountTrue,
  SUM(CASE WHEN UseHTTPS = 'False' THEN 1 ELSE 0 END) AS HTTPSCountFalse
FROM
  Cirrus.NodeProperties
```


---

### Query: Devices Backup Failed

/* Identifies devices with failed configuration backups, grouped by vendor and configuration type, showing the count of failures. | Entities: `NCM.ConfigBackupStatus` */

```sql
SELECT
  Vendor,
  ConfigType,
  COUNT(NodeName) AS [Failed Count]
FROM
  NCM.ConfigBackupStatus
WHERE
  BackupStatus != '1'
GROUP BY
  Vendor,
  ConfigType
ORDER BY
  [Failed Count] DESC
```


---

### Query: Device Templates

/* Lists NCM device templates with their associated vendor and the total number of nodes assigned to each template. | Entities: `Cli.DeviceTemplates`, `Cli.DeviceTemplatesNodes`, `Orion.Nodes` */

```sql
SELECT
  dt.TemplateName,
  n.Vendor,
  COUNT(dt.ID) AS [Total]
FROM
  Cli.DeviceTemplates AS dt
  JOIN Cli.DeviceTemplatesNodes AS dtn ON dtn.TemplateID = dt.ID
  LEFT JOIN Orion.Nodes AS n ON dtn.NodeID = n.NodeID
GROUP BY
  dt.TemplateName,
  n.Vendor
```


---

### Query: EOS and EOL Status

/* Evaluates End of Support (EOS) and End of Sales (EOL) expiration status for managed nodes, grouped by machine type and serial number. | Entities: `NCM.NodeProperties` */

```sql
SELECT
  ncm.nodes.MachineType,
  CASE
    WHEN EndOfSupport < GETDATE() THEN 'Yes'
    WHEN EndOfSupport IS NULL THEN '-'
    ELSE 'No'
  END AS [EOS Expired],
  CASE
    WHEN EndOfSales < GETDATE() THEN 'Yes'
    WHEN EndOfSales IS NULL THEN '-'
    ELSE 'No'
  END AS [EOL Expired]
FROM
  NCM.NodeProperties AS NCM
WHERE
  EosType IN ('1', '2', '3')
GROUP BY
  CASE
    WHEN EndOfSupport < GETDATE() THEN 'Yes'
    WHEN EndOfSupport IS NULL THEN '-'
    ELSE 'No'
  END,
  CASE
    WHEN EndOfSales < GETDATE() THEN 'Yes'
    WHEN EndOfSales IS NULL THEN '-'
    ELSE 'No'
  END,
  CASE
    WHEN NCM.nodes.SwitchStack.SwitchStackMember.SerialNumber IS NULL
      THEN NCM.nodes.HardwareHealthInfos.ServiceTag
    ELSE NCM.nodes.SwitchStack.SwitchStackMember.SerialNumber
  END,
  ncm.nodes.MachineType
```


---

### Query: NCM EOL/EOF Node Summary

/* Provides a high-level count of total nodes and how many are missing End of Sales or End of Support data. | Entities: `Orion.Nodes` (via `NodeProperties` navigation) */

```sql
SELECT
  COUNT(*) AS [Total Nodes],
  SUM(CASE WHEN n.NodeProperties.EndOfSales IS NULL THEN 1 END) AS [EndOfSale Missing],
  SUM(CASE WHEN n.NodeProperties.EndOfSupport IS NULL THEN 1 END) AS [EndofSupport Missing]
FROM
  Orion.Nodes n
```


---

### Query: Firmware Repository

/* Summarizes firmware definitions by canned (predefined) vs. custom status, and lists all custom firmware definition names. | Entities: `NCM.FirmwareDefinitions` */

```sql
SELECT
  'Device Template' AS [Device Template],
  SUM(CASE WHEN canned = 1 THEN 1 END) AS [Canned],
  SUM(CASE WHEN canned = 0 THEN 1 END) AS [Not_Canned]
FROM
  NCM.FirmwareDefinitions

UNION ALL
(
  SELECT
    Name AS [c],
    NULL AS [v],
    NULL AS [v1]
  FROM
    NCM.FirmwareDefinitions
  WHERE
    canned = 0
)
```


---

### Query: Firmware Templates

/* Shows firmware template details including associated vendor and node count per template, paralleling the device template query structure. | Entities: `NCM.FirmwareDefinitions` */

```sql
SELECT
  'Device Template' AS [Device Template],
  SUM(CASE WHEN canned = 1 THEN 1 END) AS [Canned],
  SUM(CASE WHEN canned = 0 THEN 1 END) AS [Not_Canned]
FROM
  NCM.FirmwareDefinitions

UNION ALL
(
  SELECT
    Name AS [c],
    NULL AS [v],
    NULL AS [v1]
  FROM
    NCM.FirmwareDefinitions
  WHERE
    canned = 0
)
```


---

### Query: Firmware Vulnerabilities

/* Counts firmware vulnerabilities by severity level (High, Medium, Low) based on CVSS-like scoring thresholds. | Entities: `NCM.VulnerabilitiesAnnouncements`, `NCM.VulnerabilitiesAnnouncementsNodes` */

```sql
SELECT
  CASE
    WHEN score >= 7 THEN 'High'
    WHEN score >= 4 AND score < 7 THEN 'Medium'
    ELSE 'Low'
  END AS [Vulnerability Level],
  COUNT(*) AS [Total Vulnerabilities]
FROM
  NCM.VulnerabilitiesAnnouncements y
  JOIN NCM.VulnerabilitiesAnnouncementsNodes v ON v.EntryId = y.EntryId
GROUP BY
  CASE
    WHEN score >= 7 THEN 'High'
    WHEN score >= 4 AND score < 7 THEN 'Medium'
    ELSE 'Low'
  END
ORDER BY
  CASE
    WHEN score >= 7 THEN 'High'
    WHEN score >= 4 AND score < 7 THEN 'Medium'
    ELSE 'Low'
  END
```


---

### Query: Global or User Level Logins

/* Placeholder for querying global vs. user-level login credential configuration. | Entities: TBD (uses PowerShell verb `Cirrus.Settings` / `GetSetting`) */

```sql
-- TODO
```


---

### Query: NCM Jobs

/* Lists all NCM jobs with their type translated to a human-readable description, enabled status, and last run status. | Entities: `Cirrus.NCM_NCMJobsView` */

```sql
SELECT
  NCMJobName,
  CASE
    WHEN NCMJobType = 0  THEN 'Command Script'
    WHEN NCMJobType = 1  THEN 'Execute Program'
    WHEN NCMJobType = 2  THEN 'Upload Configurations'
    WHEN NCMJobType = 3  THEN 'Report'
    WHEN NCMJobType = 4  THEN 'Reboot Devices'
    WHEN NCMJobType = 5  THEN 'Export Configurations'
    WHEN NCMJobType = 6  THEN 'NCM Database Maintenance'
    WHEN NCMJobType = 7  THEN 'Inventory'
    WHEN NCMJobType = 8  THEN 'Config Change Reports'
    WHEN NCMJobType = 9  THEN 'Compliance Policy Reports'
    WHEN NCMJobType = 10 THEN 'Purge Configurations'
    WHEN NCMJobType = 11 THEN 'Download Configurations'
    WHEN NCMJobType = 12 THEN 'Real-Time Notifications'
    WHEN NCMJobType = 13 THEN 'Orion Import'
    WHEN NCMJobType = 14 THEN 'Baseline Entire Network'
    WHEN NCMJobType = 15 THEN 'Config Change Template'
    WHEN NCMJobType = 16 THEN 'Error'
    ELSE 'Unknown'
  END AS [Description],
  Enabled,
  CASE
    WHEN Status = 0 THEN 'Queued'
    WHEN Status = 1 THEN 'Transferring'
    WHEN Status = 2 THEN 'Complete'
    WHEN Status = 3 THEN 'Error'
    ELSE 'Unknown'
  END AS [Last Run Status]
FROM
  Cirrus.NCM_NCMJobsView
ORDER BY
  Enabled DESC
```


---

### Query: Policy Reporting

/* Summarizes NCM compliance policy results by report name, showing counts of informational, warning, and critical violations. | Entities: `Cirrus.PolicyCacheResults` */

```sql
SELECT
  a.report,
  a.info AS [Informational],
  a.warn AS [Warning],
  a.crit AS [Critical]
FROM
(
  SELECT TOP 100
    ReportName AS [report],
    SUM(ISNULL(CASE WHEN ErrorLevel = 0 AND IsViolation = 1 THEN 1 END, 0)) AS [info],
    SUM(ISNULL(CASE WHEN ErrorLevel = 1 AND IsViolation = 1 THEN 1 END, 0)) AS [warn],
    SUM(ISNULL(CASE WHEN ErrorLevel = 2 AND IsViolation = 1 THEN 1 END, 0)) AS [crit]
  FROM
    Cirrus.PolicyCacheResults
  GROUP BY
    ReportName
  ORDER BY
    4 DESC, 3 DESC, 2 DESC
) a
```


---

### Query: Real-Time Change Notification Settings

/* Placeholder for querying RTN (Real-Time Change Notification) settings. Uses PowerShell verb approach. | Entities: `Cirrus.Settings` (via `Invoke-SwisVerb`) */

```sql
-- Uses PowerShell Invoke-SwisVerb with Cirrus.Settings / GetSetting
-- Filter: SearchTerm "*RTN*"
-- Retrieves settings such as RTNEnabled, RTNUseUserDevice, RTNIncludeNotification,
-- RTNLimitDownloadOperations, RTNUserName, RTNConfigType, RTNLastConfig,
-- RTNBaselineConfig, DisableRTNEmail, RTNInHTMLFormat, RTNWithDiffs,
-- RTNEmailFromName, RTNEmailReplyAddress, RTNEmailSubject, RTNEmailTo, etc.
```


---

### Query: Security Settings (NCM Settings)

/* Placeholder for querying NCM security-related settings. Uses PowerShell verb approach. | Entities: `Cirrus.Settings` (via `Invoke-SwisVerb`) */

```sql
-- Uses PowerShell Invoke-SwisVerb with Cirrus.Settings / GetSetting
-- Filter: SearchTerm "*Server*" (or any wildcard pattern)
-- Retrieves settings such as HideCommunityStrings, HideUsernames,
-- ConnectivityLevel, SMTPServer, SMTPPort, SMTPUseSSL, TFTPServerAddress,
-- SCPServerAddress, FirmwareStorageLocation, and many others.
```


---

### Query: SMTP and TFTP (Integrated or 3rd Party)

/* Placeholder for querying SMTP and TFTP server configuration. Uses PowerShell verb approach. | Entities: `Cirrus.Settings` (via `Invoke-SwisVerb`) */

```sql
-- Uses PowerShell Invoke-SwisVerb with Cirrus.Settings / GetSetting
-- Filter: SearchTerm "*Server*"
-- Retrieves: SMTPServer, SMTPPort, SMTPSSLPort, SMTPUseAuth, SMTPUseSSL,
-- TFTPServerAddress, TFTPRootDir, UseThirdPartyTftpServer,
-- SCPServerAddress, SCPRootDir, UseThirdPartySCPServer, etc.
```


---

### Query: Custom Snippets Count

/* Returns the total number of custom snippets stored in the NCM snippet archive. | Entities: `Cirrus.SnippetArchive` */

```sql
SELECT
  'Custom Snippets' AS [Title],
  COUNT(ConfigID) AS [Total]
FROM
  Cirrus.SnippetArchive
```


---

### Query: User Privileges

/* Counts the number of user accounts grouped by their NCM permission level (role). | Entities: `Orion.UserSettings` */

```sql
SELECT
  SettingValue AS [NCM Permissions],
  COUNT(AccountID) AS [Total Accounts]
FROM
  Orion.UserSettings
WHERE
  SettingName = 'NCM.NCMAccountRole'
  AND SettingValue IS NOT NULL
  AND SettingValue != ''
GROUP BY
  SettingValue
```


---

## NCM PowerShell Verb Operations

### Verb: Get Connection Profiles via Invoke-SwisVerb

**Purpose**: Retrieves all NCM connection profiles using the SWIS verb API, which exposes details not available through standard SWQL queries (usernames, protocols, port numbers, enable levels).

**Verb**: `Cirrus.Nodes` / `GetAllConnectionProfiles`

```powershell
function Get-NCMConnectionProfiles {
    param (
        [string]$Name  # Allow filtered name
    )

    $results = Invoke-SwisVerb $swis 'Cirrus.Nodes' 'GetAllConnectionProfiles' @()

    Add-Type -AssemblyName System.Web

    $filteredProfile = if ($Name) {
        $results.ConnectionProfile | Where-Object { $_.Name -like "*$Name*" }
    }
    else {
        $results.ConnectionProfile
    }

    $resultsTable = @()
    $filteredProfile | ForEach-Object {
        $resultsTable += [pscustomobject][ordered]@{
            ProfileName            = $_.Name.InnerXml
            UserName               = $_.ConnectionData.UserName.InnerXml
            Password               = $_.ConnectionData.Password.InnerXml
            EnableLevel            = [System.Web.HttpUtility]::HtmlDecode($_.ConnectionData.EnableLevel.InnerXml)
            EnablePassword         = $_.ConnectionData.EnablePassword.InnerXml
            ExecuteScriptProtocol  = $_.ExecuteScriptProtocol.InnerXml
            RequestConfigProtocol  = $_.RequestConfigProtocol.InnerXml
            TransferConfigProtocol = $_.TransferConfigProtocol.InnerXml
            TelnetPort             = $_.ConnectionData.TelnetPort
            SSHPort                = $_.ConnectionData.SSHPort
            UseForAutoDetect       = $_.UseForAutoDetect
        }
    }

    return $resultsTable | Format-List
}
```


---

### Verb: Get NCM Settings via Invoke-SwisVerb

**Purpose**: Retrieves individual NCM setting values by name using the `Cirrus.Settings` / `GetSetting` verb. Supports wildcard filtering to query multiple settings at once.

**Verb**: `Cirrus.Settings` / `GetSetting`

```powershell
function Get-NCMSetting {
    param (
        [string]$SearchTerm = '*',
        [string]$defaultValue = $null,
        [int]$engineId = 2
    )

    $ncmSettings = @(
        'HideCommunityStrings', 'HideUsernames', 'ConnectivityLevel',
        'SMTPServer', 'SMTPPort', 'SMTPUseSSL', 'TFTPServerAddress',
        'TFTPRootDir', 'UseThirdPartyTftpServer', 'SCPServerAddress',
        'GlobalUsername', 'GlobalExecProtocol', 'RTNEnabled',
        'ConfigArchiveDirectory', 'FirmwareStorageLocation',
        'ConfigChangeApprovalEnabled', 'ApprovalMode'
        # ... and 100+ additional setting keys
    )

    $filteredSettings = $ncmSettings -like $SearchTerm
    $resultsTable = @()

    foreach ($setting in $filteredSettings) {
        $result = Invoke-SwisVerb $swis 'Cirrus.Settings' 'GetSetting' @($setting, $defaultValue, $engineId)
        $settingValue = if ($result.nil -ne $true) { $result.InnerXml } else { 'null' }

        $resultsTable += [pscustomobject]@{
            'Setting' = $setting
            'Value'   = $settingValue
        }
    }

    return $resultsTable
}

# Example usage:
Get-NCMSetting -SearchTerm "*RTN*"      # All Real-Time Notification settings
Get-NCMSetting -SearchTerm "*Server*"   # All server-related settings
Get-NCMSetting -SearchTerm "*SMTP*"     # All SMTP settings
```


---

### Verb: Get NCM Archive Location (GUI Tool)

**Purpose**: A GUI-based PowerShell tool that connects to SolarWinds, retrieves the NCM configuration archive directory path, verifies it exists, and lists archived configuration files. Supports optional MFA authentication.

**Verb**: `Cirrus.Settings` / `GetSetting` (for `ConfigArchiveDirectory`)

```powershell
# Retrieves the NCM config archive directory and lists its contents.
# Presents a WinForms GUI for server credentials (with optional MFA).
# Uses Invoke-SwisVerb to call Cirrus.Settings / GetSetting for 'ConfigArchiveDirectory'.

# Key steps:
# 1. Prompts for Hostname, Username, Password, optional MFA Code via GUI form
# 2. Connects to SWIS using Connect-Swis (with or without MFA)
# 3. Calls Get-NCMSetting -SearchTerm 'ConfigArchiveDirectory'
# 4. Validates the returned path exists on the filesystem
# 5. Lists *.xml files in the archive directory via Out-GridView
```

**Key points**: The archive directory stores mirrored configuration files when `EnableConfigMirror` is enabled. Files are stored as XML. The tool requires the OrionSDK PowerShell module (`SwisPowerShell` or `SwisSnapIn`). MFA support uses the `-MfaCode` parameter of `Connect-Swis`.



