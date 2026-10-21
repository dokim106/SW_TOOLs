# SWQL NCM (Network Configuration Manager) Entity Schema Reference

## Cirrus.Nodes Entity Schema (SWQL)

The primary NCM node entity in SWQL. Each row represents a network device managed by NCM for configuration backup, change detection, and compliance. The `Cirrus` namespace is the legacy SWIS namespace for NCM entities.

### Properties

| Property | Type | Notes |
|----------|------|-------|
| NodeID | Int32 | **Primary Key.** Matches the `NodeID` in `Orion.Nodes` for cross-module joins. |
| NodeCaption | String | Device display name. |
| AgentIP | String | IP address used for NCM connections to the device. |
| ConnectionProfile | String | Name of the connection profile (credentials and protocol settings). |
| LastConfigDownload | DateTime | Timestamp of the most recent configuration download from the device. |
| LastConfigUpload | DateTime | Timestamp of the most recent configuration push to the device. |
| ConfigDownloadStatus | Int32 | Status code of the last download attempt. |
| ConfigUploadStatus | Int32 | Status code of the last upload attempt. |
| Uri | String | SWIS URI for this entity instance. |
| DisplayName | String | Formatted display name. |

### SWQL Navigation Properties

| Navigation Property | Target Entity | Cardinality | Description |
|---------------------|---------------|-------------|-------------|
| NodeProperties | NCM.NodeProperties | Reference (single) | Extended node properties (EOL, EOS, firmware). |
| ConfigArchive | Cirrus.ConfigArchive | Collection | All archived configuration backups. |

### Example SWQL Queries

**Nodes where configuration download failed or is stale (over 7 days):**

```sql
SELECT
    cn.NodeCaption,
    cn.AgentIP,
    cn.ConnectionProfile,
    cn.LastConfigDownload,
    cn.ConfigDownloadStatus,
    DAYDIFF(cn.LastConfigDownload, GETUTCDATE()) AS DaysSinceDownload
FROM Cirrus.Nodes AS cn
WHERE cn.LastConfigDownload < ADDDAY(-7, GETUTCDATE())
   OR cn.ConfigDownloadStatus <> 1
ORDER BY cn.LastConfigDownload ASC
```

**All NCM-managed nodes with their Orion status (cross-module join):**

```sql
SELECT
    cn.NodeCaption,
    cn.AgentIP,
    n.StatusDescription AS OrionStatus,
    cn.LastConfigDownload,
    cn.ConnectionProfile
FROM Cirrus.Nodes AS cn
INNER JOIN Orion.Nodes AS n
    ON cn.NodeID = n.NodeID
ORDER BY cn.NodeCaption
```

---

## Cirrus.ConfigArchive Entity Schema (SWQL)

Stores archived configuration snapshots downloaded from managed devices. Each row is one configuration backup. Used for change tracking, diff comparisons, and compliance auditing.

### Properties

| Property | Type | Notes |
|----------|------|-------|
| ConfigArchiveID | Int32 | **Primary Key.** Unique identifier for this config snapshot. |
| NodeID | Int32 | Foreign key to `Cirrus.Nodes`. The device this config belongs to. |
| ConfigType | String | Configuration type: "Running", "Startup", or custom types. |
| DownloadTime | DateTime | Timestamp when this configuration was downloaded. |
| ConfigData | String | The full configuration text content. |
| BaselineID | Int32 | References a baseline config for comparison (0 if none). |
| DownloadStatus | Int32 | Status of the download operation. |
| IsCurrent | Boolean | True if this is the most recent archive for this node and config type. |
| ConfigSize | Int32 | Size of the configuration in bytes. |
| ChangedBy | String | User or process that triggered the download. |
| Comments | String | Optional comments attached to this snapshot. |

### Example SWQL Queries

**Most recent running config download per node:**

```sql
SELECT
    ca.NodeID,
    cn.NodeCaption,
    ca.DownloadTime,
    ca.ConfigSize,
    ca.ChangedBy
FROM Cirrus.ConfigArchive AS ca
INNER JOIN Cirrus.Nodes AS cn
    ON ca.NodeID = cn.NodeID
WHERE ca.ConfigType = 'Running'
  AND ca.IsCurrent = true
ORDER BY ca.DownloadTime DESC
```

