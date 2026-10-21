# SWQL WPM Entity Schema Reference

> Detailed schema reference for SolarWinds Web Performance Monitor (WPM) SWQL entities.
> Covers synthetic web transactions, player agents, recordings, transaction steps, and configuration settings.
> The SWQL namespace uses `Orion.SEUM.*` for WPM entities.

---

## Orion.SEUM.Transactions (SWQL)

Represents a synthetic web transaction monitored by WPM. Each transaction defines a recorded browser workflow that is replayed at regular intervals to measure availability and response time.

### SWQL Properties

| Property | Type | Description |
|----------|------|-------------|
| TransactionID | Int32 | Primary key. Unique transaction identifier |
| Name | String | Transaction display name |
| Description | String | Transaction description |
| Status | Int32 | Current transaction status code |
| StatusDescription | String | Human-readable status (Up, Down, Warning, Unknown) |
| AvgResponseTime | Double | Average response time in milliseconds |
| Availability | Double | Availability percentage (0-100) |
| Frequency | Int32 | Playback frequency in minutes |
| Enabled | Boolean | Whether the transaction is active |
| LastRun | DateTime | Timestamp of the most recent playback |
| StepCount | Int32 | Number of steps in the transaction |
| URL | String | Starting URL for the transaction |
| WarningThreshold | Double | Response time warning threshold in ms |
| CriticalThreshold | Double | Response time critical threshold in ms |
| DownCount | Int32 | Number of consecutive failures |
| TotalPlaybacks | Int64 | Total number of playback attempts |
| SuccessfulPlaybacks | Int64 | Total successful playbacks |
| FailedPlaybacks | Int64 | Total failed playbacks |

### SWQL Navigation Properties

- **Steps** navigates to Orion.SEUM.TransactionSteps (collection) -- steps within this transaction
- **Agents** navigates to Orion.SEUM.Agents (collection) -- players assigned to run this transaction
- **Recordings** navigates to Orion.SEUM.Recordings (collection) -- recorded browser sessions

### Example SWQL Queries

**All transactions with current response times and availability:**

```sql
SELECT
    t.Name AS [Transaction],
    t.StatusDescription AS [Status],
    t.AvgResponseTime AS [Avg ms],
    t.Availability AS [Avail %],
    t.Frequency AS [Interval min],
    ToLocal(t.LastRun) AS [Last Run]
FROM Orion.SEUM.Transactions AS t
WHERE t.Enabled = true
ORDER BY t.Availability ASC
```

**Transactions exceeding warning thresholds:**

```sql
SELECT
    t.Name AS [Transaction],
    t.AvgResponseTime AS [Avg ms],
    t.WarningThreshold AS [Warn ms],
    t.CriticalThreshold AS [Crit ms],
    t.Availability AS [Avail %],
    t.DownCount AS [Consecutive Failures]
FROM Orion.SEUM.Transactions AS t
WHERE t.Enabled = true
  AND t.AvgResponseTime > t.WarningThreshold
ORDER BY t.AvgResponseTime DESC
```

**Transaction success rates:**

```sql
SELECT
    t.Name AS [Transaction],
    t.TotalPlaybacks AS [Total Runs],
    t.SuccessfulPlaybacks AS [Success],
    t.FailedPlaybacks AS [Failed],
    CASE
        WHEN t.TotalPlaybacks > 0
        THEN (t.SuccessfulPlaybacks * 100) / t.TotalPlaybacks
        ELSE 0
    END AS [Success Rate %]
FROM Orion.SEUM.Transactions AS t
WHERE t.Enabled = true
ORDER BY [Success Rate %] ASC
```

---

## Orion.SEUM.Agents (SWQL)

Represents a WPM player agent (also called a player) that executes synthetic transactions. Players can be local (on the Orion server) or remote (distributed across locations).

### SWQL Properties

| Property | Type | Description |
|----------|------|-------------|
| AgentID | Int32 | Primary key. Unique agent identifier |
| Name | String | Agent display name |
| Hostname | String | Hostname or FQDN of the player machine |
| IPAddress | String | IP address of the player |
| Status | Int32 | Current agent status code |
| StatusDescription | String | Human-readable status (Active, Inactive, Error) |
| AgentType | String | Agent type (Internal, External) |
| Location | String | Geographic location label |
| Version | String | WPM player software version |
| LastContact | DateTime | Last successful communication with the agent |
| TransactionCount | Int32 | Number of transactions assigned to this agent |
| OS | String | Operating system of the player machine |
| IsLocal | Boolean | Whether this is the built-in local player |

### SWQL Navigation Properties

- **Transactions** navigates to Orion.SEUM.Transactions (collection) -- transactions assigned to this player

### Example SWQL Queries

**Player agent health overview:**

```sql
SELECT
    a.Name AS [Player],
    a.Hostname,
    a.IPAddress,
    a.StatusDescription AS [Status],
    a.Location,
    a.Version,
    a.TransactionCount AS [Transactions],
    ToLocal(a.LastContact) AS [Last Contact]
FROM Orion.SEUM.Agents AS a
ORDER BY a.Status DESC, a.Name
```

**Players that have not checked in recently:**

