# SWQL NTA (NetFlow Traffic Analyzer) Query Cookbook

## SWQL NTA Queries

### Query: Applications and Service Ports

/* Counts the number of monitored (enabled) application definitions grouped by whether they are single-port or multi-port applications. | Entities: `Orion.Netflow.Applications` */

```sql
SELECT
  CASE
    WHEN Multiport = 0 THEN 'Single-Port'
    ELSE 'Multi-Port'
  END AS [Application Type],
  COUNT(*) AS [Monitoring]
FROM
  Orion.Netflow.Applications
WHERE
  enabled = 1
GROUP BY
  MultiPort
```


---

### Query: CBQoS Sources

/* Lists all Class-Based Quality of Service (CBQoS) sources showing the node, interface, polling engine, enabled status, and last collection time. | Entities: `Orion.Netflow.CBQoSSource` */

```sql
SELECT
  cs.node.Caption AS [Node],
  cs.Interface.Caption AS [Interface],
  cs.node.Engine.ServerName AS [Engine],
  enabled,
  ToLocal(cs.LastTime) AS [Last Time]
FROM
  Orion.Netflow.CBQoSSource cs
```


---

### Query: IP Address Groups

/* Lists all configured IP address groups with their start and end IP ranges and enabled status, used to classify traffic as internal or external. | Entities: `Orion.Netflow.IPAddressGroupRanges` */

```sql
SELECT
  IPAddressGroupName AS [Group Name],
  CONCAT(
    SUBSTRING(ToString(IPRangeStart), 1, 3), '.',
    SUBSTRING(ToString(IPRangeStart), 4, 3), '.',
    SUBSTRING(ToString(IPRangeStart), 7, 3), '.',
    SUBSTRING(ToString(IPRangeStart), 9, 3)
  ) AS [Start],
  CONCAT(
    SUBSTRING(ToString(IPRangeEnd), 1, 3), '.',
    SUBSTRING(ToString(IPRangeEnd), 4, 3), '.',
    SUBSTRING(ToString(IPRangeEnd), 7, 3), '.',
    SUBSTRING(ToString(IPRangeEnd), 9, 3)
  ) AS [End],
  Enabled
FROM
  Orion.Netflow.IPAddressGroupRanges
```


---

### Query: NBAR2 Enabled Nodes

/* Identifies nodes actively sending NBAR2 (Network-Based Application Recognition) flow data today, showing unique interface count and total flow records per node. | Entities: `Orion.Netflow.Flows` */

```sql
SELECT
  f.node.DisplayName AS [Node],
  COUNT(DISTINCT f.IngressInterface.DisplayName) AS UniqueInterfaces,
  COUNT(*) AS TotalRecords
FROM
  Orion.Netflow.Flows f
WHERE
  f.AdvancedApplicationID > 0
  AND ISNULL(f.AdvancedApplication.Name, '') != ''
  AND DAYDIFF(f.ObservationTimestamp, GETUTCDATE()) = 0
GROUP BY
  f.node.DisplayName
ORDER BY
  TotalRecords DESC
```


---

### Query: NetFlow Sources by Node

/* Counts the number of enabled NetFlow source interfaces per node, sorted by interface count descending to highlight the most instrumented nodes. | Entities: `Orion.Netflow.Source` */

```sql
SELECT
  f.Node.Caption AS [Node Caption],
  COUNT(f.Interface.Caption) AS [Interface Count]
FROM
  Orion.Netflow.Source AS f
WHERE
  f.Enabled = TRUE
GROUP BY
  f.Node.Caption
ORDER BY
  [Interface Count] DESC
```


---

### Query: NTA Flow Engine Statistics

/* Retrieves flows-per-second statistics for each polling engine across three time windows (5 minutes, 24 hours, 3 days), showing the current flow ingestion rate. | Entities: `Orion.Netflow.FlowEngines`, `Orion.Netflow.NetFlowEnginesStatistics` */

