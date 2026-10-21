# SWQL SAM (Server & Application Monitor) Entity Schema Reference

## Orion.APM.Application Entity Schema (SWQL)

The primary SWQL entity for monitored applications. Each row represents one application monitor instance assigned to a node. An application is created from a template and contains one or more components that perform the actual monitoring checks.

### Properties

| Property | Type | Notes |
|----------|------|-------|
| ApplicationID | Int32 | **Primary Key.** Unique identifier for the application instance. |
| NodeID | Int32 | Foreign key to `Orion.Nodes`. The host where this application runs. |
| Name | String | Display name of the application monitor. |
| Status | Int32 | Current monitoring status (1 = Up, 2 = Down, 3 = Warning, 4 = Critical, 14 = Critical, etc.). |
| StatusDescription | String | Human-readable status label. |
| ApplicationTemplateID | Int32 | Foreign key to `Orion.APM.ApplicationTemplate`. The template this instance was created from. |
| DetailsUrl | String | Relative URL to the application details page in the Orion web console. |
| Uri | String | SWIS URI for this entity instance. |
| DisplayName | String | Formatted name used in the web console. |
| PercentAvailability | Single | Rolling availability percentage. |
| LastTimeUp | DateTime | Most recent time the application was in Up status. |
| ResponseTime | Int64 | Latest measured response time in milliseconds. |
| AvgResponseTime | Int64 | Average response time over the retention period. |
| PercentTimeUp | Single | Percentage of time the application has been Up. |
| Unmanaged | Boolean | True if the application is in an unmanaged state. |
| UnManageFrom | DateTime | Start of the unmanage window (if applicable). |
| UnManageUntil | DateTime | End of the unmanage window (if applicable). |

### SWQL Navigation Properties

| Navigation Property | Target Entity | Cardinality | Description |
|---------------------|---------------|-------------|-------------|
| Node | Orion.Nodes | Reference (single) | The host node for this application. |
| Template | Orion.APM.ApplicationTemplate | Reference (single) | The application template definition. |
| Components | Orion.APM.Component | Collection | All component monitors within this application. |
| CustomProperties | Orion.APM.ApplicationCustomProperties | Reference (single) | Custom property bag. |

### Example SWQL Queries

**All applications currently in a non-Up status:**

```sql
SELECT
    a.Node.Caption AS NodeName,
    a.Name AS ApplicationName,
    a.StatusDescription,
    a.Template.Name AS TemplateName,
    a.DetailsUrl
FROM Orion.APM.Application AS a
WHERE a.Status <> 1
ORDER BY a.Status DESC, a.Node.Caption
```

**Application availability report grouped by template:**

```sql
SELECT
    a.Template.Name AS TemplateName,
    COUNT(a.ApplicationID) AS InstanceCount,
    AVG(a.PercentAvailability) AS AvgAvailability,
    SUM(CASE WHEN a.Status = 1 THEN 1 ELSE 0 END) AS UpCount,
    SUM(CASE WHEN a.Status = 2 THEN 1 ELSE 0 END) AS DownCount
FROM Orion.APM.Application AS a
WHERE a.Unmanaged = false
GROUP BY a.Template.Name
ORDER BY AvgAvailability ASC
```

**Applications with response time above threshold:**

```sql
SELECT
    a.Node.Caption AS NodeName,
    a.Name AS ApplicationName,
    a.ResponseTime,
    a.AvgResponseTime,
    a.StatusDescription
FROM Orion.APM.Application AS a
WHERE a.ResponseTime > 5000
  AND a.Status = 1
ORDER BY a.ResponseTime DESC
```

---

## Orion.APM.Component Entity Schema (SWQL)

Represents an individual component monitor within an application. Components are the atomic monitoring units -- each performs a specific check such as a process monitor, service check, port probe, script execution, or performance counter.

### Properties

| Property | Type | Notes |
|----------|------|-------|
| ComponentID | Int32 | **Primary Key.** Unique identifier for the component. |
| ApplicationID | Int32 | Foreign key to `Orion.APM.Application`. Parent application. |
| Name | String | Display name of the component. |
| ComponentType | Int32 | Numeric type code identifying the monitor kind. |
| Status | Int32 | Current monitoring status code. |
| StatusDescription | String | Human-readable status label. |
| ComponentTypeName | String | Name of the component type (e.g., "Windows Service Monitor", "Process Monitor"). |
| Disabled | Boolean | True if the component is disabled. |
| Uri | String | SWIS URI. |
| DisplayName | String | Formatted name used in the web console. |
| ResponseTime | Int64 | Latest response time in milliseconds. |
| StatisticData | Double | Latest numeric statistic value (interpretation depends on component type). |
| ErrorMessage | String | Most recent error message (empty when healthy). |

### SWQL Navigation Properties

