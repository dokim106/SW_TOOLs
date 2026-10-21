# SWQL LA Entity Schema Reference

> Detailed schema reference for SolarWinds Log Analyzer (LA) SWQL entities.
> Covers log message sources, processing rules, log entries, tags, and severity levels.
> The SWQL namespace uses `Orion.OLM.*` for Log Analyzer entities.

---

## Orion.OLM.MessageSources (SWQL)

Represents a log source configured in Log Analyzer. Each message source defines a device or application sending syslog, SNMP trap, or Windows event log data to the collector.

### SWQL Properties

| Property | Type | Description |
|----------|------|-------------|
| MessageSourceID | Int32 | Primary key. Unique log source identifier |
| NodeID | Int32 | FK to Orion.Nodes. The node generating log messages |
| Name | String | Log source display name |
| DisplayName | String | Full display name |
| LogSourceType | String | Source type (Syslog, SNMPTrap, WindowsEventLog, File) |
| Status | Int32 | Current source status code |
| StatusDescription | String | Human-readable status |
| Enabled | Boolean | Whether the source is actively collecting |
| IPAddress | String | IP address of the log source |
| Port | Int32 | Listening port for this source |
| Protocol | String | Transport protocol (UDP, TCP, TLS) |
| MessageRate | Double | Current messages per second |
| TotalMessages | Int64 | Total messages received from this source |
| LastMessageTime | DateTime | Timestamp of the most recent message |
| FilterEnabled | Boolean | Whether pre-processing filters are active |

### SWQL Navigation Properties

- **Node** navigates to Orion.Nodes -- the node generating logs
- **Rules** navigates to Orion.OLM.ProcessingRule (collection) -- rules applied to this source

### Example SWQL Queries

**All active log sources with message rates:**

```sql
SELECT
    ms.Name AS [Source],
    ms.Node.Caption AS [Node],
    ms.LogSourceType AS [Type],
    ms.MessageRate AS [Msgs/sec],
    ms.TotalMessages AS [Total],
    ToLocal(ms.LastMessageTime) AS [Last Message]
FROM Orion.OLM.MessageSources AS ms
WHERE ms.Enabled = true
ORDER BY ms.MessageRate DESC
```

**Log sources that have stopped sending data:**

```sql
SELECT
    ms.Name AS [Source],
    ms.Node.Caption AS [Node],
    ms.LogSourceType AS [Type],
    ToLocal(ms.LastMessageTime) AS [Last Message],
    HOURDIFF(ms.LastMessageTime, GETUTCDATE()) AS [Hours Silent]
FROM Orion.OLM.MessageSources AS ms
WHERE ms.Enabled = true
  AND HOURDIFF(ms.LastMessageTime, GETUTCDATE()) > 4
ORDER BY [Hours Silent] DESC
```

---

## Orion.OLM.ProcessingRule (SWQL)

Represents a log processing rule that matches, filters, tags, or triggers actions based on log message content.

### SWQL Properties

| Property | Type | Description |
|----------|------|-------------|
| RuleID | Int32 | Primary key. Unique rule identifier |
| Name | String | Rule display name |
| Description | String | Rule description |
| Enabled | Boolean | Whether the rule is active |
| Priority | Int32 | Rule evaluation order (lower = higher priority) |
| RuleType | String | Rule type (Filter, Alert, Tag, Transform) |
| MatchExpression | String | Regular expression or keyword pattern to match |
| ActionType | String | Action to take on match (Tag, Alert, Discard, Forward) |
| MatchCount | Int64 | Total number of times this rule has matched |
| LastMatch | DateTime | Timestamp of the most recent match |
| StopProcessing | Boolean | Whether to stop evaluating further rules after match |

### Example SWQL Queries

**All enabled rules with match statistics:**

```sql
SELECT
    r.Name AS [Rule],
    r.RuleType AS [Type],
    r.Priority,
    r.ActionType AS [Action],
    r.MatchCount AS [Matches],
    ToLocal(r.LastMatch) AS [Last Match],
    r.StopProcessing AS [Stop After]
FROM Orion.OLM.ProcessingRule AS r
WHERE r.Enabled = true
ORDER BY r.Priority ASC
```

**Rules that have never matched (candidates for cleanup):**

```sql
SELECT
    r.Name AS [Rule],
    r.RuleType AS [Type],
    r.MatchExpression AS [Pattern],
    r.Priority
FROM Orion.OLM.ProcessingRule AS r
WHERE r.Enabled = true
  AND (r.MatchCount = 0 OR r.MatchCount IS NULL)
ORDER BY r.Priority
```