```sql
SELECT
    a.Name AS [Player],
    a.Hostname,
    a.StatusDescription AS [Status],
    ToLocal(a.LastContact) AS [Last Contact],
    HOURDIFF(a.LastContact, GETUTCDATE()) AS [Hours Silent]
FROM Orion.SEUM.Agents AS a
WHERE HOURDIFF(a.LastContact, GETUTCDATE()) > 1
ORDER BY [Hours Silent] DESC
```

---

## Orion.SEUM.Recordings (SWQL)

Represents a recorded browser session used as the basis for a synthetic transaction. Recordings capture the exact browser interactions to replay.

### SWQL Properties

| Property | Type | Description |
|----------|------|-------------|
| RecordingID | Int32 | Primary key. Unique recording identifier |
| TransactionID | Int32 | FK to Orion.SEUM.Transactions |
| Name | String | Recording name |
| CreatedDate | DateTime | When the recording was created |
| ModifiedDate | DateTime | When the recording was last modified |
| StepCount | Int32 | Number of steps in the recording |
| Browser | String | Browser used for recording |
| IsActive | Boolean | Whether this recording is the active version |

### SWQL Navigation Properties

- **Transaction** navigates to Orion.SEUM.Transactions -- parent transaction

### Example SWQL Queries

**Active recordings with creation dates:**

```sql
SELECT
    r.Name AS [Recording],
    r.Transaction.Name AS [Transaction],
    r.StepCount AS [Steps],
    r.Browser,
    ToLocal(r.CreatedDate) AS [Created],
    ToLocal(r.ModifiedDate) AS [Modified]
FROM Orion.SEUM.Recordings AS r
WHERE r.IsActive = true
ORDER BY r.ModifiedDate DESC
```

---

## Orion.SEUM.TransactionSteps (SWQL)

Represents an individual step within a synthetic transaction. Each step corresponds to a specific page load or action in the browser workflow.

### SWQL Properties

| Property | Type | Description |
|----------|------|-------------|
| StepID | Int32 | Primary key. Unique step identifier |
| TransactionID | Int32 | FK to Orion.SEUM.Transactions |
| StepName | String | Step display name |
| StepOrder | Int32 | Execution order within the transaction |
| URL | String | URL loaded in this step |
| Status | Int32 | Current step status code |
| AvgResponseTime | Double | Average response time for this step in ms |
| AvgDNSTime | Double | Average DNS resolution time in ms |
| AvgConnectTime | Double | Average TCP connect time in ms |
| AvgTTFB | Double | Average time to first byte in ms |
| AvgContentLoad | Double | Average content load time in ms |
| WarningThreshold | Double | Step-level warning threshold in ms |
| CriticalThreshold | Double | Step-level critical threshold in ms |

### SWQL Navigation Properties

- **Transaction** navigates to Orion.SEUM.Transactions -- parent transaction

### Example SWQL Queries

**Slowest transaction steps across all transactions:**

```sql
SELECT TOP 20
    ts.Transaction.Name AS [Transaction],
    ts.StepName AS [Step],
    ts.StepOrder AS [Order],
    ts.URL,
    ts.AvgResponseTime AS [Avg ms],
    ts.AvgDNSTime AS [DNS ms],
    ts.AvgTTFB AS [TTFB ms]
FROM Orion.SEUM.TransactionSteps AS ts
WHERE ts.Transaction.Enabled = true
ORDER BY ts.AvgResponseTime DESC
```

**Step-by-step breakdown for a specific transaction:**

```sql
SELECT
    ts.StepOrder AS [Step #],
    ts.StepName AS [Step],
    ts.URL,
    ts.AvgResponseTime AS [Total ms],
    ts.AvgDNSTime AS [DNS ms],
    ts.AvgConnectTime AS [Connect ms],
    ts.AvgTTFB AS [TTFB ms],
    ts.AvgContentLoad AS [Content ms]
FROM Orion.SEUM.TransactionSteps AS ts
WHERE ts.TransactionID = @TransactionId
ORDER BY ts.StepOrder
```

---

## Orion.SEUM.Settings (SWQL)

Stores WPM module configuration settings as key-value pairs.

### SWQL Properties

| Property | Type | Description |
|----------|------|-------------|
| SettingID | String | Primary key. Setting name/identifier |
| Value | String | Current setting value |
| Description | String | What this setting controls |
| DefaultValue | String | Factory default value |

### Example SWQL Queries

**View all WPM configuration settings:**

```sql
SELECT
    SettingID AS [Setting],
    Value,
    DefaultValue AS [Default],
    Description
FROM Orion.SEUM.Settings
ORDER BY SettingID
```

---

## SWQL WPM Schema Discovery

Use these metadata queries to explore available WPM entities and properties at runtime:

```sql
-- List all SEUM entities
SELECT FullName, EntityName
FROM Metadata.Entity
WHERE FullName LIKE 'Orion.SEUM.%'
ORDER BY EntityName

-- List properties of a specific WPM entity
SELECT Name, Type, IsNavigable, IsKey
FROM Metadata.Property
WHERE EntityName = 'Orion.SEUM.Transactions'
```
