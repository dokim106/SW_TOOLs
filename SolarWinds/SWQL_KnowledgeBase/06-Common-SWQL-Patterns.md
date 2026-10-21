# Common SWQL Patterns and Best Practices

## SWQL Node Status Values and Filtering

Complete reference for node status integer codes and common filtering patterns used in SWQL queries.

Node Status codes (`Orion.Nodes.Status`):

| Code | Status             |
|------|--------------------|
| 1    | Up                 |
| 2    | Down               |
| 3    | Warning            |
| 4    | Shutdown           |
| 9    | Unmanaged          |
| 12   | Unreachable        |
| 14   | Critical           |
| 15   | Mixed Availability |
| 22   | Unplugged          |

The `StatusDescription` property provides the text equivalent, but comparing the `Status` integer is faster for filtering in SWQL queries.

```sql
-- SWQL: All down nodes
SELECT Caption, IPAddress, StatusDescription
FROM Orion.Nodes
WHERE Status = 2

-- SWQL: All problematic nodes (not Up and not Unmanaged)
SELECT Caption, IPAddress, StatusDescription
FROM Orion.Nodes
WHERE Status NOT IN (1, 9)

-- SWQL: Status summary dashboard
SELECT StatusDescription, COUNT(*) AS [Count]
FROM Orion.Nodes
GROUP BY StatusDescription
ORDER BY [Count] DESC
```

## SWQL Interface Status Values

Interface status codes and operational/admin status values for SWQL queries against `Orion.NPM.Interfaces`.

Interface Status (`Orion.NPM.Interfaces.Status`):

| Code | Status        |
|------|---------------|
| 1    | Up            |
| 2    | Down          |
| 3    | Warning       |
| 4    | Shutdown      |
| 6    | Testing       |
| 9    | Unmanaged     |
| 10   | Dormant       |
| 11   | NotPresent    |
| 24   | InactiveBulk  |

OperStatus and AdminStatus follow IETF standards:

- AdminStatus: 1=Up, 2=Down, 3=Testing
- OperStatus: 1=Up, 2=Down, 3=Testing, 4=Unknown, 5=Dormant, 6=NotPresent, 7=LowerLayerDown

```sql
-- SWQL: Down interfaces on up nodes
SELECT n.Caption AS [Node], i.Caption AS [Interface], i.StatusDescription
FROM Orion.NPM.Interfaces AS i
INNER JOIN Orion.Nodes AS n ON i.NodeID = n.NodeID
WHERE i.Status = 2 AND n.Status = 1
```

## SWQL Custom Property Access Patterns

Custom properties in SWQL are accessed via the `CustomProperties` navigation property or the entity's custom property table. This applies to nodes, interfaces, volumes, and other entities that support custom properties.

```sql
-- SWQL: Via navigation property (most common)
SELECT Caption, CustomProperties.City, CustomProperties.Environment
FROM Orion.Nodes
WHERE CustomProperties.Environment = 'Production'

-- SWQL: List all custom property definitions
SELECT Field, Description, DataType, MaxLength
FROM Orion.CustomProperty
WHERE TargetEntity = 'Orion.NodesCustomProperties'

-- SWQL: Nodes with a specific custom property value
SELECT n.Caption, n.IPAddress, n.CustomProperties.Department
FROM Orion.Nodes AS n
WHERE n.CustomProperties.Department IS NOT NULL
ORDER BY n.CustomProperties.Department
```

## SWQL Date and Time Filtering Patterns

Common date-based SWQL query patterns. SWQL stores timestamps in UTC. Use `GetUtcDate()` for UTC comparisons and `GetDate()` / `ToLocal()` for local time operations.