| Navigation Property | Target Entity | Cardinality | Description |
|---------------------|---------------|-------------|-------------|
| Application | Orion.APM.Application | Reference (single) | The parent application. |
| ComponentAlert | Orion.APM.ComponentAlert | Collection | Alert configurations linked to this component. |

### Example SWQL Queries

**Components in a critical or down state with their parent application:**

```sql
SELECT
    c.Application.Node.Caption AS NodeName,
    c.Application.Name AS ApplicationName,
    c.Name AS ComponentName,
    c.ComponentTypeName,
    c.StatusDescription,
    c.ErrorMessage
FROM Orion.APM.Component AS c
WHERE c.Status IN (2, 4, 14)
  AND c.Disabled = false
ORDER BY c.Application.Node.Caption, c.Application.Name
```

**Count of components by type and status:**

```sql
SELECT
    c.ComponentTypeName,
    c.StatusDescription,
    COUNT(c.ComponentID) AS ComponentCount
FROM Orion.APM.Component AS c
GROUP BY c.ComponentTypeName, c.StatusDescription
ORDER BY c.ComponentTypeName, c.StatusDescription
```

---

## Orion.APM.ApplicationTemplate Entity Schema (SWQL)

Defines the template (blueprint) from which application monitor instances are created. Templates specify which component monitors to include and their default configuration.

### Properties

| Property | Type | Notes |
|----------|------|-------|
| ApplicationTemplateID | Int32 | **Primary Key.** Unique identifier for the template. |
| Name | String | Template name (e.g., "Apache Web Server", "Microsoft SQL Server"). |
| Description | String | Human-readable description of what the template monitors. |
| CustomApplicationType | String | Application type classification. |
| Uri | String | SWIS URI. |
| DisplayName | String | Formatted display name. |
| ViewColumn1 | String | Custom view layout definition. |

### Example SWQL Queries

**All templates and how many active instances each has:**

```sql
SELECT
    t.Name AS TemplateName,
    t.Description,
    COUNT(a.ApplicationID) AS InstanceCount
FROM Orion.APM.ApplicationTemplate AS t
LEFT JOIN Orion.APM.Application AS a
    ON t.ApplicationTemplateID = a.ApplicationTemplateID
GROUP BY t.Name, t.Description
ORDER BY InstanceCount DESC
```

**Templates with no assigned applications (unused templates):**

```sql
SELECT
    t.Name AS TemplateName,
    t.Description
FROM Orion.APM.ApplicationTemplate AS t
WHERE t.ApplicationTemplateID NOT IN (
    SELECT DISTINCT a.ApplicationTemplateID
    FROM Orion.APM.Application AS a
)
ORDER BY t.Name
```

---

## SWQL SAM AppInsight Entities

SAM AppInsight provides deep monitoring for specific application platforms. These entities expose detailed internal metrics that go beyond basic up/down status.

### Orion.APM.SqlServerApplication (AppInsight for SQL Server)

Extends standard application monitoring with SQL-Server-specific internals.

| Property | Type | Notes |
|----------|------|-------|
| ApplicationID | Int32 | Foreign key to `Orion.APM.Application`. |
| InstanceName | String | SQL Server instance name. |
| Edition | String | SQL Server edition (Standard, Enterprise, Express, etc.). |
| Version | String | Full version string. |
| ServicePackLevel | String | Installed service pack. |
| ActiveConnections | Int32 | Current active connection count. |
| BufferCacheHitRatio | Single | Percentage of requests served from the buffer pool. |
| PageLifeExpectancy | Int32 | Seconds a page is expected to stay in the buffer pool. |
| BatchRequestsPerSec | Double | SQL batch requests per second. |
| CompilationsPerSec | Double | SQL compilations per second. |
| RecompilationsPerSec | Double | SQL recompilations per second. |
| DeadlocksPerSec | Double | Deadlocks detected per second. |

Related sub-entities:
- `Orion.APM.SqlServerApplication.Database` -- per-database metrics (size, status, recovery model)
- `Orion.APM.SqlServerApplication.Job` -- SQL Agent job status and history
- `Orion.APM.SqlServerApplication.AlwaysOn` -- AG replica state and health

### Orion.APM.IISApplication (AppInsight for IIS)

Deep monitoring for IIS web server instances.

| Property | Type | Notes |
|----------|------|-------|
| ApplicationID | Int32 | Foreign key to `Orion.APM.Application`. |
| Version | String | IIS version. |
| TotalSites | Int32 | Number of configured sites. |
| TotalAppPools | Int32 | Number of application pools. |
| CurrentConnections | Int32 | Active HTTP connections. |
| RequestsPerSec | Double | HTTP requests per second. |
| BytesSentPerSec | Double | Outbound throughput in bytes/sec. |
| BytesReceivedPerSec | Double | Inbound throughput in bytes/sec. |

Related sub-entities:
- `Orion.APM.IISApplication.Site` -- per-site metrics and status
- `Orion.APM.IISApplication.AppPool` -- per-app-pool state, worker process details

