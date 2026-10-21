# SWQL SCM Entity Schema Reference

> Detailed schema reference for SolarWinds Server Configuration Monitor (SCM) SWQL entities.
> Covers configuration baselines, server profiles, configuration changes, node-profile associations, poll entries, and profile elements.
> The SWQL namespace uses `Orion.SCM.*` for SCM entities.

---

## Orion.SCM.Baseline (SWQL)

Represents a configuration baseline definition. Baselines capture a known-good server configuration state that can be compared against to detect drift.

### SWQL Properties

| Property | Type | Description |
|----------|------|-------------|
| BaselineID | Int32 | Primary key. Unique baseline identifier |
| Name | String | Baseline display name |
| Description | String | Baseline description |
| CreatedDate | DateTime | When the baseline was created |
| ModifiedDate | DateTime | When the baseline was last modified |
| CreatedBy | String | Administrator who created the baseline |
| Status | Int32 | Current baseline status code |
| StatusDescription | String | Human-readable status |
| NodeCount | Int32 | Number of nodes assigned to this baseline |
| DriftCount | Int32 | Number of nodes currently in drift from baseline |
| ProfileID | Int32 | FK to Orion.SCM.Profiles. Associated profile |

### SWQL Navigation Properties

- **Profile** navigates to Orion.SCM.Profiles -- the profile defining what to monitor
- **Nodes** navigates to Orion.SCM.NodesProfiles (collection) -- node-baseline assignments

### Example SWQL Queries

**All baselines with drift status:**

```sql
SELECT
    b.Name AS [Baseline],
    b.Description,
    b.NodeCount AS [Nodes],
    b.DriftCount AS [Drifted],
    CASE
        WHEN b.NodeCount > 0
        THEN (b.DriftCount * 100) / b.NodeCount
        ELSE 0
    END AS [Drift %],
    b.StatusDescription AS [Status],
    ToLocal(b.ModifiedDate) AS [Last Modified]
FROM Orion.SCM.Baseline AS b
ORDER BY b.DriftCount DESC
```

**Baselines with active drift requiring attention:**

```sql
SELECT
    b.Name AS [Baseline],
    b.DriftCount AS [Drifted Nodes],
    b.CreatedBy AS [Owner],
    ToLocal(b.CreatedDate) AS [Created]
FROM Orion.SCM.Baseline AS b
WHERE b.DriftCount > 0
ORDER BY b.DriftCount DESC
```

---

## Orion.SCM.Profiles (SWQL)

Represents an SCM monitoring profile. Profiles define the set of configuration elements (files, registry keys, services, IIS settings, etc.) to track on target servers.

### SWQL Properties

| Property | Type | Description |
|----------|------|-------------|
| ProfileID | Int32 | Primary key. Unique profile identifier |
| Name | String | Profile display name |
| Description | String | Profile description |
| TargetType | String | Target platform (Windows, Linux) |
| Enabled | Boolean | Whether the profile is active |
| ElementCount | Int32 | Number of configuration elements in the profile |
| NodeCount | Int32 | Number of nodes assigned to this profile |
| CreatedDate | DateTime | When the profile was created |
| ModifiedDate | DateTime | When the profile was last modified |
| CreatedBy | String | Administrator who created the profile |
| Category | String | Profile category label |

### SWQL Navigation Properties

- **Elements** navigates to Orion.SCM.ProfileElements (collection) -- elements tracked by this profile
- **NodesProfiles** navigates to Orion.SCM.NodesProfiles (collection) -- node assignments

### Example SWQL Queries

**All profiles with element and node counts:**

```sql
SELECT
    p.Name AS [Profile],
    p.TargetType AS [Platform],
    p.ElementCount AS [Elements],
    p.NodeCount AS [Nodes],
    p.Enabled,
    p.Category,
    ToLocal(p.ModifiedDate) AS [Last Modified]
FROM Orion.SCM.Profiles AS p
ORDER BY p.NodeCount DESC
```

**Enabled profiles with no nodes assigned (unused):**

```sql
SELECT
    p.Name AS [Profile],
    p.TargetType AS [Platform],
    p.ElementCount AS [Elements],
    p.CreatedBy AS [Owner]
FROM Orion.SCM.Profiles AS p
WHERE p.Enabled = true
  AND p.NodeCount = 0
ORDER BY p.Name
```

---

## Orion.SCM.ServerConfiguration (SWQL)

