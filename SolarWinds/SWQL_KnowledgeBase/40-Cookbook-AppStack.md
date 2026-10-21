# AppStack Query Cookbook

---

## Query: Critical Applications Health Dashboard

/* Executive view: business-critical apps with health/operational risk visibility. */

```sql
SELECT
    ApplicationName,
    ApplicationType,
    CriticityLevel,
    CASE Status WHEN 1 THEN 'Healthy' WHEN 2 THEN 'Warning' WHEN 3 THEN 'Critical' ELSE 'Unknown' END AS 'Status',
    HealthScore,
    Owner,
    Department,
    LastAssessment
FROM Orion.AppStack.Application
WHERE CriticityLevel <= 2
ORDER BY HealthScore ASC, ApplicationName
```

---

## Query: Application Topology Completeness (Discovery Validation)

/* Verify each app has expected components/dependencies mapped; identify topology gaps. */

```sql
SELECT
    ApplicationName,
    COUNT(DISTINCT CASE WHEN Components.Status = 1 THEN Components.ComponentId END) AS 'Healthy Components',
    COUNT(DISTINCT Components.ComponentId) AS 'Total Components',
    COUNT(DISTINCT Dependencies.DependencyId) AS 'Dependencies Mapped',
    DATEDIFF(day, LastAssessment, GetDate()) AS 'Days Since Scan'
FROM Orion.AppStack.Application
LEFT JOIN Orion.AppStack.ApplicationComponent AS Components ON (Components.ApplicationId = ApplicationId)
LEFT JOIN Orion.AppStack.ServiceDependency AS Dependencies 
    ON (Dependencies.SourceComponentId = Components.ComponentId)
WHERE HealthScore IS NOT NULL
GROUP BY ApplicationName, LastAssessment
ORDER BY 'Days Since Scan' DESC
```

---

## Query: Component Health Drill-Down (Tier-Level Performance)

/* Identify which tier (web, app, db) is degraded; guides troubleshooting for multi-tier apps. */

```sql
SELECT
    Application.ApplicationName,
    ComponentType,
    COUNT(*) AS 'Component Count',
    ROUND(AVG(HealthScore), 1) AS 'Avg Health',
    ROUND(MAX(ResponseTime), 0) AS 'Worst Response (ms)',
    ROUND(AVG(Throughput), 1) AS 'Avg Throughput (req/s)',
    ROUND(MAX(ErrorRate), 2) AS 'Peak Error %'
FROM Orion.AppStack.ApplicationComponent
WHERE Status != 9
GROUP BY Application.ApplicationName, ComponentType
ORDER BY Application.ApplicationName, 'Avg Health' ASC
```

---

## Query: Unhealthy & Failing Dependencies (Availability Risk)

/* Pinpoint broken or degraded service calls; direct root-cause for application failures. */

```sql
SELECT
    SourceComponent.Application.ApplicationName AS 'Source App',
    SourceComponent.ComponentName AS 'Caller',
    TargetComponent.Application.ApplicationName AS 'Target App',
    TargetComponent.ComponentName AS 'Called Service',
    DependencyType,
    CallCount,
    ROUND(AvgLatency, 2) AS 'Avg Latency (ms)',
    ROUND(FailureRate, 2) AS 'Failure %',
    CASE IsHealthy WHEN 0 THEN 'UNHEALTHY' ELSE 'OK' END AS 'Status'
FROM Orion.AppStack.ServiceDependency
WHERE IsHealthy = 0 OR FailureRate > 1.0
ORDER BY FailureRate DESC, AvgLatency DESC
```

---

## Query: Application Response Time SLA Tracking

/* Monitor SLA compliance; track whether applications meet contractual response time targets. */

```sql
SELECT
    Application.ApplicationName,
    Application.CriticityLevel,
    ROUND(AVG(ComponentResponseTime.ResponseTime), 1) AS 'Avg Response (ms)',
    ROUND(MAX(ComponentResponseTime.ResponseTime), 1) AS 'Peak Response (ms)',
    ROUND(MIN(ComponentResponseTime.ResponseTime), 1) AS 'Best Response (ms)',
    COUNT(DISTINCT ComponentResponseTime.ComponentId) AS 'Component Count',
    CASE
        WHEN AVG(ComponentResponseTime.ResponseTime) > 1000 THEN 'SLA MISS'
        WHEN AVG(ComponentResponseTime.ResponseTime) > 500 THEN 'AT RISK'
        ELSE 'COMPLIANT'
    END AS 'SLA Status'
FROM Orion.AppStack.Application
JOIN Orion.AppStack.ApplicationComponent AS ComponentResponseTime 
    ON (ComponentResponseTime.ApplicationId = Application.ApplicationId)
WHERE ComponentResponseTime.Status = 1
GROUP BY Application.ApplicationName, Application.CriticityLevel
ORDER BY 'Avg Response (ms)' DESC
```