```sql
-- SWQL: Events in the last 24 hours
SELECT EventTime, Message, Node.Caption
FROM Orion.Events
WHERE EventTime > AddDay(-1, GetUtcDate())
ORDER BY EventTime DESC

-- SWQL: Events in the last 7 days
SELECT EventTime, Message
FROM Orion.Events
WHERE EventTime > AddDay(-7, GetUtcDate())

-- SWQL: Events today (local time)
SELECT EventTime, Message
FROM Orion.Events
WHERE DateTrunc('day', ToLocal(EventTime)) = DateTrunc('day', GetDate())

-- SWQL: Nodes not polled in over 24 hours
SELECT Caption, LastSystemUpTimePollUtc
FROM Orion.Nodes
WHERE DayDiff(LastSystemUpTimePollUtc, GetUtcDate()) > 1

-- SWQL: Alerts triggered this month
SELECT AlertActive.AlertName, TriggeredDateTime
FROM Orion.AlertHistory
WHERE Month(TriggeredDateTime) = Month(GetDate())
  AND Year(TriggeredDateTime) = Year(GetDate())
```

## SWQL Counting and Summarization Patterns

Dashboard-style aggregation SWQL queries for summaries, grouping, and top-N reporting.

```sql
-- SWQL: Count by vendor and machine type
SELECT Concat(Vendor, ' - ', MachineType) AS [Device Type], COUNT(*) AS [Count]
FROM Orion.Nodes
GROUP BY Vendor, MachineType
ORDER BY [Count] DESC

-- SWQL: Summary by status
SELECT
    SUM(CASE WHEN Status = 1 THEN 1 ELSE 0 END) AS [Up],
    SUM(CASE WHEN Status = 2 THEN 1 ELSE 0 END) AS [Down],
    SUM(CASE WHEN Status = 3 THEN 1 ELSE 0 END) AS [Warning],
    SUM(CASE WHEN Status = 9 THEN 1 ELSE 0 END) AS [Unmanaged],
    COUNT(*) AS [Total]
FROM Orion.Nodes

-- SWQL: Nodes per polling engine
SELECT e.ServerName AS [Engine], COUNT(n.NodeID) AS [Node Count]
FROM Orion.Nodes AS n
INNER JOIN Orion.Engines AS e ON n.EngineID = e.EngineID
GROUP BY e.ServerName
ORDER BY [Node Count] DESC

-- SWQL: Top 10 busiest interfaces by utilization
SELECT TOP 10
    n.Caption AS [Node],
    i.Caption AS [Interface],
    i.InPercentUtil AS [In %],
    i.OutPercentUtil AS [Out %]
FROM Orion.NPM.Interfaces AS i
INNER JOIN Orion.Nodes AS n ON i.NodeID = n.NodeID
WHERE i.Status = 1
ORDER BY (i.InPercentUtil + i.OutPercentUtil) DESC
```

## SWQL Volume and Disk Space Patterns

SWQL queries for monitoring disk space and volume utilization. Volume sizes are stored in bytes, so divide by `1073741824.0` (1024^3) to convert to gigabytes.

```sql
-- SWQL: Volumes with low disk space (less than 10% free)
SELECT
    n.Caption AS [Node],
    v.Caption AS [Volume],
    v.VolumePercentUsed AS [Used %],
    ROUND(v.VolumeSpaceAvailable / 1073741824.0, 2) AS [Free GB],
    ROUND(v.VolumeSize / 1073741824.0, 2) AS [Total GB]
FROM Orion.Volumes AS v
INNER JOIN Orion.Nodes AS n ON v.NodeID = n.NodeID
WHERE v.VolumePercentUsed > 90
ORDER BY v.VolumePercentUsed DESC

-- SWQL: Volume type summary
SELECT VolumeType, COUNT(*) AS [Count]
FROM Orion.Volumes
GROUP BY VolumeType
```

## SWQL Alert Query Patterns

SWQL queries for working with active alerts, alert history, and alert configuration.

```sql
-- SWQL: Currently active (triggered) alerts
SELECT
    a.AlertActive.AlertName AS [Alert],
    a.AlertActive.TriggeredDateTime AS [Triggered],
    a.AlertActive.AcknowledgedBy AS [Acked By],
    a.AlertActive.EntityCaption AS [Object]
FROM Orion.AlertActive AS a
ORDER BY a.AlertActive.TriggeredDateTime DESC

-- SWQL: Alert configuration summary
SELECT
    Name,
    CASE Enabled
        WHEN 'True' THEN 'Enabled'
        ELSE 'Disabled'
    END AS [Status],
    Severity
FROM Orion.AlertConfigurations
ORDER BY Enabled DESC, Name

-- SWQL: Count of alerts by severity
SELECT Severity, COUNT(*) AS [Count]
FROM Orion.AlertConfigurations
WHERE Enabled = 'True'
GROUP BY Severity
```