### Orion.APM.ExchangeApplication (AppInsight for Exchange)

Monitors Microsoft Exchange Server components.

| Property | Type | Notes |
|----------|------|-------|
| ApplicationID | Int32 | Foreign key to `Orion.APM.Application`. |
| Version | String | Exchange version. |
| ServerRole | String | Server role (Mailbox, Edge Transport, etc.). |
| DatabaseCount | Int32 | Number of mailbox databases. |
| ActiveMailboxCount | Int32 | Number of active mailboxes. |
| MessageQueueLength | Int32 | Current transport queue depth. |

### Example SWQL Queries

**SQL Server instances with low page life expectancy (potential memory pressure):**

```sql
SELECT
    sq.Application.Node.Caption AS NodeName,
    sq.InstanceName,
    sq.PageLifeExpectancy,
    sq.BufferCacheHitRatio,
    sq.ActiveConnections
FROM Orion.APM.SqlServerApplication AS sq
WHERE sq.PageLifeExpectancy < 300
ORDER BY sq.PageLifeExpectancy ASC
```

**IIS sites with high request rates:**

```sql
SELECT
    iis.Application.Node.Caption AS NodeName,
    iis.RequestsPerSec,
    iis.CurrentConnections,
    iis.TotalSites,
    iis.TotalAppPools
FROM Orion.APM.IISApplication AS iis
WHERE iis.RequestsPerSec > 100
ORDER BY iis.RequestsPerSec DESC
```

---

## SWQL SAM Cloud Monitoring Entities

Cloud monitoring entities allow SWQL queries against public cloud resources discovered and monitored through SolarWinds Hybrid Cloud Observability or the Cloud module.

### Orion.Cloud.Instances

Represents individual cloud resource instances (VMs, containers, serverless functions, etc.).

| Property | Type | Notes |
|----------|------|-------|
| InstanceID | Int32 | **Primary Key.** |
| AccountID | Int32 | Foreign key to `Orion.Cloud.Accounts`. |
| ProviderID | Int32 | Foreign key to `Orion.Cloud.Providers`. |
| Name | String | Instance name or resource ID. |
| InstanceType | String | Cloud instance type/size (e.g., "t3.large", "Standard_D4s_v3"). |
| Region | String | Cloud region where the instance runs. |
| Status | Int32 | Monitoring status code. |
| StatusDescription | String | Human-readable status. |
| State | String | Cloud-native state (Running, Stopped, Terminated, etc.). |
| PublicIPAddress | String | Public IP address (if assigned). |
| PrivateIPAddress | String | Private/VPC IP address. |
| Tags | String | Cloud resource tags (JSON or key=value format). |
| CPUUtilization | Single | Current CPU utilization percentage. |
| MemoryUtilization | Single | Current memory utilization percentage. |
| Uri | String | SWIS URI. |

### Orion.Cloud.Accounts

Represents cloud provider account/subscription configurations.

| Property | Type | Notes |
|----------|------|-------|
| AccountID | Int32 | **Primary Key.** |
| Name | String | Account display name. |
| ProviderID | Int32 | Foreign key to `Orion.Cloud.Providers`. |
| AccountIdentifier | String | Provider account ID or subscription ID. |
| Status | Int32 | Connection status. |
| Enabled | Boolean | Whether monitoring is active. |
| TotalInstances | Int32 | Count of monitored instances under this account. |

### Orion.Cloud.Providers

Enumerates supported cloud providers.

| Property | Type | Notes |
|----------|------|-------|
| ProviderID | Int32 | **Primary Key.** |
| Name | String | Provider name (AWS, Azure, GCP). |
| Description | String | Provider description. |

### Example SWQL Queries

**Cloud instances with high CPU across all accounts:**

```sql
SELECT
    ci.Name AS InstanceName,
    ci.InstanceType,
    ci.Region,
    ci.CPUUtilization,
    ci.MemoryUtilization,
    ci.State,
    ca.Name AS AccountName
FROM Orion.Cloud.Instances AS ci
INNER JOIN Orion.Cloud.Accounts AS ca
    ON ci.AccountID = ca.AccountID
WHERE ci.CPUUtilization > 85
  AND ci.State = 'Running'
ORDER BY ci.CPUUtilization DESC
```

**Instance count by region and provider:**

```sql
SELECT
    cp.Name AS Provider,
    ci.Region,
    COUNT(ci.InstanceID) AS InstanceCount,
    SUM(CASE WHEN ci.State = 'Running' THEN 1 ELSE 0 END) AS RunningCount,
    SUM(CASE WHEN ci.State = 'Stopped' THEN 1 ELSE 0 END) AS StoppedCount
FROM Orion.Cloud.Instances AS ci
INNER JOIN Orion.Cloud.Providers AS cp
    ON ci.ProviderID = cp.ProviderID
GROUP BY cp.Name, ci.Region
ORDER BY cp.Name, ci.Region
```
