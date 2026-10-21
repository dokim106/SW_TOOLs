# SWQL Syntax Reference

## SWQL SELECT Statement Basics

The SWQL `SELECT` statement retrieves data from the SolarWinds Information Service (SWIS). SWQL follows SQL-like syntax but queries the SolarWinds object model (entities) rather than raw database tables.

### Basic Column Selection

Select specific columns from an entity:

```sql
SELECT Caption, IPAddress, Status
FROM Orion.Nodes
```

### SELECT with Column Aliases

Use `AS` to rename columns in output. Bracket notation `[Column Name]` allows spaces in alias names:

```sql
SELECT n.Caption AS [Node Name], n.IPAddress AS [IP Address], n.Vendor AS [Device Vendor]
FROM Orion.Nodes AS n
```

Without brackets (no spaces in alias):

```sql
SELECT Caption AS NodeCaption, IPAddress AS Address
FROM Orion.Nodes
```

### SELECT DISTINCT

Eliminate duplicate rows from the result set:

```sql
SELECT DISTINCT Vendor
FROM Orion.Nodes

SELECT DISTINCT Vendor, MachineType
FROM Orion.Nodes

SELECT DISTINCT Status
FROM Orion.Nodes
```

### SELECT TOP n

Limit the number of rows returned. Always pair with `ORDER BY` for deterministic results:

```sql
SELECT TOP 10 Caption, ResponseTime
FROM Orion.Nodes
ORDER BY ResponseTime DESC

SELECT TOP 5 Caption, CPULoad
FROM Orion.Nodes
WHERE CPULoad IS NOT NULL
ORDER BY CPULoad DESC

SELECT TOP 25 Caption, IPAddress, Status
FROM Orion.Nodes
ORDER BY Caption ASC
```

### Combining SELECT Features

```sql
SELECT TOP 20
    n.Caption AS [Node Name],
    n.IPAddress AS [IP Address],
    n.Vendor AS [Vendor],
    n.ResponseTime AS [Response Time (ms)]
FROM Orion.Nodes AS n
WHERE n.Status = 1
ORDER BY n.ResponseTime DESC
```

---

## SWQL FROM Clause and Entity Names

In SWQL, you query **entities** rather than database tables. Entities follow the naming convention `Namespace.EntityName`. The `FROM` clause specifies which entity (or entities) to query.

### Entity Naming Convention

The format is always `Namespace.EntityName`. Common namespaces include:

| Namespace | Product / Module |
|-----------|-----------------|
| `Orion` | Core SolarWinds Platform |
| `Orion.NPM` | Network Performance Monitor |
| `Orion.APM` | Server & Application Monitor |
| `IPAM` | IP Address Manager |
| `Cirrus` | Network Configuration Manager |
| `Orion.SEUM` | Web Performance Monitor |
| `Orion.Netflow` | NetFlow Traffic Analyzer |
| `Orion.DPA` | Database Performance Analyzer |
| `Orion.VIM` | Virtualization Manager |

### Basic FROM Examples

```sql
-- Core platform: Nodes
SELECT Caption, IPAddress FROM Orion.Nodes

-- NPM: Interfaces
SELECT Caption, Status FROM Orion.NPM.Interfaces

-- APM: Applications
SELECT Name, Status FROM Orion.APM.Application

-- IPAM: Subnets
SELECT Address, CIDR, FriendlyName FROM IPAM.Subnet

-- NCM: Config nodes
SELECT NodeCaption, LastConfigDownload FROM Cirrus.Nodes

-- Alerts
SELECT Name, Enabled FROM Orion.AlertConfigurations

-- Events / Syslog
SELECT Message, DateTime FROM Orion.Events

-- Volumes (disk/storage)
SELECT Caption, VolumePercentUsed FROM Orion.Volumes
```

### Table Aliasing with AS

Aliases shorten entity references, especially in multi-entity queries:

```sql
SELECT n.Caption, n.IPAddress
FROM Orion.Nodes AS n

SELECT i.Caption, i.Status, i.InBandwidth
FROM Orion.NPM.Interfaces AS i

SELECT a.Name, a.Status
FROM Orion.APM.Application AS a
WHERE a.Status <> 1
```

### Discovering Available Entities

You can query the SWIS metadata to list available entities:

```sql
-- List all entity types in a namespace
SELECT EntityName
FROM Metadata.Entity
WHERE Namespace = 'Orion'

-- List columns/properties of an entity
SELECT Name, Type
FROM Metadata.Property
WHERE EntityName = 'Orion.Nodes'
```

---

## SWQL WHERE Clause and Filtering

The SWQL `WHERE` clause filters rows returned by a query. SWQL supports standard comparison operators, logical operators, pattern matching, range checks, set membership, and NULL handling.

### Comparison Operators

| Operator | Meaning |
|----------|---------|
| `=` | Equal to |
| `!=` or `<>` | Not equal to |
| `<` | Less than |
| `>` | Greater than |
| `<=` | Less than or equal to |
| `>=` | Greater than or equal to |

```sql
SELECT Caption FROM Orion.Nodes WHERE Status = 1
SELECT Caption FROM Orion.Nodes WHERE Status != 1
SELECT Caption FROM Orion.Nodes WHERE Status <> 1
SELECT Caption FROM Orion.Nodes WHERE ResponseTime > 100
SELECT Caption FROM Orion.Nodes WHERE CPULoad >= 90
SELECT Caption FROM Orion.Nodes WHERE ResponseTime <= 50
```

### Logical Operators: AND, OR, NOT

Combine multiple conditions. Use parentheses to control evaluation order:

```sql
-- AND: both conditions must be true
SELECT Caption, IPAddress
FROM Orion.Nodes
WHERE Vendor = 'Cisco' AND Status = 1

-- OR: at least one condition must be true
SELECT Caption, IPAddress
FROM Orion.Nodes
WHERE Status = 2 OR Status = 3

-- NOT: negate a condition
SELECT Caption
FROM Orion.Nodes
WHERE NOT Vendor = 'Cisco'

-- Combined with parentheses for precedence
SELECT Caption, IPAddress
FROM Orion.Nodes
WHERE (Status = 2 OR Status = 3) AND Vendor = 'Cisco'

-- Without parentheses, AND binds tighter than OR
-- This means: (Vendor='Cisco' AND Status=1) OR Status=2
SELECT Caption
FROM Orion.Nodes
WHERE Vendor = 'Cisco' AND Status = 1 OR Status = 2
```

### Pattern Matching: LIKE

The `LIKE` operator matches string patterns. Use `%` as a wildcard for zero or more characters:

```sql
-- Starts with 'switch'
SELECT Caption FROM Orion.Nodes WHERE Caption LIKE 'switch%'

-- Ends with '-core'
SELECT Caption FROM Orion.Nodes WHERE Caption LIKE '%-core'

-- Contains 'switch' anywhere
SELECT Caption FROM Orion.Nodes WHERE Caption LIKE '%switch%'

-- NOT LIKE: exclude matching rows
SELECT Caption FROM Orion.Nodes WHERE Caption NOT LIKE '%test%'

-- Multiple LIKE conditions
SELECT Caption FROM Orion.Nodes
WHERE Caption LIKE '%fw%' OR Caption LIKE '%firewall%'
```

**Note on case sensitivity:** SWQL string comparisons (including `LIKE`) are generally **case-insensitive** on most SolarWinds deployments because the underlying SQL Server collation is typically case-insensitive. However, this depends on the database collation setting. Do not rely on case-insensitive behavior in all environments.

### Range: BETWEEN

`BETWEEN` is inclusive of both boundaries:

```sql
-- Nodes with response time between 50ms and 200ms (inclusive)
SELECT Caption, ResponseTime
FROM Orion.Nodes
WHERE ResponseTime BETWEEN 50 AND 200

-- NOT BETWEEN
SELECT Caption, ResponseTime
FROM Orion.Nodes
WHERE ResponseTime NOT BETWEEN 0 AND 100

-- Date range example
SELECT Caption, DateTime
FROM Orion.Events
WHERE DateTime BETWEEN '2025-01-01' AND '2025-01-31'
```

### Set Membership: IN

Check if a value matches any value in a list:

```sql
-- Status is Up, Down, or Warning
SELECT Caption, Status
FROM Orion.Nodes
WHERE Status IN (1, 2, 3)

-- Vendor is Cisco or Juniper
SELECT Caption, Vendor
FROM Orion.Nodes
WHERE Vendor IN ('Cisco', 'Juniper Networks')

-- NOT IN: exclude a set of values
SELECT Caption, Status
FROM Orion.Nodes
WHERE Status NOT IN (9, 12)

-- Combine IN with other conditions
SELECT Caption, Vendor, Status
FROM Orion.Nodes
WHERE Vendor IN ('Cisco', 'Juniper Networks')
    AND Status = 1
```

### NULL Checks: IS NULL, IS NOT NULL

NULL represents missing or unknown data. Use `IS NULL` / `IS NOT NULL` (never `= NULL`):

```sql
-- Nodes with no SysName
SELECT Caption FROM Orion.Nodes WHERE SysName IS NULL

-- Nodes that have a SysName
SELECT Caption, SysName FROM Orion.Nodes WHERE SysName IS NOT NULL

-- Nodes missing contact information
SELECT Caption FROM Orion.Nodes WHERE Contact IS NULL

-- Combine NULL check with other filters
SELECT Caption, MachineType
FROM Orion.Nodes
WHERE MachineType IS NOT NULL AND Vendor = 'Cisco'
```

### Complex Filtering Examples

```sql
-- Cisco devices that are down or in warning, excluding test devices
SELECT Caption, IPAddress, Status
FROM Orion.Nodes
WHERE Vendor = 'Cisco'
    AND Status IN (2, 3)
    AND Caption NOT LIKE '%test%'
    AND Caption NOT LIKE '%lab%'

-- Devices with high response time and CPU load
SELECT Caption, ResponseTime, CPULoad
FROM Orion.Nodes
WHERE ResponseTime > 200
    AND CPULoad > 80
    AND Status = 1
ORDER BY ResponseTime DESC
```

---

## SWQL JOIN Syntax

SWQL supports joining multiple entities together using standard SQL join syntax. Joins allow you to combine rows from two or more entities based on a related column.

### INNER JOIN

Returns only rows where the join condition matches in both entities:

```sql
SELECT n.Caption, i.Caption AS [Interface], i.Status
FROM Orion.Nodes AS n
INNER JOIN Orion.NPM.Interfaces AS i ON n.NodeID = i.NodeID
WHERE n.Vendor = 'Cisco'

SELECT n.Caption AS [Node], v.Caption AS [Volume], v.VolumePercentUsed AS [Disk Used %]
FROM Orion.Nodes AS n
INNER JOIN Orion.Volumes AS v ON n.NodeID = v.NodeID
WHERE v.VolumePercentUsed > 80
ORDER BY v.VolumePercentUsed DESC
```

### LEFT JOIN (LEFT OUTER JOIN)

Returns all rows from the left entity, plus matching rows from the right entity. Non-matching right-side rows produce NULLs:

```sql
-- All nodes with their interface count (including nodes with zero interfaces)
SELECT n.Caption, COUNT(i.InterfaceID) AS [Interface Count]
FROM Orion.Nodes AS n
LEFT JOIN Orion.NPM.Interfaces AS i ON n.NodeID = i.NodeID
GROUP BY n.Caption

-- Find nodes that have NO interfaces
SELECT n.Caption, n.IPAddress
FROM Orion.Nodes AS n
LEFT JOIN Orion.NPM.Interfaces AS i ON n.NodeID = i.NodeID
WHERE i.InterfaceID IS NULL

-- LEFT OUTER JOIN is identical to LEFT JOIN
SELECT n.Caption, a.Name AS [Application]
FROM Orion.Nodes AS n
LEFT OUTER JOIN Orion.APM.Application AS a ON n.NodeID = a.NodeID
```

### RIGHT JOIN (RIGHT OUTER JOIN)

Returns all rows from the right entity, plus matching rows from the left entity:

```sql
SELECT n.Caption AS [Node], i.Caption AS [Interface]
FROM Orion.Nodes AS n
RIGHT JOIN Orion.NPM.Interfaces AS i ON n.NodeID = i.NodeID
```

### Multi-Table Joins

Join three or more entities by chaining JOIN clauses:

```sql
-- Nodes with their interfaces and interface current statistics
SELECT n.Caption AS [Node],
    i.Caption AS [Interface],
    ts.InAveragebps AS [Avg In bps],
    ts.OutAveragebps AS [Avg Out bps]
FROM Orion.Nodes AS n
INNER JOIN Orion.NPM.Interfaces AS i ON n.NodeID = i.NodeID
INNER JOIN Orion.NPM.InterfaceTraffic AS ts ON i.InterfaceID = ts.InterfaceID
WHERE n.Status = 1

-- Nodes, volumes, and custom properties
SELECT n.Caption AS [Node],
    v.Caption AS [Volume],
    v.VolumePercentUsed AS [Used %],
    cp.City AS [City]
FROM Orion.Nodes AS n
INNER JOIN Orion.Volumes AS v ON n.NodeID = v.NodeID
LEFT JOIN Orion.NodesCustomProperties AS cp ON n.NodeID = cp.NodeID
WHERE v.VolumePercentUsed > 85
ORDER BY v.VolumePercentUsed DESC
```

### JOIN with Additional Conditions

Add extra conditions to the ON clause or the WHERE clause:

```sql
-- Join with extra condition in WHERE
SELECT n.Caption, i.Caption AS [Interface], i.Status AS [Interface Status]
FROM Orion.Nodes AS n
INNER JOIN Orion.NPM.Interfaces AS i ON n.NodeID = i.NodeID
WHERE n.Vendor = 'Cisco'
    AND i.Status = 2

-- Multiple join conditions
SELECT n.Caption, a.Name AS [Alert], ah.Message
FROM Orion.Nodes AS n
INNER JOIN Orion.AlertActive AS a ON n.NodeID = a.ActiveObject
INNER JOIN Orion.AlertHistory AS ah ON a.AlertActiveID = ah.AlertActiveID
ORDER BY ah.TimeStamp DESC
```

---

## SWQL Navigation Properties (Dot Notation)

SWQL provides **navigation properties** that let you traverse relationships between entities using dot notation, eliminating the need for explicit JOINs. This is one of SWQL's most powerful features and a key difference from standard SQL.

### How Navigation Properties Work

Entities in SWIS have defined relationships. When entity A has a relationship to entity B, you can access B's properties directly from A using dot notation: `A.RelationshipName.PropertyName`.

### One-to-One Navigation (Direct Property Access)

Access a single related entity's properties:

```sql
-- Access custom properties directly via navigation
SELECT Caption, CustomProperties.City, CustomProperties.Department
FROM Orion.Nodes

-- Access the parent node from an interface
SELECT Caption, Status, Node.Caption AS [Parent Node]
FROM Orion.NPM.Interfaces

-- Access node info from an application
SELECT a.Name, a.Node.Caption AS [Node Name], a.Node.IPAddress AS [Node IP]
FROM Orion.APM.Application AS a

-- Access node from a volume
SELECT v.Caption, v.VolumePercentUsed, v.Node.Caption AS [Node Name]
FROM Orion.Volumes AS v
WHERE v.VolumePercentUsed > 90
```

### Chained Navigation (Multi-Level)

Chain navigation properties to traverse multiple levels:

```sql
-- Interface -> Node -> Custom Properties
SELECT i.Caption AS [Interface],
    i.Node.Caption AS [Node],
    i.Node.CustomProperties.City AS [City]
FROM Orion.NPM.Interfaces AS i
WHERE i.Status = 2

-- Volume -> Node -> Custom Properties
SELECT v.Caption AS [Volume],
    v.VolumePercentUsed AS [Used %],
    v.Node.Caption AS [Node],
    v.Node.Vendor AS [Vendor]
FROM Orion.Volumes AS v
WHERE v.VolumePercentUsed > 85
```

### Navigation vs Explicit JOIN Equivalence

Navigation properties are syntactic sugar for JOINs. These pairs are equivalent:

```sql
-- NAVIGATION PROPERTY approach
SELECT Caption, CustomProperties.City
FROM Orion.Nodes

-- EXPLICIT JOIN equivalent
SELECT n.Caption, cp.City
FROM Orion.Nodes AS n
INNER JOIN Orion.NodesCustomProperties AS cp ON n.NodeID = cp.NodeID
```

```sql
-- NAVIGATION PROPERTY approach
SELECT a.Name, a.Node.Caption AS [Node Name]
FROM Orion.APM.Application AS a

-- EXPLICIT JOIN equivalent
SELECT a.Name, n.Caption AS [Node Name]
FROM Orion.APM.Application AS a
INNER JOIN Orion.Nodes AS n ON a.NodeID = n.NodeID
```

