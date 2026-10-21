# SEM (Security Event Manager) Entity Schema Reference

---

## Orion.SEM.Nodes Entity

Monitored nodes sending security events to SEM.

### Properties

| Property | Type | Description |
|---|---|---|
| SemNodeId | Int32 | Primary key. |
| NodeId | Int32 | FK to Orion.Nodes. |
| AgentVersion | String | SEM agent version installed. |
| LastHeartbeat | DateTime | Last communication timestamp. |
| IsConnected | Boolean | Current connection status. |
| EventsForwarded | Int64 | Cumulative event count. |
| RiskScore | Int32 | Aggregated security risk (0-100). |
| ThreatLevel | String | 'Critical', 'High', 'Medium', 'Low', 'Info'. |
| Status | Int32 | 1=Active, 2=Disconnected, 3=Error. |

### Navigation Properties

| Property | Target | Cardinality | Description |
|---|---|---|---|
| Node | Orion.Nodes | 0..1 | Parent node in Orion inventory. |
| Events | Orion.SEM.Events | 0..* | Security events from this node. |
| Alerts | Orion.SEM.AlertRule | 0..* | Alerts triggered on this node. |
| Incidents | Orion.SEM.Incident | 0..* | Consolidated security incidents. |

### Example Queries

**Nodes with high security risk:**

```sql
SELECT Node.Caption, RiskScore, ThreatLevel, LastHeartbeat, IsConnected
FROM Orion.SEM.Nodes
WHERE RiskScore > 75
ORDER BY RiskScore DESC
```

**Disconnected SEM agents:**

```sql
SELECT Node.Caption, LastHeartbeat, AgentVersion
FROM Orion.SEM.Nodes
WHERE IsConnected = 0
ORDER BY LastHeartbeat DESC
```

---

## Orion.SEM.Events Entity

Individual security events collected from monitored systems (logs, syslog, SNMP traps).

### Properties

| Property | Type | Description |
|---|---|---|
| EventId | Int64 | Primary key. Unique event identifier. |
| SemNodeId | Int32 | FK to Orion.SEM.Nodes. |
| EventTime | DateTime | When event occurred on source system. |
| ReceivedTime | DateTime | When event received by SEM. |
| EventType | String | Category: 'Login', 'FileAccess', 'ProcessExecution', 'Privilege', 'ConfigChange'. |
| Severity | Int32 | 1=Critical, 2=High, 3=Medium, 4=Low, 5=Info. |
| Source | String | Event origin (e.g., Windows Event Log, syslog, netflow). |
| Message | String | Event description/log entry text. |
| User | String | User account associated with event. |
| IpAddress | String | Source or target IP address. |
| IsAnomalous | Boolean | Flagged as anomaly by ML engine. |
| IncidentId | Int32 | FK to Orion.SEM.Incident (if grouped). |

### Example Queries

**Critical security events in past 24 hours:**

```sql
SELECT TOP 100 EventTime, Node.Caption, EventType, Severity, User, Message
FROM Orion.SEM.Events
WHERE Severity <= 2 AND EventTime >= DATEADD(day, -1, GetDate())
ORDER BY EventTime DESC
```

**Anomalous events by user:**

```sql
SELECT User, COUNT(*) AS AnomalousCount, MAX(EventTime) AS LastEvent
FROM Orion.SEM.Events
WHERE IsAnomalous = 1
GROUP BY User
ORDER BY AnomalousCount DESC
```

**Events by source type:**

```sql
SELECT Source, EventType, COUNT(*) AS EventCount, MAX(Severity) AS HighestSeverity
FROM Orion.SEM.Events
WHERE ReceivedTime >= DATEADD(day, -7, GetDate())
GROUP BY Source, EventType
ORDER BY EventCount DESC
```

---

## Orion.SEM.AlertRule Entity

Configured alert rules that trigger on event patterns or thresholds.

### Properties

| Property | Type | Description |
|---|---|---|
| AlertRuleId | Int32 | Primary key. |
| RuleName | String | User-friendly rule identifier. |
| RuleType | String | 'EventCount', 'EventContent', 'RiskScore', 'Behavior'. |
| Enabled | Boolean | Rule is active and monitoring. |
| Condition | String | Rule logic (e.g., `EventType='Login' AND Severity=1`). |
| Threshold | Int32 | Alert triggers when metric exceeds this. |
| Window | Int32 | Time window in minutes for aggregation. |
| NotifyUsers | String | Comma-separated email list or distribution group. |
| LastTriggered | DateTime | Timestamp of most recent alert firing. |
| TriggerCount | Int32 | Cumulative alert fires. |

### Example Queries

**Active alert rules with trigger counts:**

```sql
SELECT RuleName, RuleType, Condition, Threshold, TriggerCount, LastTriggered
FROM Orion.SEM.AlertRule
WHERE Enabled = 1
ORDER BY TriggerCount DESC
```

---

## Orion.SEM.Incident Entity

Grouped/correlated security events representing a potential breach or incident.

### Properties

| Property | Type | Description |
|---|---|---|
| IncidentId | Int32 | Primary key. |
| IncidentName | String | Auto-generated or manual incident title. |
| Status | String | 'Open', 'Investigating', 'Resolved', 'Closed'. |
| Severity | Int32 | 1=Critical, 2=High, 3=Medium, 4=Low. |
| StartTime | DateTime | First event in incident timeline. |
| EndTime | DateTime | Incident closure timestamp (null if open). |
| EventCount | Int32 | Number of events in incident. |
| AffectedNodes | Int32 | Count of unique nodes involved. |
| AssignedTo | String | Incident owner/analyst. |
| Description | String | Incident summary/notes. |

### Navigation Properties

| Property | Target | Cardinality | Description |
|---|---|---|---|
| Events | Orion.SEM.Events | 0..* | Events grouped in this incident. |
| AffectedAssets | Orion.Nodes | 0..* | Nodes impacted. |

### Example Queries

**Open critical incidents:**

```sql
SELECT IncidentName, Status, Severity, StartTime, EventCount, AffectedNodes, AssignedTo, Description
FROM Orion.SEM.Incident
WHERE Status IN ('Open', 'Investigating') AND Severity <= 2
ORDER BY StartTime DESC
```

**Incident timeline dashboard:**

```sql
SELECT 
    IncidentName, 
    Severity, 
    EventCount, 
    DATEDIFF(hour, StartTime, IsNull(EndTime, GetDate())) AS DurationHours,
    AffectedNodes,
    Status
FROM Orion.SEM.Incident
WHERE StartTime >= DATEADD(day, -30, GetDate())
ORDER BY StartTime DESC
```