Represents the current configuration state captured from a monitored server. Contains the actual collected data for comparison against baselines.

### SWQL Properties

| Property | Type | Description |
|----------|------|-------------|
| ConfigurationID | Int32 | Primary key. Unique configuration record identifier |
| NodeID | Int32 | FK to Orion.Nodes. The monitored server |
| ProfileID | Int32 | FK to Orion.SCM.Profiles |
| CaptureDate | DateTime | When this configuration snapshot was captured |
| Status | Int32 | Configuration status (Compliant, Drifted, Error) |
| StatusDescription | String | Human-readable status |
| ChangeCount | Int32 | Number of configuration changes since baseline |
| ElementsMonitored | Int32 | Number of elements being tracked |
| CompliancePercent | Double | Percentage of elements matching baseline |

### SWQL Navigation Properties

- **Node** navigates to Orion.Nodes -- the monitored server
- **Profile** navigates to Orion.SCM.Profiles -- the monitoring profile
- **Changes** navigates to Orion.SCM.ServerConfigurationChange (collection) -- detected changes

### Example SWQL Queries

**Server compliance summary:**

```sql
SELECT
    sc.Node.Caption AS [Server],
    sc.Profile.Name AS [Profile],
    sc.StatusDescription AS [Status],
    sc.CompliancePercent AS [Compliance %],
    sc.ChangeCount AS [Changes],
    ToLocal(sc.CaptureDate) AS [Last Capture]
FROM Orion.SCM.ServerConfiguration AS sc
ORDER BY sc.CompliancePercent ASC
```

---

## Orion.SCM.ServerConfigurationChange (SWQL)

Represents a configuration change detected on a monitored server. Stores the before and after values for auditing and compliance reporting.

### SWQL Properties

| Property | Type | Description |
|----------|------|-------------|
| ChangeID | Int64 | Primary key. Unique change identifier |
| ConfigurationID | Int32 | FK to Orion.SCM.ServerConfiguration |
| NodeID | Int32 | FK to Orion.Nodes |
| ChangeDate | DateTime | When the change was detected |
| ElementName | String | Name of the changed element (file, registry key, service, etc.) |
| ElementType | String | Type of element (File, Registry, Service, IISSetting, etc.) |
| ChangeType | String | Type of change (Modified, Added, Removed) |
| PreviousValue | String | Value before the change |
| CurrentValue | String | Value after the change |
| Severity | Int32 | Change severity level |
| UserName | String | User who made the change (when available) |
| ProcessName | String | Process that triggered the change (when available) |

### SWQL Navigation Properties

- **Node** navigates to Orion.Nodes -- the server where the change occurred
- **ServerConfiguration** navigates to Orion.SCM.ServerConfiguration -- parent configuration record

### Example SWQL Queries

**Recent configuration changes across all servers:**

```sql
SELECT TOP 50
    c.Node.Caption AS [Server],
    c.ElementName AS [Element],
    c.ElementType AS [Type],
    c.ChangeType AS [Change],
    c.UserName AS [Changed By],
    ToLocal(c.ChangeDate) AS [Date]
FROM Orion.SCM.ServerConfigurationChange AS c
ORDER BY c.ChangeDate DESC
```

**Changes by element type over the last 7 days:**

```sql
SELECT
    c.ElementType AS [Element Type],
    c.ChangeType AS [Change Type],
    COUNT(*) AS [Count]
FROM Orion.SCM.ServerConfigurationChange AS c
WHERE DAYDIFF(c.ChangeDate, GETUTCDATE()) < 7
GROUP BY c.ElementType, c.ChangeType
ORDER BY [Count] DESC
```

**File changes on a specific server:**

```sql
SELECT
    c.ElementName AS [File],
    c.ChangeType AS [Change],
    c.UserName AS [User],
    c.ProcessName AS [Process],
    ToLocal(c.ChangeDate) AS [Date]
FROM Orion.SCM.ServerConfigurationChange AS c
WHERE c.NodeID = @NodeId
  AND c.ElementType = 'File'
ORDER BY c.ChangeDate DESC
```

---

## Orion.SCM.NodesProfiles (SWQL)

Represents the assignment relationship between nodes and SCM profiles. Links a server to one or more monitoring profiles.

### SWQL Properties