**Nodes with configuration changes in the last 24 hours:**

```sql
SELECT
    cn.NodeCaption,
    ca.ConfigType,
    ca.DownloadTime,
    ca.ChangedBy,
    ca.Comments
FROM Cirrus.ConfigArchive AS ca
INNER JOIN Cirrus.Nodes AS cn
    ON ca.NodeID = cn.NodeID
WHERE ca.DownloadTime >= ADDDAY(-1, GETUTCDATE())
ORDER BY ca.DownloadTime DESC
```

**Count of archived configs per node (storage analysis):**

```sql
SELECT
    cn.NodeCaption,
    ca.ConfigType,
    COUNT(ca.ConfigArchiveID) AS ArchiveCount,
    MAX(ca.DownloadTime) AS LatestDownload,
    MIN(ca.DownloadTime) AS OldestDownload
FROM Cirrus.ConfigArchive AS ca
INNER JOIN Cirrus.Nodes AS cn
    ON ca.NodeID = cn.NodeID
GROUP BY cn.NodeCaption, ca.ConfigType
ORDER BY ArchiveCount DESC
```

---

## Cirrus.ConfigSnippets Entity Schema (SWQL)

Configuration snippets are reusable blocks of device configuration used in NCM scripting and remediation. They serve as building blocks for configuration deployment jobs.

### Properties

| Property | Type | Notes |
|----------|------|-------|
| SnippetID | Int32 | **Primary Key.** |
| Name | String | Snippet display name. |
| Content | String | The actual configuration text. |
| Category | String | Logical category for organization (e.g., "Security", "QoS", "Routing"). |
| Description | String | Human-readable description of the snippet purpose. |
| CreatedBy | String | User who created the snippet. |
| CreatedDate | DateTime | Creation timestamp. |
| LastModifiedBy | String | User who last modified the snippet. |
| LastModifiedDate | DateTime | Last modification timestamp. |

### Example SWQL Queries

**All snippets organized by category:**

```sql
SELECT
    cs.Category,
    cs.Name,
    cs.Description,
    cs.CreatedBy,
    cs.LastModifiedDate
FROM Cirrus.ConfigSnippets AS cs
ORDER BY cs.Category, cs.Name
```

---

## Cirrus.Policies Entity Schema (SWQL)

NCM configuration compliance policies define rules that device configurations must satisfy. Policies are evaluated against archived configs to detect non-compliance.

### Properties

| Property | Type | Notes |
|----------|------|-------|
| PolicyID | Int32 | **Primary Key.** |
| Name | String | Policy display name. |
| Description | String | Description of what the policy enforces. |
| Enabled | Boolean | Whether the policy is actively evaluated. |
| Severity | Int32 | Severity level of violations (informational, warning, critical). |
| Category | String | Policy category. |
| CreatedBy | String | User who defined the policy. |
| CreatedDate | DateTime | Creation timestamp. |
| LastEvaluationDate | DateTime | When the policy was last evaluated against configs. |
| ViolationCount | Int32 | Number of nodes currently violating this policy. |
| ComplianceCount | Int32 | Number of nodes currently compliant. |

### Example SWQL Queries

**Active policies with their current violation counts:**

```sql
SELECT
    p.Name AS PolicyName,
    p.Description,
    p.ViolationCount,
    p.ComplianceCount,
    p.LastEvaluationDate,
    CASE
        WHEN p.ComplianceCount + p.ViolationCount = 0 THEN 0
        ELSE ROUND(
            (p.ComplianceCount * 100.0) / (p.ComplianceCount + p.ViolationCount), 1
        )
    END AS CompliancePercent
FROM Cirrus.Policies AS p
WHERE p.Enabled = true
ORDER BY p.ViolationCount DESC
```

**Policies that have not been evaluated recently:**

```sql
SELECT
    p.Name AS PolicyName,
    p.LastEvaluationDate,
    DAYDIFF(p.LastEvaluationDate, GETUTCDATE()) AS DaysSinceEval
FROM Cirrus.Policies AS p
WHERE p.Enabled = true
  AND p.LastEvaluationDate < ADDDAY(-30, GETUTCDATE())
ORDER BY p.LastEvaluationDate ASC
```

