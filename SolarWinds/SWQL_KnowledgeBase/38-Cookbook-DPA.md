# DPA Query Cookbook

---

## Query: DPA Server Inventory with Health Status

/* Comprehensive inventory of all monitored SQL Server instances with health/resource utilization. */

```sql
SELECT
    ServerName,
    InstanceName,
    Version,
    Port,
    IsMonitored,
    CASE Status WHEN 1 THEN 'Up' WHEN 2 THEN 'Down' ELSE 'Warning' END AS Status,
    CpuUsage AS 'CPU %',
    MemoryUsage AS 'Memory %',
    LastPoll,
    DATEDIFF(minute, LastPoll, GetDate()) AS 'Minutes Since Poll'
FROM Orion.DPA.DpaServer
ORDER BY ServerName
```

---

## Query: Database Space Utilization & Growth Forecast

/* Identify databases near capacity; project run-out time based on growth rate. */

```sql
SELECT
    DpaServer.ServerName,
    DatabaseName,
    ROUND(Size, 2) AS 'Size (MB)',
    ROUND(UsedSpace, 2) AS 'Used (MB)',
    ROUND(FreeSpace, 2) AS 'Free (MB)',
    ROUND(100.0 * UsedSpace / Size, 1) AS 'Used %',
    ROUND(GrowthRate, 2) AS 'Growth (MB/hr)',
    CASE
        WHEN GrowthRate > 0 THEN ROUND(FreeSpace / GrowthRate / 24, 1)
        ELSE NULL
    END AS 'Days to Full'
FROM Orion.DPA.Database
WHERE Status = 1
ORDER BY 'Used %' DESC
```

---

## Query: Page Life Expectancy (PLE) Health Check

/* Monitor memory pressure via PLE; low values indicate buffer pool pressure and increased disk I/O. */

```sql
SELECT
    DpaServer.ServerName,
    DatabaseName,
    PageLifeExpectancy,
    CASE
        WHEN PageLifeExpectancy >= 300 THEN 'Healthy'
        WHEN PageLifeExpectancy >= 100 THEN 'Caution'
        ELSE 'Critical'
    END AS 'PLE Status'
FROM Orion.DPA.Database
WHERE Status = 1
ORDER BY PageLifeExpectancy ASC
```

---

## Query: Top Wait Types by Duration (Query Performance Tuning)

/* Identify which wait events consume the most time; guides where to focus tuning efforts. */

```sql
SELECT TOP 15
    DpaServer.ServerName,
    WaitType,
    WaitCount,
    ROUND(WaitTimeMs / 1000.0 / 60, 2) AS 'Total Wait (min)',
    ROUND(AvgWaitTimeMs, 2) AS 'Avg Wait (ms)',
    CASE
        WHEN Severity = 1 THEN 'Critical'
        WHEN Severity = 2 THEN 'High'
        WHEN Severity = 3 THEN 'Medium'
        ELSE 'Low'
    END AS 'Severity'
FROM Orion.DPA.WaitStat
WHERE WaitType NOT IN ('SLEEP_TASK', 'LAZYWRITER_SLEEP', 'QDS_CLEANUP_STALE_QUERIES')
ORDER BY WaitTimeMs DESC
```

---

## Query: Active Blocking Chains (Deadlock & Contention Diagnosis)

/* Identify queries blocking others; critical for incident response and performance bottleneck root-cause analysis. */

```sql
SELECT
    DpaServer.ServerName,
    Database AS 'Database',
    BlockingSpid AS 'Blocker SPID',
    BlockedSpid AS 'Blocked SPID',
    BlockDuration AS 'Duration (sec)',
    BlockingQuery AS 'Blocking Query Text',
    BlockedQuery AS 'Blocked Query Text'
FROM Orion.DPA.BlockingChain
WHERE ResolvedTime IS NULL
ORDER BY BlockDuration DESC
```

---

## Query: Database Metrics Timeline (Performance Trending)

/* Track CPU and memory trends over time for capacity planning and anomaly detection. */

```sql
SELECT
    DpaServer.ServerName,
    MetricName,
    ROUND(AVG(MetricValue), 2) AS 'Avg Value',
    ROUND(MAX(MetricValue), 2) AS 'Peak Value',
    ROUND(MIN(MetricValue), 2) AS 'Low Value',
    COUNT(*) AS 'Sample Count'
FROM Orion.DPA.Metric
WHERE MetricName IN ('CPUUsage', 'MemoryUsage')
  AND CollectionTime >= DATEADD(day, -7, GetDate())
GROUP BY DpaServer.ServerName, MetricName
ORDER BY DpaServer.ServerName, MetricName
```

---

## Query: Servers Not Polled in 24 Hours (Availability Alert)

/* Detect monitoring gaps; critical for SLA compliance and incident detection. */

```sql
SELECT
    ServerName,
    InstanceName,
    LastPoll,
    DATEDIFF(hour, LastPoll, GetDate()) AS 'Hours Since Poll',
    Status,
    IsMonitored
FROM Orion.DPA.DpaServer
WHERE LastPoll < DATEADD(day, -1, GetDate())
    OR IsMonitored = 0
ORDER BY LastPoll ASC, ServerName
```

---

## Query: Database Table Bloat & Index Fragmentation Summary

/* Identify space-wasting fragmentation; actionable for maintenance planning (REBUILD vs. REORGANIZE). */

```sql
SELECT
    d.DpaServer.ServerName,
    d.DatabaseName,
    COUNT(DISTINCT t.TableId) AS 'Fragmented Tables',
    ROUND(AVG(idx.FragmentationPercent), 1) AS 'Avg Index Fragmentation %'
FROM Orion.DPA.Database d
LEFT JOIN Orion.DPA.Table t ON d.DatabaseId = t.DatabaseId
LEFT JOIN Orion.DPA.Index idx ON t.TableId = idx.TableId
WHERE d.Status = 1 AND idx.FragmentationPercent > 10
GROUP BY d.DpaServer.ServerName, d.DatabaseName
ORDER BY 'Avg Index Fragmentation %' DESC
```



