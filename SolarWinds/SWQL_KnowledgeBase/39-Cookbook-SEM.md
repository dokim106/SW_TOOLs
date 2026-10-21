# SEM Query Cookbook

---

## Query: Monitored Nodes Risk Summary

/* Dashboard: SEM-monitored nodes with risk ranking and security posture. */

```sql
SELECT
    Node.Caption,
    AgentVersion,
    IsConnected AS 'Connected',
    CASE IsConnected WHEN 1 THEN 'OK' ELSE 'ALERT' END AS 'Agent Status',
    RiskScore,
    ThreatLevel,
    EventsForwarded,
    LastHeartbeat
FROM Orion.SEM.Nodes
ORDER BY RiskScore DESC
```

---

## Query: Disconnected/Offline SEM Agents (Coverage Gap Detection)

/* Identify monitoring blindspots: agents not reporting = security risks. */

```sql
SELECT
    Node.Caption,
    Node.IPAddress,
    LastHeartbeat,
    DATEDIFF(hour, LastHeartbeat, GetDate()) AS 'Hours Offline',
    AgentVersion,
    IsConnected
FROM Orion.SEM.Nodes
WHERE IsConnected = 0
    OR LastHeartbeat < DATEADD(day, -1, GetDate())
ORDER BY LastHeartbeat ASC
```

---

## Query: Critical & High-Severity Events (Past 7 Days)

/* Real-time security posture; isolate actionable threats requiring immediate response. */

```sql
SELECT TOP 500
    EventTime,
    Node.Caption,
    EventType,
    CASE Severity WHEN 1 THEN 'CRITICAL' WHEN 2 THEN 'HIGH' ELSE 'MEDIUM' END AS 'Severity',
    User,
    IpAddress,
    Message,
    CASE IsAnomalous WHEN 1 THEN 'ANOMALY' ELSE 'Normal' END AS 'Anomaly Flag'
FROM Orion.SEM.Events
WHERE Severity <= 2 AND EventTime >= DATEADD(day, -7, GetDate())
ORDER BY EventTime DESC
```

---

## Query: Events by Type Distribution (Threat Landscape)

/* Understand attack surface; shows where threats concentrate (login attacks, file access, etc.). */

```sql
SELECT
    EventType,
    COUNT(*) AS 'Event Count',
    MAX(Severity) AS 'Highest Severity',
    COUNT(DISTINCT Node.Caption) AS 'Affected Nodes',
    MIN(EventTime) AS 'Oldest Event',
    MAX(EventTime) AS 'Most Recent'
FROM Orion.SEM.Events
WHERE EventTime >= DATEADD(day, -30, GetDate())
GROUP BY EventType
ORDER BY 'Event Count' DESC
```

---

## Query: User Risk Profiling (Suspicious Account Activity)

/* Identify risky user behaviors; anomalies, failed login storms, privilege escalations. */

```sql
SELECT
    User,
    COUNT(*) AS 'Event Count',
    COUNT(DISTINCT CASE WHEN IsAnomalous = 1 THEN 1 END) AS 'Anomalous Events',
    MIN(Severity) AS 'Worst Severity',
    COUNT(DISTINCT Node.Caption) AS 'Nodes Accessed',
    MAX(EventTime) AS 'Last Activity'
FROM Orion.SEM.Events
WHERE EventTime >= DATEADD(day, -30, GetDate())
GROUP BY User
HAVING COUNT(*) > 50 OR COUNT(DISTINCT CASE WHEN IsAnomalous = 1 THEN 1 END) > 0
ORDER BY 'Anomalous Events' DESC, 'Event Count' DESC
```

---

## Query: Alert Rule Performance (Effectiveness & Alerting Load)

/* Measure alert rule quality; high-firing rules risk fatigue; low-firing rules may be ineffective. */

```sql
SELECT
    RuleName,
    CASE Enabled WHEN 1 THEN 'Active' ELSE 'Inactive' END AS 'Status',
    RuleType,
    TriggerCount AS 'Total Fires',
    ROUND(TriggerCount / (DATEDIFF(day, CreatedDate, GetDate()) + 1.0), 2) AS 'Fires/Day',
    LastTriggered,
    Threshold,
    'Window ' + CAST([Window] AS VARCHAR) + ' min' AS 'Rule Window'
FROM Orion.SEM.AlertRule
ORDER BY TriggerCount DESC
```

---

## Query: Open and In-Progress Incidents (Incident Management)

/* Tactical view of active security incidents requiring investigation or remediation. */

```sql
SELECT
    IncidentName,
    Status,
    CASE Severity WHEN 1 THEN 'CRITICAL' WHEN 2 THEN 'HIGH' WHEN 3 THEN 'MEDIUM' ELSE 'LOW' END AS 'Severity',
    StartTime,
    DATEDIFF(day, StartTime, GetDate()) AS 'Days Open',
    EventCount,
    AffectedNodes,
    AssignedTo,
    Description
FROM Orion.SEM.Incident
WHERE Status IN ('Open', 'Investigating')
ORDER BY Severity ASC, StartTime ASC
```

---

## Query: Incident Timeline & Metrics (Forensics & Trend Analysis)

/* Incident duration, scope, and resolution patterns; supports post-incident review and metrics. */

```sql
SELECT
    IncidentName,
    Severity,
    DATEDIFF(day, StartTime, IsNull(EndTime, GetDate())) AS 'Duration Days',
    EventCount,
    AffectedNodes,
    Status,
    CASE
        WHEN EndTime IS NULL THEN 'Open'
        ELSE 'Resolved ' + CAST(DATEDIFF(day, StartTime, EndTime) AS VARCHAR) + 'd'
    END AS 'Resolution Status'
FROM Orion.SEM.Incident
WHERE StartTime >= DATEADD(month, -3, GetDate())
ORDER BY StartTime DESC
```

---

## Query: Event Source Breakdown (Log & Sensor Health)

**Purpose**: Verify data collection from all expected sources; detect collection failures or gaps.

```sql
SELECT
    Source,
    COUNT(*) AS 'Total Events',
    COUNT(DISTINCT Node.Caption) AS 'Sending Nodes',
    MAX(Severity) AS 'Most Severe Event',
    MIN(EventTime) AS 'Earliest Event',
    MAX(EventTime) AS 'Latest Event',
    DATEDIFF(hour, MAX(EventTime), GetDate()) AS 'Hours Since Last Event'
FROM Orion.SEM.Events
WHERE EventTime >= DATEADD(day, -7, GetDate())
GROUP BY Source
ORDER BY 'Total Events' DESC
```