```sql
-- NAVIGATION PROPERTY approach
SELECT i.Caption, i.Node.Caption AS [Node Name], i.Node.CustomProperties.City
FROM Orion.NPM.Interfaces AS i

-- EXPLICIT JOIN equivalent
SELECT i.Caption, n.Caption AS [Node Name], cp.City
FROM Orion.NPM.Interfaces AS i
INNER JOIN Orion.Nodes AS n ON i.NodeID = n.NodeID
INNER JOIN Orion.NodesCustomProperties AS cp ON n.NodeID = cp.NodeID
```

### Discovering Navigation Properties

Query metadata to see available navigation properties for an entity:

```sql
SELECT Name, Type
FROM Metadata.Property
WHERE EntityName = 'Orion.Nodes' AND IsNavigable = true
```

---

## SWQL GROUP BY and Aggregate Queries

SWQL supports standard SQL aggregate functions combined with `GROUP BY` to summarize data. The `HAVING` clause filters groups after aggregation.

### Aggregate Functions

| Function | Description |
|----------|-------------|
| `COUNT(*)` | Count all rows in the group |
| `COUNT(column)` | Count non-NULL values |
| `SUM(column)` | Sum of values |
| `AVG(column)` | Average of values |
| `MIN(column)` | Minimum value |
| `MAX(column)` | Maximum value |

### Basic GROUP BY

Every non-aggregated column in `SELECT` must appear in `GROUP BY`:

```sql
-- Count nodes by vendor
SELECT Vendor, COUNT(*) AS [Count]
FROM Orion.Nodes
GROUP BY Vendor
ORDER BY [Count] DESC

-- Count nodes by status
SELECT Status, COUNT(*) AS [Count]
FROM Orion.Nodes
GROUP BY Status

-- Count interfaces by node
SELECT n.Caption, COUNT(i.InterfaceID) AS [Interface Count]
FROM Orion.Nodes AS n
INNER JOIN Orion.NPM.Interfaces AS i ON n.NodeID = i.NodeID
GROUP BY n.Caption
ORDER BY [Interface Count] DESC
```

### Multiple Aggregate Functions

Use several aggregates in one query:

```sql
SELECT Vendor,
    COUNT(*) AS [Node Count],
    AVG(ResponseTime) AS [Avg Response Time],
    MAX(ResponseTime) AS [Max Response Time],
    MIN(ResponseTime) AS [Min Response Time]
FROM Orion.Nodes
WHERE Status = 1
GROUP BY Vendor
ORDER BY [Node Count] DESC
```

### GROUP BY Multiple Columns

```sql
SELECT Vendor, MachineType, COUNT(*) AS [Count]
FROM Orion.Nodes
GROUP BY Vendor, MachineType
ORDER BY Vendor, [Count] DESC

SELECT Vendor, Status, COUNT(*) AS [Count]
FROM Orion.Nodes
GROUP BY Vendor, Status
ORDER BY Vendor, Status
```

### HAVING Clause

`HAVING` filters groups after aggregation (unlike `WHERE`, which filters rows before aggregation):

```sql
-- Vendors with more than 5 nodes
SELECT Vendor, COUNT(*) AS [Count]
FROM Orion.Nodes
GROUP BY Vendor
HAVING COUNT(*) > 5
ORDER BY [Count] DESC

-- Nodes with more than 10 interfaces
SELECT n.Caption, COUNT(i.InterfaceID) AS [Interface Count]
FROM Orion.Nodes AS n
INNER JOIN Orion.NPM.Interfaces AS i ON n.NodeID = i.NodeID
GROUP BY n.Caption
HAVING COUNT(i.InterfaceID) > 10
ORDER BY [Interface Count] DESC

-- Vendors whose average response time exceeds a threshold
SELECT Vendor,
    COUNT(*) AS [Count],
    AVG(ResponseTime) AS [Avg Response Time]
FROM Orion.Nodes
WHERE Status = 1
GROUP BY Vendor
HAVING AVG(ResponseTime) > 100
ORDER BY [Avg Response Time] DESC
```

### WHERE vs HAVING

`WHERE` filters individual rows before grouping. `HAVING` filters groups after aggregation:

```sql
-- WHERE filters rows first, then GROUP BY aggregates, then HAVING filters groups
SELECT Vendor, COUNT(*) AS [Count], AVG(ResponseTime) AS [Avg RT]
FROM Orion.Nodes
WHERE Status = 1                  -- filter: only Up nodes
GROUP BY Vendor
HAVING COUNT(*) > 3               -- filter: only vendors with more than 3 Up nodes
ORDER BY [Avg RT] DESC
```

---

## SWQL ORDER BY Clause

The SWQL `ORDER BY` clause sorts query results. Without it, row order is undefined and not guaranteed.

### Ascending and Descending Sort

`ASC` (ascending) is the default. Use `DESC` for descending:

```sql
-- Ascending (default, ASC keyword is optional)
SELECT Caption, ResponseTime
FROM Orion.Nodes
ORDER BY Caption ASC

-- Descending
SELECT Caption, ResponseTime
FROM Orion.Nodes
ORDER BY ResponseTime DESC
```

### Multiple Column Ordering

Specify multiple columns to break ties. Rows are sorted by the first column, then by the second within ties, and so on:

```sql
SELECT Caption, Status, ResponseTime
FROM Orion.Nodes
ORDER BY Status ASC, ResponseTime DESC

SELECT Vendor, Caption, ResponseTime
FROM Orion.Nodes
ORDER BY Vendor ASC, Caption ASC

-- Sort by status first, then by highest response time within each status
SELECT Caption, Status, ResponseTime, CPULoad
FROM Orion.Nodes
WHERE Status IN (1, 2, 3)
ORDER BY Status ASC, ResponseTime DESC, CPULoad DESC
```