---

## Query: Components Hosting Locations (Infrastructure Mapping)

/* Inventory what runs where; critical for change management, capacity planning, and disaster recovery. */

```sql
SELECT
    HostNode.Caption,
    HostNode.IPAddress,
    ComponentType,
    COUNT(DISTINCT ComponentId) AS 'Component Count',
    COUNT(DISTINCT Application.ApplicationId) AS 'Applications Served',
    ROUND(AVG(HealthScore), 1) AS 'Avg Health'
FROM Orion.AppStack.ApplicationComponent
JOIN Orion.Nodes AS HostNode ON (HostNode.NodeID = (
    SELECT NodeID FROM Orion.Nodes WHERE Caption = HostedOn LIMIT 1
))
JOIN Orion.AppStack.Application ON (Application.ApplicationId = ApplicationId)
WHERE Status = 1
GROUP BY HostNode.Caption, HostNode.IPAddress, ComponentType
ORDER BY HostNode.Caption, ComponentType
```

---

## Query: Error Rate by Tier (Quality Risk)

/* Identify which tier is introducing errors; indicates configuration, resource, or code issues. */

```sql
SELECT
    Application.ApplicationName,
    ComponentType,
    COUNT(*) AS 'Component Count',
    ROUND(AVG(ErrorRate), 2) AS 'Avg Error %',
    ROUND(MAX(ErrorRate), 2) AS 'Worst Error %',
    CASE
        WHEN AVG(ErrorRate) > 5 THEN 'CRITICAL'
        WHEN AVG(ErrorRate) > 1 THEN 'HIGH'
        WHEN AVG(ErrorRate) > 0 THEN 'MEDIUM'
        ELSE 'HEALTHY'
    END AS 'Error Status'
FROM Orion.AppStack.ApplicationComponent
WHERE Status = 1 AND ErrorRate IS NOT NULL
GROUP BY Application.ApplicationName, ComponentType
HAVING AVG(ErrorRate) > 0
ORDER BY 'Avg Error %' DESC
```

---

## Query: Metrics Anomaly Trend (ML-Detected Issues)

/* Surface anomalies detected by machine learning; early warning system for emerging problems. */

```sql
SELECT
    Component.ComponentName,
    Component.Application.ApplicationName,
    MetricType,
    COUNT(*) AS 'Anomaly Count',
    ROUND(AVG(MetricValue), 2) AS 'Avg Anomalous Value',
    MIN(CollectionTime) AS 'First Anomaly',
    MAX(CollectionTime) AS 'Most Recent',
    DATEDIFF(day, MIN(CollectionTime), MAX(CollectionTime)) AS 'Days Detected'
FROM Orion.AppStack.Metric
WHERE IsAnomaly = 1
GROUP BY Component.ComponentName, Component.Application.ApplicationName, MetricType
ORDER BY MAX(CollectionTime) DESC
```

---

## Query: Dependency Health Chain for Critical App (Critical Path Analysis)

/* Trace all dependencies for a critical application; identify single points of failure. */

```sql
WITH RECURSIVE DependencyChain AS (
    SELECT
        1 AS 'Depth',
        SourceComponent.Component.ApplicationName,
        SourceComponent.ComponentName AS 'Source',
        TargetComponent.ComponentName AS 'Target',
        TargetComponent.Application.ApplicationName AS 'TargetApp',
        DependencyType,
        IsHealthy,
        FailureRate,
        AvgLatency
    FROM Orion.AppStack.ServiceDependency
    WHERE SourceComponent.Application.ApplicationName = 'OrderProcessingApp'

    UNION ALL

    SELECT
        dc.Depth + 1,
        dep.SourceComponent.Application.ApplicationName,
        dep.SourceComponent.ComponentName,
        dep.TargetComponent.ComponentName,
        dep.TargetComponent.Application.ApplicationName,
        dep.DependencyType,
        dep.IsHealthy,
        dep.FailureRate,
        dep.AvgLatency
    FROM Orion.AppStack.ServiceDependency dep
    JOIN DependencyChain dc ON dep.SourceComponent.ComponentId = (
        SELECT ComponentId FROM Orion.AppStack.ApplicationComponent 
        WHERE ComponentName = dc.Target
    )
    WHERE dc.Depth < 5
)
SELECT * FROM DependencyChain
ORDER BY Depth, Source, Target
```