```sql
SELECT
  e.Engine.ServerName AS [Polling Engine],
  CASE
    WHEN s.StatisticsName = 'FlowsPerSecondForLast24Hours' THEN 'Last 24 Hours'
    WHEN s.StatisticsName = 'FlowsPerSecondForLast3Days' THEN 'Last 3 Days'
    WHEN s.StatisticsName = 'FlowsPerSecondForLast5Minutes' THEN 'Last 5 Minutes'
    ELSE s.StatisticsName
  END AS [Statistic Time Period],
  s.StatisticsValue AS [Flows per Second]
FROM
  Orion.Netflow.FlowEngines AS e
  JOIN Orion.Netflow.NetFlowEnginesStatistics AS s ON s.EngineID = e.EngineID
WHERE
  s.StatisticsName IN (
    'FlowsPerSecondForLast24Hours',
    'FlowsPerSecondForLast3Days',
    'FlowsPerSecondForLast5Minutes'
  )
ORDER BY
  [Polling Engine],
  [Statistic Time Period]
```


---

### Query: NTA Active Interface Sources Count

/* Returns a single count of all enabled (active) NetFlow interface sources across the environment. | Entities: `Orion.Netflow.Source` */

```sql
SELECT
  COUNT(InterfaceID) AS [Active Interface Sources]
FROM
  Orion.Netflow.Source
WHERE
  enabled = '1'
```


---

### Query: NTA NBAR Flows by Node and Interface

/* Counts NBAR-classified flow records per node and interface for the current day, providing granular visibility into which interfaces are generating NBAR2 data. | Entities: `Orion.Netflow.Flows` */

```sql
SELECT
  f.node.DisplayName AS [Node],
  f.IngressInterface.DisplayName AS [Interface],
  COUNT(*) AS [Number of Flows]
FROM
  Orion.Netflow.Flows AS f
WHERE
  f.AdvancedApplicationID > 0
  AND ISNULL(f.AdvancedApplication.Name, '') != ''
  AND DAYDIFF(f.ObservationTimestamp, GETUTCDATE()) = 0
GROUP BY
  f.node.DisplayName,
  f.IngressInterface.DisplayName
ORDER BY
  [Node],
  [Interface]
```


---

### Query: NTA Node Sources Count

/* Returns a count of all NetFlow node sources that have a non-empty caption, indicating they are properly named and trackable. | Entities: `Orion.Netflow.NodeSources` */

```sql
SELECT
  COUNT(ns.Node.Caption) AS [Count of Node Sources]
FROM
  Orion.Netflow.NodeSources AS ns
WHERE
  ns.Node.Caption IS NOT NULL
  AND ns.Node.Caption != ''
```


---

### Query: Protocols Enabled vs Disabled

/* Counts the number of enabled and disabled protocol definitions in NTA. | Entities: `Orion.Netflow.Protocols` */

```sql
SELECT
  Enabled,
  COUNT(*) AS [Count]
FROM
  Orion.Netflow.Protocols
GROUP BY
  Enabled
```


---

### Query: Unmonitored Application Ports

/* Counts the number of application definitions that are currently disabled (not being monitored). | Entities: `Orion.Netflow.Applications` */

```sql
SELECT
  COUNT(ApplicationID) AS [Unmonitored Ports]
FROM
  Orion.Netflow.Applications
WHERE
  enabled = 'false'
```


---

### Query: Charting and Graphs Settings (Work-in-Progress)

/* Intended to retrieve NTA charting and graph display settings. | Entities: TBD */

```sql
-- TODO find the table with this setting.
```


---

### Query: DNS and NetBIOS Resolution (Work-in-Progress)

/* Intended to check whether NetBIOS resolution is disabled (recommended best practice). | Entities: TBD */

```sql
-- NetBIOS Resolution should be disabled.
-- TODO Find the setting
```


---

### Query: Retention Settings (Work-in-Progress)

/* Intended to retrieve NTA data retention settings controlling how long flow data is kept. | Entities: TBD */

```sql
-- TODO
```


---

### Query: Top Talkers Settings (Work-in-Progress)

/* Intended to retrieve NTA Top Talkers display and threshold settings. | Entities: TBD */

```sql
-- TODO
```

**Key points**: **WIP** -- This query is under development. Top Talkers settings configure how many top sources/destinations are tracked and displayed.