### ORDER BY with Aliases and Expressions

You can sort by column aliases or expressions:

```sql
SELECT Caption, ResponseTime AS [RT]
FROM Orion.Nodes
ORDER BY [RT] DESC

SELECT Vendor, COUNT(*) AS [Count]
FROM Orion.Nodes
GROUP BY Vendor
ORDER BY [Count] DESC
```

### ORDER BY with TOP

`ORDER BY` is essential with `TOP` to get deterministic results:

```sql
-- Top 10 slowest responding nodes
SELECT TOP 10 Caption, IPAddress, ResponseTime
FROM Orion.Nodes
WHERE Status = 1
ORDER BY ResponseTime DESC

-- Top 5 nodes with highest CPU load
SELECT TOP 5 Caption, CPULoad
FROM Orion.Nodes
WHERE CPULoad IS NOT NULL
ORDER BY CPULoad DESC
```

---

## SWQL CASE WHEN Expressions

SWQL supports `CASE` expressions for conditional logic within queries. There are two forms: **simple CASE** (compares a single expression) and **searched CASE** (evaluates independent boolean conditions).

### Simple CASE Expression

Compares one expression against multiple values:

```sql
SELECT Caption,
    Status,
    CASE Status
        WHEN 1 THEN 'Up'
        WHEN 2 THEN 'Down'
        WHEN 3 THEN 'Warning'
        WHEN 4 THEN 'Shutdown'
        WHEN 9 THEN 'Unmanaged'
        WHEN 12 THEN 'Unreachable'
        WHEN 14 THEN 'Critical'
        WHEN 15 THEN 'Mixed'
        ELSE 'Unknown'
    END AS [Status Text]
FROM Orion.Nodes

SELECT Caption,
    CASE Vendor
        WHEN 'Cisco' THEN 'Cisco Systems'
        WHEN 'Juniper Networks' THEN 'Juniper'
        WHEN 'Arista Networks' THEN 'Arista'
        ELSE Vendor
    END AS [Vendor Display Name]
FROM Orion.Nodes
```

### Searched CASE Expression

Evaluates each `WHEN` condition independently, allowing complex boolean logic:

```sql
SELECT Caption,
    CPULoad,
    CASE
        WHEN CPULoad > 95 THEN 'Critical'
        WHEN CPULoad > 80 THEN 'High'
        WHEN CPULoad > 60 THEN 'Warning'
        WHEN CPULoad > 0 THEN 'Normal'
        ELSE 'N/A'
    END AS [CPU Status]
FROM Orion.Nodes
WHERE CPULoad IS NOT NULL
ORDER BY CPULoad DESC

SELECT Caption,
    ResponseTime,
    CASE
        WHEN ResponseTime IS NULL THEN 'No Data'
        WHEN ResponseTime > 500 THEN 'Critical'
        WHEN ResponseTime > 200 THEN 'Slow'
        WHEN ResponseTime > 100 THEN 'Fair'
        ELSE 'Good'
    END AS [Performance]
FROM Orion.Nodes
WHERE Status = 1
```

### CASE in GROUP BY and Aggregation

Use CASE to create custom groupings:

```sql
SELECT
    CASE
        WHEN CPULoad > 90 THEN 'Critical (>90%)'
        WHEN CPULoad > 70 THEN 'Warning (70-90%)'
        WHEN CPULoad > 0 THEN 'Normal (<70%)'
        ELSE 'No Data'
    END AS [CPU Category],
    COUNT(*) AS [Count]
FROM Orion.Nodes
GROUP BY
    CASE
        WHEN CPULoad > 90 THEN 'Critical (>90%)'
        WHEN CPULoad > 70 THEN 'Warning (70-90%)'
        WHEN CPULoad > 0 THEN 'Normal (<70%)'
        ELSE 'No Data'
    END
ORDER BY [Count] DESC
```

### CASE in ORDER BY

Sort by computed categories:

```sql
SELECT Caption, Status
FROM Orion.Nodes
ORDER BY
    CASE Status
        WHEN 2 THEN 1    -- Down nodes first
        WHEN 14 THEN 2   -- Critical second
        WHEN 3 THEN 3    -- Warning third
        WHEN 1 THEN 4    -- Up last
        ELSE 5
    END ASC
```

### CASE for Interface Status Translation

```sql
SELECT i.Caption AS [Interface],
    i.Node.Caption AS [Node],
    CASE i.Status
        WHEN 1 THEN 'Up'
        WHEN 2 THEN 'Down'
        WHEN 3 THEN 'Warning'
        WHEN 4 THEN 'Shutdown'
        WHEN 6 THEN 'Testing'
        WHEN 9 THEN 'Unmanaged'
        WHEN 10 THEN 'Dormant'
        WHEN 11 THEN 'NotPresent'
        ELSE 'Unknown'
    END AS [Status Text]
FROM Orion.NPM.Interfaces AS i
WHERE i.Status != 1
```

---

## SWQL Subqueries

SWQL supports subqueries (nested queries) in the `WHERE` clause and the `SELECT` list. Subqueries let you use the result of one query as part of another.

### Subquery with IN

Return rows where a value matches any result from the subquery:

```sql
-- Nodes that have at least one interface with bandwidth > 1 Gbps
SELECT Caption, IPAddress
FROM Orion.Nodes
WHERE NodeID IN (
    SELECT NodeID FROM Orion.NPM.Interfaces
    WHERE InBandwidth > 1000000000
)

-- Nodes that have at least one volume over 90% used
SELECT Caption, IPAddress
FROM Orion.Nodes
WHERE NodeID IN (
    SELECT NodeID FROM Orion.Volumes
    WHERE VolumePercentUsed > 90
)

-- Nodes NOT in a specific set of vendors
SELECT Caption, IPAddress
FROM Orion.Nodes
WHERE Vendor NOT IN (
    SELECT DISTINCT Vendor FROM Orion.Nodes WHERE Status = 9
)
```

