# SWQL SAM (Server & Application Monitor) Query Cookbook

## SWQL SAM Queries

### Query: API Poller Status and Counts

/* Retrieves API poller details (name, node, status, monitored value count). Uses nav props. Entities: Orion.APIPoller.ApiPoller */

```sql
SELECT
    api.StatusDescription AS [Status],
    api.DisplayName AS [Poller Name],
    api.node.Caption AS [Assigned To],
    COUNT(api.RequestDetails.ID) AS [Monitored Values Count]
FROM
    Orion.APIPoller.ApiPoller AS api
GROUP BY
    api.DisplayName,
    api.node.Caption,
    api.StatusDescription
```

### Query: AppInsight Template Node Count

/* Counts nodes per AppInsight template (IIS, Exchange, SQL, etc). Filters on %appinsight% LIKE. */

```sql
SELECT
    app.Template.Name AS [Template Name],
    COUNT(app.NODEID) AS [Assigned Node Count]
FROM
    Orion.APM.Application AS app
WHERE
    app.Template.Name LIKE '%appinsight%'
GROUP BY
    app.Template.Name
```

**Key points**:
- The `LIKE '%appinsight%'` filter isolates AppInsight templates from standard SAM templates.
- AppInsight templates provide deep-dive monitoring (e.g., IIS sites, SQL wait stats) beyond basic component checks.
- Useful for licence planning since AppInsight nodes consume additional resources.

---

### Query: ADM Connection Quality Settings and Nodes

/* Shows the current ADM (Application Dependency Mapping) polling settings and lists all nodes that have Dependency TCP Statistics data, combining configuration audit with an inventory in a single result set. | Entities: `Orion.Setting`, `Orion.Nodes`, `Orion.APM.DependencyTcpStatistics` */

```sql
SELECT
    b.description AS [Metric],
    b.value AS [Value]
FROM
    (
        SELECT
            Description,
            Value
        FROM
            Orion.Setting
        WHERE
            Name IN ('ADM.PollingConnectionQualityEnabled', 'ADM.PollingEnabled')

        UNION ALL

        (SELECT
            CONCAT('  ', n.Caption) AS Description,
            '' AS Value
         FROM
            Orion.Nodes n
         JOIN
            Orion.APM.DependencyTcpStatistics tcps
            ON n.NodeID = tcps.NodeToNodeLinkID
         WHERE
            tcps.NodeToNodeLinkID IS NOT NULL)
    ) AS b
ORDER BY
    b.value DESC
```

**Key points**:
- Combines Orion platform settings with node-level TCP dependency data in a single query via a subquery UNION.
- The indented node captions (prefixed with spaces) create a visual hierarchy beneath the setting rows.
- ADM must be enabled at the platform level for connection quality data to be collected.

---

### Query: ADM Application Dependencies Status

/* Retrieves the ADM polling enabled/disabled status from the Orion settings table to confirm whether Application Dependency Mapping is active. | Entities: `Orion.Setting` */

```sql
SELECT
    Description,
    Value
FROM
    Orion.Setting
WHERE
    Name = 'ADM.PollingEnabled'
```

**Key points**:
- A simple settings lookup useful for configuration audits and health checks.
- Value is typically `True` or `False`.
- ADM polling must be enabled for dependency maps and connection quality metrics to function.

---

### Query: AppOptics Integration Type Counts

/* Counts the number of each integration type configured in the SolarWinds AppOptics integration, showing how many AppOptics connections are set up per type. | Entities: `Orion.SamAppOptics.Integration` */

```sql
SELECT
    IntegrationType AS [Integration],
    COUNT(*) AS [Count]
FROM
    Orion.SamAppOptics.Integration
GROUP BY
    IntegrationType
```

**Key points**:
- AppOptics integration bridges SolarWinds on-premises SAM with the SolarWinds cloud APM platform.
- Common integration types include infrastructure metrics and application traces.
- Returns no rows if AppOptics has not been configured.

---

### Query: AppStack Environment Widget Count

/* Counts the number of AppStack Environment widgets deployed across Orion views, indicating how widely the AppStack visualization feature is used. | Entities: `Orion.Resources` */

```sql
SELECT
    COUNT(ResourceID) AS [AppStack Widgets]
FROM
    Orion.Resources
WHERE
    ResourceName LIKE 'AppStack Environment for%'
```

**Key points**:
- AppStack provides a visual topology of application dependencies on node detail views.
- Each widget is a `Resource` entry whose name starts with "AppStack Environment for".
- A zero count may indicate AppStack is not being leveraged despite being available.

---

### Query: Cloud Monitoring Resource Counts

/* Provides a comprehensive inventory of cloud-monitored resources across AWS and Azure, broken down by provider and resource type (instances, volumes, VPCs, VPN gateways). | Entities: `Orion.Cloud.Aws.Instances`, `Orion.Cloud.Aws.Volumes`, `Orion.Cloud.Aws.Vpcs`, `Orion.Cloud.Azure.Instances`, `Orion.Cloud.Azure.Volumes`, `Orion.Cloud.Azure.Vpcs`, `Orion.CloudMonitoring.CloudVPNGateway.AWS`, `Orion.CloudMonitoring.CloudVPNGateway.Azure` */