---

## NCM.NodeProperties Entity Schema (SWQL)

Extended device properties tracked by NCM for lifecycle and firmware management. This entity augments the core `Cirrus.Nodes` data with end-of-life, end-of-support, and hardware/firmware details.

### Properties

| Property | Type | Notes |
|----------|------|-------|
| NodeID | Int32 | **Primary Key.** Foreign key to `Cirrus.Nodes` and `Orion.Nodes`. |
| IsEOL | Boolean | True if the device hardware is end-of-life. |
| EOLDate | DateTime | Hardware end-of-life date (null if not EOL). |
| IsEOS | Boolean | True if the device software/firmware is end-of-support. |
| EOSDate | DateTime | Software end-of-support date (null if not EOS). |
| FirmwareVersion | String | Currently running firmware version string. |
| HardwareModel | String | Device hardware model identifier. |
| SerialNumber | String | Device serial number. |
| BootTime | DateTime | Last device boot timestamp. |
| Uptime | Int64 | Device uptime in seconds. |

### Example SWQL Queries

**All devices past their end-of-life date:**

```sql
SELECT
    cn.NodeCaption,
    np.HardwareModel,
    np.FirmwareVersion,
    np.EOLDate,
    np.EOSDate,
    np.SerialNumber
FROM NCM.NodeProperties AS np
INNER JOIN Cirrus.Nodes AS cn
    ON np.NodeID = cn.NodeID
WHERE np.IsEOL = true
ORDER BY np.EOLDate ASC
```

**Devices approaching end-of-support within 90 days:**

```sql
SELECT
    cn.NodeCaption,
    np.HardwareModel,
    np.FirmwareVersion,
    np.EOSDate,
    DAYDIFF(GETUTCDATE(), np.EOSDate) AS DaysUntilEOS
FROM NCM.NodeProperties AS np
INNER JOIN Cirrus.Nodes AS cn
    ON np.NodeID = cn.NodeID
WHERE np.IsEOS = false
  AND np.EOSDate IS NOT NULL
  AND np.EOSDate <= ADDDAY(90, GETUTCDATE())
ORDER BY np.EOSDate ASC
```

**Firmware version inventory:**

```sql
SELECT
    np.HardwareModel,
    np.FirmwareVersion,
    COUNT(np.NodeID) AS DeviceCount
FROM NCM.NodeProperties AS np
GROUP BY np.HardwareModel, np.FirmwareVersion
ORDER BY np.HardwareModel, np.FirmwareVersion
```

---

## NCM.Eos Entity Schema (SWQL)

End-of-support definitions that NCM uses to flag devices running software or hardware that the vendor no longer supports. These records are populated from vendor lifecycle databases and used by the compliance and reporting features.

### Properties

| Property | Type | Notes |
|----------|------|-------|
| EosID | Int32 | **Primary Key.** |
| Vendor | String | Device vendor name (Cisco, Juniper, etc.). |
| ProductFamily | String | Product family or series. |
| Model | String | Specific model identifier. |
| SoftwareVersion | String | Affected software/firmware version. |
| EndOfSaleDate | DateTime | Date the product was no longer available for purchase. |
| EndOfSupportDate | DateTime | Date vendor support ends. |
| EndOfLifeDate | DateTime | Date the product reaches full end-of-life. |
| ReplacementModel | String | Vendor-recommended replacement model. |
| BulletinURL | String | Link to the vendor EOL/EOS bulletin. |

### Example SWQL Queries

**End-of-support records expiring this year:**

```sql
SELECT
    eos.Vendor,
    eos.ProductFamily,
    eos.Model,
    eos.SoftwareVersion,
    eos.EndOfSupportDate,
    eos.ReplacementModel
FROM NCM.Eos AS eos
WHERE YEAR(eos.EndOfSupportDate) = YEAR(GETUTCDATE())
ORDER BY eos.EndOfSupportDate ASC
```

---

## NCM.FirmwareDefinitions Entity Schema (SWQL)

Firmware definitions used by NCM to track known firmware versions, identify outdated software, and support firmware upgrade compliance.

### Properties