### Subquery with EXISTS

`EXISTS` returns true if the subquery returns at least one row. Typically uses a correlated reference to the outer query:

```sql
-- Nodes that have at least one down interface
SELECT n.Caption, n.IPAddress
FROM Orion.Nodes AS n
WHERE EXISTS (
    SELECT 1 FROM Orion.NPM.Interfaces AS i
    WHERE i.NodeID = n.NodeID AND i.Status = 2
)

-- Nodes that have NO volumes
SELECT n.Caption
FROM Orion.Nodes AS n
WHERE NOT EXISTS (
    SELECT 1 FROM Orion.Volumes AS v
    WHERE v.NodeID = n.NodeID
)
```

### Scalar Subquery in SELECT (Correlated Subquery)

A subquery in the SELECT list returns a single value per row:

```sql
-- Count interfaces per node using a subquery
SELECT n.Caption,
    (SELECT COUNT(*) FROM Orion.NPM.Interfaces AS i WHERE i.NodeID = n.NodeID) AS [Interface Count]
FROM Orion.Nodes AS n
ORDER BY [Interface Count] DESC

-- Count down interfaces per node
SELECT n.Caption,
    (SELECT COUNT(*) FROM Orion.NPM.Interfaces AS i WHERE i.NodeID = n.NodeID AND i.Status = 2) AS [Down Interfaces]
FROM Orion.Nodes AS n
ORDER BY [Down Interfaces] DESC

-- Get volume usage alongside node info
SELECT n.Caption,
    (SELECT MAX(v.VolumePercentUsed) FROM Orion.Volumes AS v WHERE v.NodeID = n.NodeID) AS [Max Disk Used %]
FROM Orion.Nodes AS n
WHERE n.Status = 1
ORDER BY [Max Disk Used %] DESC
```

### Subquery with Comparison Operators

Compare a value against a single-value subquery result:

```sql
-- Nodes with above-average response time
SELECT Caption, ResponseTime
FROM Orion.Nodes
WHERE ResponseTime > (
    SELECT AVG(ResponseTime) FROM Orion.Nodes WHERE Status = 1
)
ORDER BY ResponseTime DESC
```

---

## SWQL UNION and UNION ALL

SWQL supports `UNION` and `UNION ALL` to combine result sets from multiple queries. All queries in a UNION must have the same number of columns, and corresponding columns should have compatible data types.

### UNION ALL (Include Duplicates)

`UNION ALL` concatenates all rows from each query, including duplicates:

```sql
-- Summary counts by status category
SELECT 'Up' AS [Status], COUNT(*) AS [Count] FROM Orion.Nodes WHERE Status = 1
UNION ALL
SELECT 'Down', COUNT(*) FROM Orion.Nodes WHERE Status = 2
UNION ALL
SELECT 'Warning', COUNT(*) FROM Orion.Nodes WHERE Status = 3
UNION ALL
SELECT 'Unmanaged', COUNT(*) FROM Orion.Nodes WHERE Status = 9
UNION ALL
SELECT 'Unreachable', COUNT(*) FROM Orion.Nodes WHERE Status = 12
UNION ALL
SELECT 'Critical', COUNT(*) FROM Orion.Nodes WHERE Status = 14
```

### UNION (Remove Duplicates)

`UNION` removes duplicate rows from the combined result set:

```sql
-- All unique vendor names from both nodes and interfaces
SELECT DISTINCT Vendor AS [Name] FROM Orion.Nodes
UNION
SELECT DISTINCT Vendor FROM Orion.NPM.Interfaces
```

### Practical UNION Examples

```sql
-- Combined alert summary: nodes and interfaces with problems
SELECT 'Node' AS [Type], Caption AS [Name], IPAddress AS [Detail]
FROM Orion.Nodes
WHERE Status = 2
UNION ALL
SELECT 'Interface', i.Caption, i.Node.Caption
FROM Orion.NPM.Interfaces AS i
WHERE i.Status = 2
UNION ALL
SELECT 'Volume', v.Caption, v.Node.Caption
FROM Orion.Volumes AS v
WHERE v.VolumePercentUsed > 95
```

### Rules for UNION

1. Each SELECT must return the **same number of columns**
2. Column names come from the **first** SELECT statement
3. Data types of corresponding columns must be **compatible**
4. `ORDER BY` can only appear on the **last** SELECT (sorts the entire result)
5. `UNION ALL` is faster than `UNION` because it skips duplicate elimination

---

## SWQL Parameter Binding

SWQL supports **parameterized queries** using the `@parameterName` syntax. Parameters prevent injection issues and allow query reuse with different values. They are primarily used with the SolarWinds PowerShell module (SwisPowerShell) and the SWIS API.

### Parameter Syntax in SWQL

Parameters are prefixed with `@`:

```sql
SELECT Caption, IPAddress
FROM Orion.Nodes
WHERE Vendor = @vendor

SELECT Caption, IPAddress, Status
FROM Orion.Nodes
WHERE Vendor = @vendor AND Status = @status

SELECT Caption, IPAddress
FROM Orion.Nodes
WHERE Caption LIKE @pattern
```

### PowerShell Usage with Get-SwisData

Pass parameters as a hashtable:

```powershell
# Single parameter
Get-SwisData $swis "SELECT Caption, IPAddress FROM Orion.Nodes WHERE Vendor = @v" @{v='Cisco'}

# Multiple parameters
Get-SwisData $swis "SELECT Caption FROM Orion.Nodes WHERE Vendor = @v AND Status = @s" @{v='Cisco'; s=1}

# Parameter with LIKE wildcard
Get-SwisData $swis "SELECT Caption FROM Orion.Nodes WHERE Caption LIKE @pattern" @{pattern='%switch%'}

# Numeric parameter
Get-SwisData $swis "SELECT Caption, CPULoad FROM Orion.Nodes WHERE CPULoad > @threshold" @{threshold=80}
```

### PowerShell Usage with Invoke-SwisVerb

For SWIS verbs (actions), parameters are passed differently:

```powershell
# Query via Invoke-SwisVerb
$query = "SELECT Caption FROM Orion.Nodes WHERE NodeID = @id"
$results = Get-SwisData $swis $query @{id=42}
```

### Python (orionsdk) Usage

```python
from orionsdk import SwisClient

swis = SwisClient("solarwinds-server", "username", "password")

# Parameterized query
results = swis.query("SELECT Caption FROM Orion.Nodes WHERE Vendor = @v", v='Cisco')

# Multiple parameters
results = swis.query(
    "SELECT Caption FROM Orion.Nodes WHERE Vendor = @v AND Status = @s",
    v='Cisco', s=1
)
```

### Benefits of Parameter Binding

1. **Security**: prevents SWQL injection attacks
2. **Performance**: query plan reuse on the server
3. **Type safety**: parameters are type-checked automatically
4. **Readability**: separates query logic from data values

---

## SWQL Arithmetic Operators

SWQL supports standard arithmetic operators for numeric calculations within queries.

### Available Operators

| Operator | Description |
|----------|-------------|
| `+` | Addition |
| `-` | Subtraction |
| `*` | Multiplication |
| `/` | Division |
| `%` | Modulo (remainder) |

### Basic Arithmetic Examples

```sql
-- Average of CPU and memory load
SELECT Caption,
    CPULoad AS [CPU %],
    PercentMemoryUsed AS [Memory %],
    (CPULoad + PercentMemoryUsed) / 2 AS [Avg Load]
FROM Orion.Nodes
WHERE CPULoad IS NOT NULL AND PercentMemoryUsed IS NOT NULL
ORDER BY [Avg Load] DESC

-- Convert bytes to megabytes
SELECT Caption,
    TotalMemory AS [Total Memory Bytes],
    TotalMemory / 1048576 AS [Total Memory MB],
    TotalMemory / 1073741824 AS [Total Memory GB]
FROM Orion.Nodes
WHERE TotalMemory IS NOT NULL

-- Calculate free disk space from volume data
SELECT v.Caption,
    v.VolumeSize / 1073741824 AS [Total GB],
    (v.VolumeSize - v.VolumeSpaceUsed) / 1073741824 AS [Free GB],
    v.VolumePercentUsed AS [Used %],
    100 - v.VolumePercentUsed AS [Free %]
FROM Orion.Volumes AS v
WHERE v.VolumeSize > 0
ORDER BY v.VolumePercentUsed DESC
```

### Arithmetic in WHERE Clause

```sql
-- Nodes where CPU + Memory combined exceeds 160%
SELECT Caption, CPULoad, PercentMemoryUsed,
    CPULoad + PercentMemoryUsed AS [Combined Load]
FROM Orion.Nodes
WHERE (CPULoad + PercentMemoryUsed) > 160

-- Volumes with less than 10 GB free
SELECT v.Caption, v.Node.Caption AS [Node],
    (v.VolumeSize - v.VolumeSpaceUsed) / 1073741824 AS [Free GB]
FROM Orion.Volumes AS v
WHERE (v.VolumeSize - v.VolumeSpaceUsed) / 1073741824 < 10
    AND v.VolumeSize > 0
ORDER BY [Free GB] ASC
```

### Arithmetic with Aggregates

```sql
SELECT Vendor,
    COUNT(*) AS [Total],
    SUM(CASE WHEN Status = 1 THEN 1 ELSE 0 END) AS [Up Count],
    SUM(CASE WHEN Status = 2 THEN 1 ELSE 0 END) AS [Down Count]
FROM Orion.Nodes
GROUP BY Vendor
ORDER BY [Total] DESC
```

---

## SWQL String Concatenation

SWQL provides the `Concat()` function for combining string values. Unlike standard SQL, SWQL uses a function rather than the `+` or `||` operators for string concatenation.

### Concat() Function

The `Concat()` function takes two or more arguments and joins them into a single string:

```sql
-- Combine vendor and machine type
SELECT Concat(Vendor, ' - ', MachineType) AS [Device Type]
FROM Orion.Nodes
WHERE MachineType IS NOT NULL

-- Build a display label for nodes
SELECT Concat(Caption, ' (', IPAddress, ')') AS [Node Label]
FROM Orion.Nodes

-- Multi-field concatenation
SELECT Concat(Caption, ' | ', Vendor, ' | ', MachineType) AS [Node Summary]
FROM Orion.Nodes
WHERE Vendor IS NOT NULL

-- Build a descriptive status line
SELECT Concat(
    Caption, ' is ',
    CASE Status
        WHEN 1 THEN 'Up'
        WHEN 2 THEN 'Down'
        WHEN 3 THEN 'Warning'
        ELSE 'Unknown'
    END,
    ' (', IPAddress, ')'
) AS [Status Line]
FROM Orion.Nodes
```

### Concat with Other Functions