```sql
SELECT
    Provider,
    'Instances' AS InstanceType,
    COUNT(VirtualMachineID) AS Total
FROM
    Orion.Cloud.Aws.Instances
GROUP BY
    Provider, InstanceType

UNION

(SELECT
    'Amazon AWS' AS [Provider],
    'Volumes' AS InstanceType,
    COUNT(ID) AS Total
 FROM Orion.Cloud.Aws.Volumes
 GROUP BY InstanceType)

UNION

(SELECT
    'Amazon AWS' AS [Provider],
    'Vpcs' AS InstanceType,
    COUNT(ID) AS Total
 FROM Orion.Cloud.Aws.Vpcs
 GROUP BY InstanceType)

UNION

(SELECT
    Provider,
    'Instances' AS InstanceType,
    COUNT(InstanceId) AS Total
 FROM Orion.Cloud.Azure.Instances
 GROUP BY InstanceType)

UNION

(SELECT
    'Microsoft Azure' AS Provider,
    'Volumes' AS InstanceType,
    COUNT(Id) AS Total
 FROM Orion.Cloud.Azure.Volumes
 GROUP BY InstanceType)

UNION

(SELECT
    'Microsoft Azure' AS Provider,
    'Vpcs' AS InstanceType,
    COUNT(Id) AS Total
 FROM Orion.Cloud.Azure.Vpcs
 GROUP BY InstanceType)

UNION ALL

(SELECT
    Provider,
    'VPN Gateway' AS InstanceType,
    COUNT(Id) AS Total
 FROM Orion.CloudMonitoring.CloudVPNGateway.AWS
 GROUP BY InstanceType)

UNION ALL

(SELECT
    Provider,
    'VPN Gateway' AS InstanceType,
    COUNT(Id) AS Total
 FROM Orion.CloudMonitoring.CloudVPNGateway.Azure
 GROUP BY InstanceType)
```

**Key points**:
- Covers both AWS and Azure resource types in a single consolidated report.
- Uses `UNION` (dedup) for standard resources and `UNION ALL` for VPN gateways to preserve provider-specific rows.
- Cloud Monitoring is a SAM add-on; entities will not exist unless the feature is licensed and configured.

---

### Query: Custom Application Monitors and Templates Applied

/* Lists each application by name and template, along with the count of distinct nodes and components it is applied to, providing a full picture of SAM template deployment. | Entities: `Orion.APM.Application` */

```sql
SELECT
    a.Name AS [Application Name],
    COUNT(DISTINCT a.NodeID) AS [Nodes Count],
    COUNT(DISTINCT a.Components.ComponentID) AS [Components Count],
    MAX(a.Template.Name) AS [Template Name]
FROM
    Orion.APM.Application AS a
GROUP BY
    a.ApplicationTemplateID,
    a.Name
```

**Key points**:
- `COUNT(DISTINCT ...)` avoids inflated counts when an application has many components per node.
- `MAX(a.Template.Name)` retrieves the template name without adding it to the GROUP BY clause.
- Useful for capacity planning and understanding which templates are most widely deployed.

---

### Query: Default Application View Check

/* Audits application templates to determine how many use the default application details view versus a custom view, and lists the templates that have custom views enabled. | Entities: `Orion.APM.ApplicationTemplate`, `Orion.Views` */

```sql
SELECT
    'No, use Default Application Details View' AS [Metric],
    SUM(CASE WHEN ISNULL(v.Customizable, 'N') = 'N' THEN 1 END) AS [Count]
FROM Orion.APM.ApplicationTemplate atemp
LEFT JOIN Orion.Views v ON v.ViewID = atemp.ViewID

UNION ALL

(SELECT
    'Yes, create custom view' AS [Metric],
    SUM(CASE WHEN ISNULL(v.Customizable, 'N') != 'N' THEN 1 END) AS [Count]
 FROM Orion.APM.ApplicationTemplate atemp
 LEFT JOIN Orion.Views v ON v.ViewID = atemp.ViewID)

UNION ALL

(SELECT
    atemp.name AS [Metric],
    NULL AS [Count]
 FROM Orion.APM.ApplicationTemplate atemp
 LEFT JOIN Orion.Views v ON v.ViewID = atemp.ViewID
 WHERE ISNULL(v.Customizable, 'N') != 'N')
```

**Key points**:
- The first two rows give a summary count; subsequent rows list the specific templates with custom views.
- `ISNULL(v.Customizable, 'N')` treats NULL as not-customizable for safe comparison.
- Custom views allow teams to tailor the application detail page layout per template.

---

### Query: Monitored Services Count

/* Counts the total number of Windows/Linux service components being monitored by SAM (ComponentType 9 represents service monitors). | Entities: `Orion.APM.Component` */

```sql
SELECT
    COUNT(ComponentID) AS [Services Monitored]
FROM
    Orion.APM.Component
WHERE
    ComponentType = 9
```

**Key points**:
- ComponentType 9 corresponds to Windows/Linux service monitors within SAM application templates.
- A high count relative to your licence may indicate the need for cleanup or licence expansion.
- Other ComponentType values cover process monitors, port monitors, script monitors, etc.

---

### Query: Total Component Count

/* Returns the total count of all SAM components across every application template and node, regardless of component type. | Entities: `Orion.APM.Component` */

```sql
SELECT
    'Total Components Count' AS [Application Name],
    '' AS [Nodes Count],
    ToString(COUNT(DISTINCT c.ComponentID)) AS [Components Count],
    '' AS [Template Name]
FROM
    Orion.APM.Component AS c
```

**Key points**:
- Provides a single summary number useful for licence capacity checks.
- The column aliases match the Custom Application Monitors query structure so results can be combined.
- `ToString()` converts the count to a string for consistent formatting with companion queries.

---


