# SWQL LA (Log Analyzer) Query Cookbook

> Consolidated SWQL queries for SolarWinds Log Analyzer (LA).
> Covers processing rules, log sources, profiles, retention policies, rule summaries, VMware events, and Windows event logs.

---

## Global Postprocessing

### Query: Postprocessing Rules List

/* List all Log Analyzer postprocessing rules with their enabled status. | Entities: `Orion.OLM.ProcessingRule` */

```sql
SELECT
    Enabled,
    Name
FROM
    Orion.OLM.ProcessingRule;
```

**Key points**:
- Postprocessing rules run after log messages are ingested and parsed.
- The `Enabled` field indicates whether each rule is actively processing incoming log data.
- This query returns all processing rules (both pre- and post-processing share the same entity); context determines usage.

---

## Global Preprocessing

### Query: Preprocessing Rules List

/* List all Log Analyzer preprocessing rules with their enabled status. | Entities: `Orion.OLM.ProcessingRule` */

```sql
SELECT
    Enabled,
    Name
FROM
    Orion.OLM.ProcessingRule;
```

**Key points**:
- Preprocessing rules run before log messages are fully parsed and stored.
- Uses the same `Orion.OLM.ProcessingRule` entity as postprocessing; the distinction between pre- and post-processing rules is determined by rule configuration within the SolarWinds UI.
- Useful for verifying that expected filtering and parsing rules are enabled.

---

## Log Sources

### Query: Log Sources by Engine

/* Count log message sources grouped by Orion polling engine, showing server name and type. | Entities: `Orion.OLM.MessageSources`, `Orion.Engines` */

```sql
SELECT
    ms.EngineID,
    e.ServerName,
    e.ServerType,
    COUNT(*) AS [IP Count]
FROM
    Orion.OLM.MessageSources AS ms
JOIN
    Orion.Engines AS e ON ms.EngineID = e.EngineID
GROUP BY
    ms.EngineID,
    e.ServerName,
    e.ServerType
ORDER BY
    ms.EngineID ASC;
```

**Key points**:
- Joins message sources with the Engines entity to correlate log sources to their assigned polling engine.
- `IP Count` represents the number of distinct log-sending sources per engine.
- Useful for identifying engine load distribution and capacity planning for log ingestion.
- `ServerType` distinguishes between primary and additional polling engines.

---

## Profiles Used

### Query: Log Profiles Inventory

/* List all Log Analyzer profiles with their name and description. | Entities: `Orion.OLM.LogProfile` */

```sql
SELECT
    Name,
    Description
FROM
    Orion.OLM.LogProfile;
```

**Key points**:
- Log profiles define parsing templates that extract structured fields from raw log messages.
- The `Description` field provides context about what each profile is designed to parse.
- Useful for auditing which log parsing profiles are configured and available.

---

## Retention

### Query: Log Retention Periods by Type

/* Retrieve the configured retention period (in days) for each log entry type. | Entities: `Orion.OLM.LogEntryType` */

```sql
SELECT
    Name AS [Log Type],
    CONCAT(RetentionPeriodInDays, ' days') AS [Retention Time]
FROM
    Orion.OLM.LogEntryType;
```

**Key points**:
- Each log type (e.g., Syslog, Windows Events, VMware Events, Traps) can have a different retention period.
- `RetentionPeriodInDays` controls how long log entries of each type are kept before automatic purging.
- Important for compliance auditing and storage capacity planning.
- The `CONCAT` function formats the output as a human-readable string (e.g., "90 days").

---

## Rules

### Query: Processing Rules Summary by Type

/* Summarize processing rules by type (Out-of-Box vs Custom), showing total and enabled counts. | Entities: `Orion.OLM.ProcessingRule` */

```sql
SELECT
    CASE
        WHEN ReadOnly = 'True' THEN 'Out-of-Box'
        ELSE 'Custom'
    END AS [Type],
    COUNT(*) AS [Total Count],
    COUNT(CASE WHEN Enabled = 'true' THEN 1 END) AS [Enabled Count]
FROM
    Orion.OLM.ProcessingRule
GROUP BY
    CASE
        WHEN ReadOnly = 'True' THEN 'Out-of-Box'
        ELSE 'Custom'
    END
ORDER BY
    [Total Count] DESC;
```

**Key points**:
- Classifies rules as "Out-of-Box" (ReadOnly = True, shipped with the product) or "Custom" (user-created).
- Shows both total and enabled counts to identify unused or disabled rules.
- `ReadOnly` is a string field (`'True'`/`'False'`), not a boolean.
- Useful for understanding the ratio of custom rules to built-in rules and how many are actively enabled.

---

## VMware Events

### Query: VMware Event Count (Last 90 Days)

/* Count VMware events ingested by Log Analyzer in the last 90 days. | Entities: `Orion.OLM.LogEntry`, `Orion.OLM.LogEntryType` */

```sql
SELECT
    COUNT(CASE WHEN logs.LogEntryTypeID = 5 THEN logs.LogEntryID END) AS [VMware Events in 90 days]
FROM
    Orion.OLM.LogEntry AS logs
JOIN
    Orion.OLM.LogEntryType AS type ON type.LogEntryTypeID = logs.LogEntryTypeID
WHERE
    logs.LogEntryTypeID IN (5)
    AND logs.DateTime > ADDDATE('day', -90, GETUTCDATE());
```

**Key points**:
- `LogEntryTypeID = 5` corresponds to VMware events in the Log Analyzer schema.
- Uses `ADDDATE('day', -90, GETUTCDATE())` for SWQL-compatible date arithmetic (last 90 days from current UTC time).
- The JOIN with `LogEntryType` enables access to type metadata if needed for extended queries.
- High event counts may indicate noisy VMware environments or misconfigured event forwarding.

---

## Windows Logs and Events

### Query: Windows Event Count (Last 90 Days)

/* Count Windows events ingested by Log Analyzer in the last 90 days. | Entities: `Orion.OLM.LogEntry`, `Orion.OLM.LogEntryType` */

```sql
SELECT
    COUNT(CASE WHEN logs.LogEntryTypeID = 4 THEN logs.LogEntryID END) AS [Windows Events in 90 days]
FROM
    Orion.OLM.LogEntry AS logs
JOIN
    Orion.OLM.LogEntryType AS type ON type.LogEntryTypeID = logs.LogEntryTypeID
WHERE
    logs.LogEntryTypeID IN (4)
    AND logs.DateTime > ADDDATE('day', -90, GETUTCDATE());
```

**Key points**:
- `LogEntryTypeID = 4` corresponds to Windows events in the Log Analyzer schema.
- Uses the same date arithmetic pattern as the VMware Events query (`ADDDATE` with `GETUTCDATE`).
- Windows events include Security, Application, and System event logs forwarded to Log Analyzer.
- Useful for measuring log volume and validating that Windows event collection is working.

---