```sql
-- Combine with ToString for numeric values
SELECT Concat(Caption, ' - CPU: ', ToString(CPULoad), '%') AS [CPU Info]
FROM Orion.Nodes
WHERE CPULoad IS NOT NULL

-- Combine with navigation properties
SELECT Concat(i.Caption, ' on ', i.Node.Caption) AS [Interface on Node]
FROM Orion.NPM.Interfaces AS i
```

### Concat in WHERE Clause

```sql
SELECT Caption, IPAddress
FROM Orion.Nodes
WHERE Concat(Caption, ' ', IPAddress) LIKE '%192.168%'
```

---

## SWQL Common Status Codes Reference

SWQL queries frequently filter or translate numeric status codes. This section provides a comprehensive reference for status codes used across SolarWinds entities.

### Node Status Codes (Orion.Nodes.Status)

| Code | Status | Description |
|------|--------|-------------|
| 0 | Unknown | Status has not been determined |
| 1 | Up | Node is responding normally |
| 2 | Down | Node is not responding |
| 3 | Warning | Node has warning-level alerts |
| 4 | Shutdown | Node is administratively shut down |
| 9 | Unmanaged | Node is not being monitored |
| 12 | Unreachable | Node cannot be reached (path issue) |
| 14 | Critical | Node has critical-level issues |
| 15 | Mixed | Child objects have mixed statuses |
| 22 | Unplugged | Node is physically disconnected |

#### SWQL Query to Decode Node Statuses

```sql
SELECT Caption, IPAddress,
    Status,
    CASE Status
        WHEN 0 THEN 'Unknown'
        WHEN 1 THEN 'Up'
        WHEN 2 THEN 'Down'
        WHEN 3 THEN 'Warning'
        WHEN 4 THEN 'Shutdown'
        WHEN 9 THEN 'Unmanaged'
        WHEN 12 THEN 'Unreachable'
        WHEN 14 THEN 'Critical'
        WHEN 15 THEN 'Mixed'
        WHEN 22 THEN 'Unplugged'
        ELSE 'Other'
    END AS [Status Text]
FROM Orion.Nodes
ORDER BY Status
```

#### Count Nodes by Status

```sql
SELECT
    CASE Status
        WHEN 1 THEN 'Up'
        WHEN 2 THEN 'Down'
        WHEN 3 THEN 'Warning'
        WHEN 9 THEN 'Unmanaged'
        WHEN 12 THEN 'Unreachable'
        WHEN 14 THEN 'Critical'
        ELSE 'Other'
    END AS [Status],
    COUNT(*) AS [Count]
FROM Orion.Nodes
GROUP BY Status
ORDER BY Status
```

### Interface Status Codes (Orion.NPM.Interfaces.Status)

| Code | Status | Description |
|------|--------|-------------|
| 1 | Up | Interface is operational |
| 2 | Down | Interface is not operational |
| 3 | Warning | Interface has warning conditions |
| 4 | Shutdown | Interface is administratively down |
| 6 | Testing | Interface is in test mode |
| 9 | Unmanaged | Interface is not being monitored |
| 10 | Dormant | Interface is in dormant state |
| 11 | NotPresent | Interface hardware is not present |
| 24 | InactiveBulk | Bulk-inactivated interface |

#### SWQL Query to Decode Interface Statuses

```sql
SELECT i.Caption AS [Interface],
    i.Node.Caption AS [Node],
    CASE i.Status
        WHEN 1 THEN 'Up'
        WHEN 2 THEN 'Down'
        WHEN 3 THEN 'Warning'
        WHEN 4 THEN 'Shutdown'
        WHEN 6 THEN 'Testing'
        WHEN 9 THEN 'Unmanaged'
        WHEN 10 THEN 'Dormant'
        WHEN 11 THEN 'NotPresent'
        WHEN 24 THEN 'InactiveBulk'
        ELSE 'Unknown'
    END AS [Status Text]
FROM Orion.NPM.Interfaces AS i
WHERE i.Status != 1
ORDER BY i.Status
```

### Alert Status Codes (Orion.AlertActive)

| Code | Status | Description |
|------|--------|-------------|
| 0 | Not Triggered | Alert condition is not met |
| 1 | Triggered | Alert has been triggered |
| 2 | Acknowledged | Alert has been acknowledged by a user |

#### SWQL Query for Active Alerts by Status

```sql
SELECT a.Name AS [Alert Name],
    CASE a.Acknowledged
        WHEN 0 THEN 'Not Acknowledged'
        WHEN 1 THEN 'Acknowledged'
    END AS [Ack Status],
    a.TriggeredDateTime AS [Triggered],
    a.ObjectName AS [Object]
FROM Orion.AlertActive AS a
ORDER BY a.TriggeredDateTime DESC
```

### Volume Status Codes (Orion.Volumes.VolumeStatus)

| Code | Status |
|------|--------|
| 1 | Up |
| 2 | Down |
| 3 | Warning |
| 9 | Unmanaged |
| 14 | Critical |

### Quick Status Filter Patterns

Common filtering patterns used in operational queries:

```sql
-- All devices with problems (not Up and not Unmanaged)
SELECT Caption, IPAddress, Status
FROM Orion.Nodes
WHERE Status NOT IN (1, 9)
ORDER BY Status

-- Only managed devices that are down
SELECT Caption, IPAddress
FROM Orion.Nodes
WHERE Status = 2

-- All critical or down resources across types
SELECT 'Node' AS [Type], Caption AS [Name], Status
FROM Orion.Nodes WHERE Status IN (2, 14)
UNION ALL
SELECT 'Interface', i.Caption, i.Status
FROM Orion.NPM.Interfaces AS i WHERE i.Status IN (2, 14)
UNION ALL
SELECT 'Volume', v.Caption, v.VolumeStatus
FROM Orion.Volumes AS v WHERE v.VolumeStatus IN (2, 14)
```