| Property | Type | Notes |
|----------|------|-------|
| FirmwareDefinitionID | Int32 | **Primary Key.** |
| Vendor | String | Device vendor. |
| Model | String | Device model or platform. |
| Version | String | Firmware version string. |
| ReleaseDate | DateTime | Vendor release date of this firmware. |
| IsRecommended | Boolean | True if this is the vendor-recommended version. |
| IsCurrent | Boolean | True if this is the latest available version. |
| TrainName | String | Software train or branch name (e.g., "17.6.x", "15.1SY"). |
| Notes | String | Release notes summary or description. |

### Example SWQL Queries

**Devices running non-recommended firmware:**

```sql
SELECT
    cn.NodeCaption,
    np.HardwareModel,
    np.FirmwareVersion AS RunningVersion,
    fd.Version AS RecommendedVersion,
    fd.ReleaseDate AS RecommendedReleaseDate
FROM NCM.NodeProperties AS np
INNER JOIN Cirrus.Nodes AS cn
    ON np.NodeID = cn.NodeID
INNER JOIN NCM.FirmwareDefinitions AS fd
    ON np.HardwareModel = fd.Model
WHERE fd.IsRecommended = true
  AND np.FirmwareVersion <> fd.Version
ORDER BY np.HardwareModel, cn.NodeCaption
```

**All known firmware versions for a specific model:**

```sql
SELECT
    fd.Version,
    fd.ReleaseDate,
    fd.TrainName,
    fd.IsRecommended,
    fd.IsCurrent,
    fd.Notes
FROM NCM.FirmwareDefinitions AS fd
WHERE fd.Model = 'WS-C3850-48P'
ORDER BY fd.ReleaseDate DESC
```

---

## Cirrus.NCM_NCMJobsView Entity Schema (SWQL)

A read-only SWQL view that exposes NCM job definitions and their execution history. Use this entity to monitor scheduled configuration backups, compliance scans, and scripting jobs.

### Properties

| Property | Type | Notes |
|----------|------|-------|
| NCMJobName | String | Display name of the NCM job. |
| NCMJobType | String | Job type: "Config Download", "Config Upload", "Script Execution", "Compliance Report", etc. |
| Enabled | Boolean | Whether the job is scheduled to run. |
| Status | Int32 | Status code of the last execution. |
| StatusDescription | String | Human-readable status of the last execution. |
| LastRunDate | DateTime | Timestamp of the most recent job execution. |
| NextRunDate | DateTime | Scheduled time for the next execution. |
| CreatedBy | String | User who created the job. |
| TargetNodeCount | Int32 | Number of nodes targeted by this job. |
| SuccessCount | Int32 | Nodes that completed successfully in the last run. |
| FailureCount | Int32 | Nodes that failed in the last run. |
| Duration | Int32 | Duration of the last run in seconds. |

### Example SWQL Queries

**All NCM jobs and their last execution status:**

```sql
SELECT
    j.NCMJobName,
    j.NCMJobType,
    j.Enabled,
    j.StatusDescription,
    j.LastRunDate,
    j.NextRunDate,
    j.TargetNodeCount,
    j.SuccessCount,
    j.FailureCount,
    j.Duration
FROM Cirrus.NCM_NCMJobsView AS j
ORDER BY j.LastRunDate DESC
```

**Jobs with failures in the most recent run:**

```sql
SELECT
    j.NCMJobName,
    j.NCMJobType,
    j.LastRunDate,
    j.TargetNodeCount,
    j.SuccessCount,
    j.FailureCount,
    ROUND(
        (j.FailureCount * 100.0) / j.TargetNodeCount, 1
    ) AS FailurePercent
FROM Cirrus.NCM_NCMJobsView AS j
WHERE j.FailureCount > 0
  AND j.Enabled = true
ORDER BY j.FailureCount DESC
```

**Disabled jobs that may need cleanup or re-enabling:**

```sql
SELECT
    j.NCMJobName,
    j.NCMJobType,
    j.LastRunDate,
    j.CreatedBy,
    DAYDIFF(j.LastRunDate, GETUTCDATE()) AS DaysSinceLastRun
FROM Cirrus.NCM_NCMJobsView AS j
WHERE j.Enabled = false
ORDER BY j.LastRunDate ASC
```