---

## Orion.OLM.LogEntry (SWQL)

Represents an individual log event stored by Log Analyzer. Contains the parsed message, severity, source, and any applied tags.

### SWQL Properties

| Property | Type | Description |
|----------|------|-------------|
| LogEntryID | Int64 | Primary key. Unique log entry identifier |
| MessageSourceID | Int32 | FK to Orion.OLM.MessageSources |
| NodeID | Int32 | FK to Orion.Nodes |
| DateTime | DateTime | Timestamp of the log event |
| Message | String | Full log message text |
| MessageType | String | Parsed message type/facility |
| Severity | Int32 | Syslog severity level (0-7) |
| SeverityName | String | Human-readable severity (Emergency, Alert, Critical, Error, Warning, Notice, Info, Debug) |
| Hostname | String | Reporting hostname from the message |
| IPAddress | String | Source IP address |
| Facility | String | Syslog facility |
| Application | String | Application name from the message |
| Tag | String | Applied tags (comma-separated) |
| ProcessID | String | Process ID from the message |

### SWQL Navigation Properties

- **MessageSource** navigates to Orion.OLM.MessageSources -- source that produced this entry
- **Node** navigates to Orion.Nodes -- the originating node

### Example SWQL Queries

**Recent critical and emergency log entries:**

```sql
SELECT TOP 50
    le.SeverityName AS [Severity],
    le.Node.Caption AS [Node],
    le.Application,
    le.Message,
    ToLocal(le.DateTime) AS [Time]
FROM Orion.OLM.LogEntry AS le
WHERE le.Severity <= 2
ORDER BY le.DateTime DESC
```

**Log volume by severity over the last hour:**

```sql
SELECT
    le.SeverityName AS [Severity],
    le.Severity AS [Level],
    COUNT(*) AS [Count]
FROM Orion.OLM.LogEntry AS le
WHERE MINUTEDIFF(le.DateTime, GETUTCDATE()) < 60
GROUP BY le.SeverityName, le.Severity
ORDER BY le.Severity ASC
```

**Top 10 nodes by error log volume today:**

```sql
SELECT TOP 10
    le.Node.Caption AS [Node],
    COUNT(*) AS [Error Count]
FROM Orion.OLM.LogEntry AS le
WHERE le.Severity <= 3
  AND DAYDIFF(le.DateTime, GETUTCDATE()) < 1
GROUP BY le.Node.Caption
ORDER BY [Error Count] DESC
```

---

## Orion.OLM.Tags (SWQL)

Represents a tag definition used to classify and categorize log entries via processing rules.

### SWQL Properties

| Property | Type | Description |
|----------|------|-------------|
| TagID | Int32 | Primary key. Unique tag identifier |
| Name | String | Tag name |
| Description | String | Tag description |
| Color | String | Display color for the tag in the UI |
| UsageCount | Int64 | Number of log entries with this tag |
| CreatedDate | DateTime | When the tag was created |

### Example SWQL Queries

**All tags with usage counts:**

```sql
SELECT
    t.Name AS [Tag],
    t.Description,
    t.UsageCount AS [Entries Tagged],
    t.Color
FROM Orion.OLM.Tags AS t
ORDER BY t.UsageCount DESC
```

---

## Orion.OLM.LogEntryLevel (SWQL)

Provides a lookup table mapping syslog severity levels to their names and descriptions.

### SWQL Properties

| Property | Type | Description |
|----------|------|-------------|
| Level | Int32 | Primary key. Syslog severity level (0-7) |
| Name | String | Severity name (Emergency, Alert, Critical, Error, Warning, Notice, Informational, Debug) |
| Description | String | Severity level description |

### Example SWQL Queries

**Severity level reference:**

```sql
SELECT
    l.Level,
    l.Name AS [Severity],
    l.Description
FROM Orion.OLM.LogEntryLevel AS l
ORDER BY l.Level ASC
```

---

## SWQL LA Schema Discovery

Use these metadata queries to explore available Log Analyzer entities and properties at runtime:

```sql
-- List all OLM entities
SELECT FullName, EntityName
FROM Metadata.Entity
WHERE FullName LIKE 'Orion.OLM.%'
ORDER BY EntityName

-- List properties of a specific LA entity
SELECT Name, Type, IsNavigable, IsKey
FROM Metadata.Property
WHERE EntityName = 'Orion.OLM.LogEntry'
```
