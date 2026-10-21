# DPA (Database Performance Analyzer) Entity Schema Reference

---

## Orion.DPA.DpaServer Entity

Central entity representing a monitored SQL Server instance.

### Properties

| Property | Type | Description |
|---|---|---|
| DpaServerId | Int32 | Primary key. Unique identifier. |
| ServerName | String | SQL Server instance name. |
| InstanceName | String | Named instance identifier (e.g., `MSSQL$PROD`). |
| Version | String | SQL Server version (e.g., `2019`, `2022`). |
| Port | Int32 | SQL Server connection port (default 1433). |
| IsMonitored | Boolean | Active monitoring status. |
| LastPoll | DateTime | Timestamp of last metric collection. |
| Status | Int32 | Health status: 1=Up, 2=Down, 3=Warning. |
| CpuUsage | Double | Current CPU utilization %. |
| MemoryUsage | Double | Current memory usage %. |

### Navigation Properties

| Property | Target | Cardinality | Description |
|---|---|---|---|
| Databases | Orion.DPA.Database | 0..* | Monitored databases on this instance. |
| WaitStatistics | Orion.DPA.WaitStat | 0..* | SQL wait event metrics. |
| Metrics | Orion.DPA.Metric | 0..* | Performance metrics collection. |
| Alerts | Orion.ActiveAlerts | 0..* | Active DPA-related alerts. |

### Verbs

| Verb | Parameters | Description |
|---|---|---|
| PollNow | DpaServerId | Trigger immediate metric poll. |
| EnableMonitoring | DpaServerId, Enabled:Boolean | Enable/disable monitoring. |

### Example Queries

**List all monitored SQL Server instances with status:**

```sql
SELECT ServerName, InstanceName, Version, Port, Status, CpuUsage, MemoryUsage
FROM Orion.DPA.DpaServer
WHERE IsMonitored = 1
ORDER BY ServerName
```

**Find down DPA servers:**

```sql
SELECT ServerName, LastPoll, Status
FROM Orion.DPA.DpaServer
WHERE Status = 2
ORDER BY ServerName
```

---

## Orion.DPA.Database Entity

Represents a user database within a monitored SQL Server instance.

### Properties

| Property | Type | Description |
|---|---|---|
| DatabaseId | Int32 | Primary key. |
| DpaServerId | Int32 | FK to Orion.DPA.DpaServer. |
| DatabaseName | String | SQL database name. |
| Status | Int32 | 1=Online, 2=Offline, 3=Suspect. |
| Size | Double | Database size in MB. |
| UsedSpace | Double | Used space in MB. |
| FreeSpace | Double | Available space in MB. |
| LogicalReads | Int64 | Total logical read operations. |
| PhysicalReads | Int64 | Total physical disk reads. |
| PageLifeExpectancy | Int32 | PLE in seconds (target >300). |
| GrowthRate | Double | Recent growth rate in MB/hour. |

### Navigation Properties

| Property | Target | Cardinality | Description |
|---|---|---|---|
| DpaServer | Orion.DPA.DpaServer | 0..1 | Parent SQL Server instance. |
| Tables | Orion.DPA.Table | 0..* | Tables within database. |
| Indexes | Orion.DPA.Index | 0..* | Index objects. |
| BlockingChains | Orion.DPA.BlockingChain | 0..* | Active blocking scenarios. |

### Example Queries

**Databases with fragmentation risk (low PLE):**

```sql
SELECT DatabaseName, PageLifeExpectancy, Size, FreeSpace
FROM Orion.DPA.Database
WHERE PageLifeExpectancy < 300 AND Status = 1
ORDER BY PageLifeExpectancy ASC
```

**Database growth rate analysis:**

```sql
SELECT d.DatabaseName, d.Size, d.GrowthRate, d.DpaServer.ServerName
FROM Orion.DPA.Database d
WHERE d.GrowthRate > 100
ORDER BY d.GrowthRate DESC
```

---

## Orion.DPA.WaitStat Entity

SQL Server wait statistics for diagnostic tuning and bottleneck identification.

### Properties

| Property | Type | Description |
|---|---|---|
| WaitStatId | Int32 | Primary key. |
| DpaServerId | Int32 | FK to instance. |
| WaitType | String | SQL wait type (e.g., `PAGEIOLATCH_SH`, `WRITELOG`). |
| WaitCount | Int64 | Total wait events of this type. |
| WaitTimeMs | Int64 | Total cumulative wait time (milliseconds). |
| SignalWaitTimeMs | Int64 | Time spent signaled but not running. |
| AvgWaitTimeMs | Double | Mean wait duration. |
| Severity | Int32 | Tier: 1=Critical, 2=High, 3=Medium, 4=Low. |

### Example Queries

**Top wait types for a server (tuning focus):**

```sql
SELECT TOP 10 WaitType, WaitCount, WaitTimeMs, AvgWaitTimeMs
FROM Orion.DPA.WaitStat
WHERE WaitType NOT IN ('SLEEP_TASK', 'LAZYWRITER_SLEEP')
ORDER BY WaitTimeMs DESC
```

---

## Orion.DPA.Metric Entity

Time-series performance metrics collection point (single data point in metric stream).

### Properties

| Property | Type | Description |
|---|---|---|
| MetricId | Int32 | Primary key. |
| DpaServerId | Int32 | FK to instance. |
| MetricName | String | Metric identifier (e.g., `CPUUsage`, `PageLifeExpectancy`). |
| MetricValue | Double | Numeric value at collection time. |
| CollectionTime | DateTime | Timestamp of metric sample. |
| Threshold | Double | Configured alert threshold (if any). |
| IsAlert | Boolean | True if metric exceeded threshold. |

### Example Queries

**CPU usage trend for past 24 hours:**

```sql
SELECT MetricValue, CollectionTime
FROM Orion.DPA.Metric
WHERE MetricName = 'CPUUsage' 
  AND CollectionTime >= DATEADD(day, -1, GetDate())
ORDER BY CollectionTime DESC
```

---

## Orion.DPA.BlockingChain Entity

Active or historical SQL blocking events (query X blocked query Y).

### Properties

| Property | Type | Description |
|---|---|---|
| BlockingChainId | Int32 | Primary key. |
| DpaServerId | Int32 | FK to instance. |
| BlockingSpid | Int32 | Session ID of blocking query. |
| BlockedSpid | Int32 | Session ID of blocked query. |
| BlockingQuery | String | T-SQL text of blocker. |
| BlockedQuery | String | T-SQL text of blocked query. |
| BlockDuration | Int32 | Duration of block (seconds). |
| Database | String | Database name where block occurred. |
| DetectedTime | DateTime | When blocking was first detected. |
| ResolvedTime | DateTime | When blocking ended (null if ongoing). |

### Example Queries

**Active blocking chains (long-running):**

```sql
SELECT BlockingSpid, BlockedSpid, BlockDuration, Database, BlockingQuery, BlockedQuery
FROM Orion.DPA.BlockingChain
WHERE ResolvedTime IS NULL AND BlockDuration > 60
ORDER BY BlockDuration DESC
```

