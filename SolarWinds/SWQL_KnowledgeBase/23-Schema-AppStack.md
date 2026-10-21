# AppStack Entity Schema Reference

---

## Orion.AppStack.Application Entity

Represents a business application or service monitored via AppStack topology discovery.

### Properties

| Property | Type | Description |
|---|---|---|
| ApplicationId | Int32 | Primary key. |
| ApplicationName | String | Application display name. |
| ApplicationType | String | 'WebApplication', 'DatabaseService', 'MiddleWare', 'Custom'. |
| Owner | String | Business owner or team responsible. |
| Department | String | Owning department. |
| CriticityLevel | Int32 | 1=Critical, 2=High, 3=Medium, 4=Low. |
| Status | Int32 | 1=Healthy, 2=Warning, 3=Critical, 9=Unknown. |
| HealthScore | Double | Composite health 0-100. |
| LastAssessment | DateTime | Last dependency/topology scan. |
| IpAddress | String | Primary service IP or virtual endpoint. |
| Port | Int32 | Primary service port. |
| DiscoveryMethod | String | 'SNMP', 'Agent', 'WMI', 'Flow', 'Manual'. |

### Navigation Properties

| Property | Target | Cardinality | Description |
|---|---|---|---|
| Components | Orion.AppStack.ApplicationComponent | 0..* | Software/service components. |
| Dependencies | Orion.AppStack.ServiceDependency | 0..* | Upstream/downstream apps. |
| Nodes | Orion.Nodes | 0..* | Infrastructure hosting app. |
| Alerts | Orion.ActiveAlerts | 0..* | Active alerts for app. |
| MetricsHistory | Orion.AppStack.Metric | 0..* | Performance history. |

### Example Queries

**Critical applications with health score:**

```sql
SELECT ApplicationName, CriticityLevel, HealthScore, Status, LastAssessment
FROM Orion.AppStack.Application
WHERE CriticityLevel <= 2 AND Status != 1
ORDER BY HealthScore ASC
```

**Applications by owner/department:**

```sql
SELECT Department, Owner, ApplicationName, CriticityLevel, HealthScore
FROM Orion.AppStack.Application
ORDER BY Department, Owner, ApplicationName
```

---

## Orion.AppStack.ApplicationComponent Entity

Individual software component or microservice within an application.

### Properties

| Property | Type | Description |
|---|---|---|
| ComponentId | Int32 | Primary key. |
| ApplicationId | Int32 | FK to Orion.AppStack.Application. |
| ComponentName | String | Component identifier (e.g., 'WebTier', 'SQLServer', 'Cache'). |
| ComponentType | String | 'WebServer', 'ApplicationServer', 'Database', 'Cache', 'MessageQueue', 'Custom'. |
| Status | Int32 | 1=Up, 2=Down, 3=Degraded, 9=Unknown. |
| HostedOn | String | Node hostname or virtual instance name. |
| Port | Int32 | Listening port (if applicable). |
| Version | String | Software version or build number. |
| HealthScore | Double | Component-level health 0-100. |
| ResponseTime | Int32 | Avg response time (ms) for this tier. |
| Throughput | Double | Requests/transactions per second. |
| ErrorRate | Double | % of failed requests. |

### Navigation Properties

| Property | Target | Cardinality | Description |
|---|---|---|---|
| Application | Orion.AppStack.Application | 0..1 | Parent application. |
| HostNode | Orion.Nodes | 0..1 | Infrastructure node. |
| Dependencies | Orion.AppStack.ServiceDependency | 0..* | Direct dependencies. |

### Example Queries

**Component health drill-down:**

```sql
SELECT 
    Application.ApplicationName,
    ComponentName, 
    ComponentType, 
    Status, 
    HealthScore, 
    ResponseTime, 
    ErrorRate
FROM Orion.AppStack.ApplicationComponent
WHERE HealthScore < 80
ORDER BY HealthScore ASC
```

**Response time by tier:**

```sql
SELECT ComponentType, AVG(ResponseTime) AS AvgResponseMs, MAX(ResponseTime) AS PeakResponseMs
FROM Orion.AppStack.ApplicationComponent
WHERE Status = 1
GROUP BY ComponentType
ORDER BY AvgResponseMs DESC
```

---

## Orion.AppStack.ServiceDependency Entity

Directed link between application components or external services (who calls whom).

### Properties

| Property | Type | Description |
|---|---|---|
| DependencyId | Int32 | Primary key. |
| SourceComponentId | Int32 | FK to calling component. |
| TargetComponentId | Int32 | FK to called/dependent component. |
| TargetApplication | String | If external app; application name. |
| DependencyType | String | 'Direct', 'Queue', 'Database', 'API', 'Indirect'. |
| CallCount | Int64 | Cumulative calls. |
| AvgLatency | Double | Average call latency (ms). |
| FailureRate | Double | % of failed calls. |
| IsHealthy | Boolean | Dependency is functioning normally. |
| LastVerified | DateTime | Last topology confirmation. |

### Navigation Properties

| Property | Target | Cardinality | Description |
|---|---|---|---|
| SourceComponent | Orion.AppStack.ApplicationComponent | 0..1 | Calling tier. |
| TargetComponent | Orion.AppStack.ApplicationComponent | 0..1 | Called tier. |

### Example Queries

**Unhealthy dependencies (call failures):**

```sql
SELECT 
    SourceComponent.ComponentName AS Caller,
    TargetComponent.ComponentName AS Target,
    FailureRate, 
    AvgLatency,
    CallCount
FROM Orion.AppStack.ServiceDependency
WHERE IsHealthy = 0 OR FailureRate > 5
ORDER BY FailureRate DESC
```

**Dependency chain for critical app:**

```sql
SELECT 
    SourceComponent.Application.ApplicationName AS SourceApp,
    SourceComponent.ComponentName,
    TargetComponent.ComponentName,
    TargetComponent.Application.ApplicationName AS TargetApp,
    DependencyType,
    AvgLatency
FROM Orion.AppStack.ServiceDependency
WHERE SourceComponent.Application.ApplicationName = 'ERP-System'
ORDER BY DependencyType, AvgLatency DESC
```

---

## Orion.AppStack.Metric Entity

Performance metrics for application/component health scoring.

### Properties

| Property | Type | Description |
|---|---|---|
| MetricId | Int64 | Primary key. |
| ComponentId | Int32 | FK to component (or ApplicationId for app-level). |
| MetricType | String | 'Availability', 'ResponseTime', 'Throughput', 'ErrorRate', 'CPU', 'Memory'. |
| MetricValue | Double | Current or sampled metric value. |
| CollectionTime | DateTime | When metric was captured. |
| Threshold | Double | Alert threshold (if configured). |
| IsAnomaly | Boolean | Machine learning flagged as unusual. |

### Example Queries

**Anomalous metric detection:**

```sql
SELECT TOP 50 
    CollectionTime, 
    MetricType, 
    MetricValue, 
    Threshold,
    Component.ComponentName
FROM Orion.AppStack.Metric
WHERE IsAnomaly = 1 AND CollectionTime >= DATEADD(day, -1, GetDate())
ORDER BY CollectionTime DESC
```