## SWQL Performance and Optimization Tips

Best practices for writing efficient SWQL queries:

1. **Select only needed columns** - Avoid `SELECT *`, specify columns explicitly. This reduces data transfer and processing time.
2. **Use TOP for testing** - Test with `TOP 10` before running full queries against large tables.
3. **Filter early** - Put `WHERE` conditions to reduce result sets before joins and aggregation.
4. **Use Status integers in SWQL** - `WHERE Status=1` is faster than `WHERE StatusDescription='Up'`.
5. **Prefer navigation properties** - Dot notation (e.g., `Node.Caption`) is often optimized better than explicit JOINs in SWQL.
6. **Parameterize queries** - Use `@param` syntax with `Get-SwisData` to prevent injection.
7. **Avoid unnecessary ORDER BY** - Sorting is expensive on large result sets.
8. **Use COUNT(*) wisely** - `COUNT(*)` with complex JOINs can be slow.
9. **SWQL is read-only** - Do not attempt INSERT/UPDATE/DELETE; use CRUD verb operations instead.
10. **Test in SWQL Studio first** - Validate queries interactively before embedding in scripts.

```sql
-- BAD SWQL: Selecting all columns
SELECT * FROM Orion.Nodes

-- GOOD SWQL: Select specific columns
SELECT NodeID, Caption, IPAddress, Status FROM Orion.Nodes

-- BAD SWQL: String comparison for status
SELECT Caption FROM Orion.Nodes WHERE StatusDescription = 'Down'

-- GOOD SWQL: Integer comparison for status
SELECT Caption FROM Orion.Nodes WHERE Status = 2
```

## SWQL Common Pitfalls and Gotchas

Known issues and non-obvious behaviors to watch for when writing SWQL queries.

- **Boolean values in SWQL**: Some properties use string `'True'`/`'False'` not boolean `true`/`false`.
  ```sql
  -- SWQL: Correct string boolean comparison
  WHERE Enabled = 'True'
  ```
- **GETDATE() vs GetDate()**: Both work in SWQL, but `GetDate()` is the canonical form.
- **Navigation property depth**: Deep chains like `a.b.c.d.Property` may fail if any relationship in the chain does not exist for a given row.
- **NULL handling in SWQL**: Use the `IsNull()` function. `COALESCE` is not supported in SWQL.
  ```sql
  -- SWQL: Use IsNull instead of COALESCE
  SELECT IsNull(Caption, 'Unknown') AS [Name]
  FROM Orion.Nodes
  ```
- **No COALESCE, no IIF in SWQL**: Use `CASE WHEN ... THEN ... ELSE ... END` instead.
  ```sql
  -- SWQL: Use CASE WHEN instead of IIF
  SELECT CASE WHEN Status = 1 THEN 'Healthy' ELSE 'Problem' END AS [Health]
  FROM Orion.Nodes
  ```
- **No TOP with UNION in SWQL**: Apply `TOP` to each individual `SELECT` in the `UNION`, not the overall result.
- **String wildcards in SWQL**: Use `%` not `*` in `LIKE` patterns.
  ```sql
  -- SWQL: Correct wildcard usage
  WHERE Caption LIKE '%switch%'
  ```
- **Column aliases in SWQL WHERE**: You cannot use column aliases in the `WHERE` clause. Repeat the full expression or use a subquery.
  ```sql
  -- SWQL BAD: Alias in WHERE
  SELECT Concat(Vendor, ' ', MachineType) AS [DevType]
  FROM Orion.Nodes
  WHERE [DevType] LIKE '%Cisco%'   -- WILL NOT WORK

  -- SWQL GOOD: Repeat the expression
  SELECT Concat(Vendor, ' ', MachineType) AS [DevType]
  FROM Orion.Nodes
  WHERE Concat(Vendor, ' ', MachineType) LIKE '%Cisco%'
  ```