| Property | Type | Description |
|----------|------|-------------|
| NodeProfileID | Int32 | Primary key |
| NodeID | Int32 | FK to Orion.Nodes |
| ProfileID | Int32 | FK to Orion.SCM.Profiles |
| BaselineID | Int32 | FK to Orion.SCM.Baseline (if baselined) |
| AssignedDate | DateTime | When the profile was assigned to the node |
| Status | Int32 | Assignment status |
| LastPollDate | DateTime | Last time this node-profile was polled |

### SWQL Navigation Properties

- **Node** navigates to Orion.Nodes
- **Profile** navigates to Orion.SCM.Profiles
- **Baseline** navigates to Orion.SCM.Baseline

### Example SWQL Queries

**Node-to-profile assignments:**

```sql
SELECT
    np.Node.Caption AS [Server],
    np.Profile.Name AS [Profile],
    np.Baseline.Name AS [Baseline],
    ToLocal(np.LastPollDate) AS [Last Polled]
FROM Orion.SCM.NodesProfiles AS np
ORDER BY np.Node.Caption, np.Profile.Name
```

---

## Orion.SCM.PollEntries (SWQL)

Represents individual poll results for SCM configuration elements. Tracks the outcome of each polling cycle.

### SWQL Properties

| Property | Type | Description |
|----------|------|-------------|
| PollEntryID | Int64 | Primary key |
| NodeID | Int32 | FK to Orion.Nodes |
| ProfileID | Int32 | FK to Orion.SCM.Profiles |
| PollDate | DateTime | When the poll occurred |
| Status | Int32 | Poll result status |
| StatusDescription | String | Human-readable status |
| Duration | Int32 | Poll duration in milliseconds |
| ElementsPolled | Int32 | Number of elements checked |
| ChangesDetected | Int32 | Number of changes found in this poll |

### Example SWQL Queries

**Recent poll results with change counts:**

```sql
SELECT TOP 20
    pe.Node.Caption AS [Server],
    pe.Profile.Name AS [Profile],
    pe.StatusDescription AS [Status],
    pe.ElementsPolled AS [Elements],
    pe.ChangesDetected AS [Changes],
    pe.Duration AS [Duration ms],
    ToLocal(pe.PollDate) AS [Poll Time]
FROM Orion.SCM.PollEntries AS pe
ORDER BY pe.PollDate DESC
```

---

## Orion.SCM.ProfileElements (SWQL)

Represents an individual configuration element (file, registry key, service, etc.) defined within an SCM profile.

### SWQL Properties

| Property | Type | Description |
|----------|------|-------------|
| ElementID | Int32 | Primary key. Unique element identifier |
| ProfileID | Int32 | FK to Orion.SCM.Profiles |
| Name | String | Element name or path |
| ElementType | String | Type (File, RegistryKey, RegistryValue, Service, IISSetting, WindowsFeature) |
| Path | String | Full path to the monitored element |
| MonitorContent | Boolean | Whether content changes are tracked |
| MonitorPermissions | Boolean | Whether permission changes are tracked |
| MonitorAttributes | Boolean | Whether attribute changes are tracked |
| Enabled | Boolean | Whether this element is active |

### SWQL Navigation Properties

- **Profile** navigates to Orion.SCM.Profiles -- parent profile

### Example SWQL Queries

**Elements in a specific profile:**

```sql
SELECT
    e.Name AS [Element],
    e.ElementType AS [Type],
    e.Path,
    e.MonitorContent AS [Content],
    e.MonitorPermissions AS [Permissions],
    e.Enabled
FROM Orion.SCM.ProfileElements AS e
WHERE e.ProfileID = @ProfileId
ORDER BY e.ElementType, e.Name
```

**All monitored elements by type across profiles:**

```sql
SELECT
    e.ElementType AS [Type],
    e.Profile.Name AS [Profile],
    COUNT(*) AS [Element Count]
FROM Orion.SCM.ProfileElements AS e
WHERE e.Enabled = true
GROUP BY e.ElementType, e.Profile.Name
ORDER BY e.ElementType, [Element Count] DESC
```

---

## SWQL SCM Schema Discovery

Use these metadata queries to explore available SCM entities and properties at runtime:

```sql
-- List all SCM entities
SELECT FullName, EntityName
FROM Metadata.Entity
WHERE FullName LIKE 'Orion.SCM.%'
ORDER BY EntityName

-- List properties of a specific SCM entity
SELECT Name, Type, IsNavigable, IsKey
FROM Metadata.Property
WHERE EntityName = 'Orion.SCM.ServerConfigurationChange'
```
