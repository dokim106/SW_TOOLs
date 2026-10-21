# SWQL Orion Platform Query Cookbook

---

## SWQL Orion Platform - Scalability Queries

### Query: Polling Engines Element Summary

/* Retrieves all engines with element distribution. Entities: Orion.Engines */

```sql
SELECT
    ServerType AS [Server Type],
    ServerName AS [Server Name],
    IP AS [IP Address],
    Elements AS [Total Elements],
    Nodes AS [Total Nodes],
    Interfaces AS [Total Interfaces],
    Volumes AS [Total Volumes],
    Pollers AS [Total Pollers],
    PollingCompletion AS [Polling Completion]
FROM Orion.Engines
ORDER BY ServerType, ServerName
```

### Query: Elements per Engine with Joined Counts

/* Counts nodes/interfaces/volumes/APM components per engine. LEFT JOINs include zero-count engines. */

```sql
SELECT
    e.ServerName AS [Polling Engine],
    e.IP AS [IP Address],
    COUNT(DISTINCT n.NodeID) AS [Total Nodes],
    COUNT(DISTINCT i.InterfaceID) AS [Total Interfaces],
    COUNT(DISTINCT v.VolumeID) AS [Total Volumes],
    COUNT(DISTINCT c.ComponentID) AS [Total Components]
FROM Orion.Engines e
LEFT JOIN Orion.Nodes n ON n.EngineID = e.EngineID
LEFT JOIN Orion.NPM.Interfaces i ON i.NodeID = n.NodeID
LEFT JOIN Orion.Volumes v ON v.NodeID = n.NodeID
LEFT JOIN Orion.APM.Application a ON a.NodeID = n.NodeID
LEFT JOIN Orion.APM.Component c ON c.ApplicationID = a.ApplicationID
GROUP BY e.ServerName, e.IP
ORDER BY e.ServerName
```


---

### Query: Additional Polling Engines (Orion Platform - Scalability)
### Query: Additional Polling Engines

/* Lists APEs from both Orion.Engines and HA.PoolMembers; deduplicates via GROUP BY. */
    EngineVersion
FROM (
    SELECT
        ServerName AS [Server Name],
        IP,
        EngineVersion
    FROM Orion.Engines
    WHERE ServerType = 'Additional'

    UNION ALL

    (
    SELECT
        p.HostName AS [Server Name],
        p.PrimaryIpAddress,
        p.Engine.EngineVersion
    FROM Orion.HA.PoolMembers AS p
    WHERE p.PoolMemberType LIKE '%additionalpoller%'
    )
) AS CombinedResults
GROUP BY
    [Server Name],
    IP,
    EngineVersion
```


---

### Query: Additional Web Engines (Orion Platform - Scalability)
### Query: Additional Web Engines

/* Lists all AWS with hostname/IP/port/SSL. Joins Websites to Nodes on SysName. */
    w.Port,
    CASE
        WHEN w.SSLEnabled = 1 THEN 'Yes'
        ELSE 'No'
    END AS [SSL Enabled]
FROM Orion.Websites AS w
JOIN Orion.Nodes AS n ON w.ServerName = n.SysName
WHERE w.Type = 'Additional'
```


---

### Query: High Availability Pool Members (Orion Platform - Scalability)
### Query: High Availability Pool Members

/* Shows pool name, active/standby status, engine type, host, IP, version. Uses nav props. */
        WHEN p.Priority = 0 THEN 'Active'
        ELSE 'Standby'
    END AS [Status],
    CASE
        WHEN p.PoolMemberType LIKE '%Main%' THEN 'Main'
        ELSE 'Additional'
    END AS [Polling Engine Type],
    p.HostName AS [Server Name],
    p.PrimaryIpAddress,
    p.Engine.EngineVersion
FROM Orion.HA.PoolMembers AS p
```


---

### Query: Database Failover (AlwaysOn/NeverFail) (Orion Platform - Scalability)

/* Placeholder query for checking Database Failover (AlwaysOn/NeverFail) configuration. | Entities: N/A */

```sql
-- TODO
```


---

### Query: Enterprise Operations Console (EOC) (Orion Platform - Scalability)

/* Placeholder query for checking Enterprise Operations Console (EOC) configuration. | Entities: N/A */

```sql
-- TODO
```


---

## SWQL Orion Platform - Administration Queries

### Query: List of Accounts and Types (Orion Platform - Administration)

/* Lists all user accounts in the Orion platform with their account type translated from numeric codes to descriptive labels. | Entities: `Orion.Accounts` */

```sql
SELECT
    AccountID,
    CASE
        WHEN AccountType = 1 THEN 'Local Account'
        WHEN AccountType = 2 THEN 'Windows Individual Account'
        WHEN AccountType = 3 THEN 'Windows Group Account'
        WHEN AccountType = 5 THEN 'SAML Individual Account'
        WHEN AccountType = 6 THEN 'SAML Group Account'
    END AS [Account Type]
FROM Orion.Accounts
WHERE AccountType NOT IN (0, 4)
ORDER BY AccountType, AccountID
```


---

### Query: List of User Account Types and Counts (Orion Platform - Administration)

/* Provides a summary count of user accounts grouped by account type, useful for understanding the authentication profile of the environment. | Entities: `Orion.Accounts` */

```sql
SELECT
    CASE
        WHEN AccountType = 1 THEN 'Local Account'
        WHEN AccountType = 2 THEN 'Windows Individual Account'
        WHEN AccountType = 3 THEN 'Windows Group Account'
        WHEN AccountType = 5 THEN 'SAML Individual Account'
        WHEN AccountType = 6 THEN 'SAML Group Account'
    END AS AccountType,
    COUNT(*) AS Number
FROM Orion.Accounts
WHERE AccountType IN (1, 2, 3, 5, 6)
GROUP BY AccountType
```


---

### Query: Counts of Alert Types and Number Enabled (Orion Platform - Administration)

/* Breaks down alerts into Out of the Box vs. User Defined categories, showing enabled, disabled, and total counts for each, plus a grand total. | Entities: `Orion.AlertConfigurations` */

```sql
SELECT 'Out of the Box' AS [Alert Type],
    SUM(CASE WHEN Enabled = 'True' THEN 1 ELSE 0 END) AS [Enabled],
    SUM(CASE WHEN Enabled = 'False' THEN 1 ELSE 0 END) AS [Disabled],
    COUNT(*) AS Total
FROM Orion.AlertConfigurations
WHERE Canned = 'True'

UNION ALL

(SELECT 'User Defined' AS [Alert Type],
    SUM(CASE WHEN Enabled = 'True' THEN 1 ELSE 0 END) AS [Enabled],
    SUM(CASE WHEN Enabled = 'False' THEN 1 ELSE 0 END) AS [Disabled],
    COUNT(*) AS Total
FROM Orion.AlertConfigurations
WHERE Canned = 'False')

UNION ALL

(SELECT 'Total' AS [Alert Type],
    SUM(CASE WHEN Enabled = 'True' THEN 1 ELSE 0 END) AS [Enabled],
    SUM(CASE WHEN Enabled = 'False' THEN 1 ELSE 0 END) AS [Disabled],
    COUNT(*) AS Total
FROM Orion.AlertConfigurations)
```


---

### Query: List of Custom Alerts (Orion Platform - Administration)

/* Lists all user-defined (custom) alerts with their name, object type, enabled status, and creator. | Entities: `Orion.AlertConfigurations` */

```sql
SELECT
    Name,
    ObjectType AS [Object Type],
    Enabled,
    CreatedBy AS [Creator]
FROM Orion.AlertConfigurations
WHERE Canned = 'False'
ORDER BY ObjectType, Enabled, Name
```


---

### Query: List of Disabled Actions and Associated Alerts (Orion Platform - Administration)

/* Lists all disabled alert actions along with the alert they belong to, useful for identifying actions that may have been accidentally disabled. | Entities: `Orion.Actions`, `Orion.AlertConfigurations` */

```sql
SELECT
    a.Title AS [Action Name],
    a.ActionTypeID AS [Action Type],
    a.Description,
    ac.Name AS [Alert Name]
FROM Orion.Actions a
JOIN Orion.AlertConfigurations ac ON a.Assignments.ParentID = ac.AlertID
WHERE a.Enabled = 'False'
```


---

### Query: List of SMTP Servers (Orion Platform - Administration)

/* Lists all configured SMTP servers used for alert email notifications, including their address, port, default status, and SSL setting. | Entities: `Orion.SMTPServers` */

```sql
SELECT
    Address AS [Server Address],
    Port,
    IsDefault AS [Default Server],
    EnabledSSL AS [SSL]
FROM Orion.SMTPServers
```


---

### Query: SolarWinds Platform Polling Overview (Orion Platform - Administration)

/* Provides a quick overview of all polling engines with their name, type, IP, keep-alive status, element counts, and polling completion percentage. | Entities: `Orion.Engines` */

```sql
SELECT
    ServerName AS Name,
    ServerType AS Type,
    IP,
    MinutesSinceKeepAlive AS [Minutes Since Keep Alive],
    Elements,
    Nodes,
    Interfaces,
    Volumes,
    PollingCompletion AS [Polling Completion %]
FROM Orion.Engines
```


---

### Query: SolarWinds Platform Servers with Resource Usage (Orion Platform - Administration)

/* Lists all Orion servers with their hostname, server type, and current CPU/memory utilization by joining to node monitoring data. | Entities: `Orion.OrionServers`, `Orion.Nodes` (via navigation property) */

```sql
SELECT
    os.Hostname,
    os.ServerType,
    CASE
        WHEN os.Node.CPULoad IS NULL THEN 'Not found. Manually gather.'
        ELSE CONCAT(os.Node.CPULoad, '% of ', os.Node.CPUCount)
    END AS [CPU],
    CASE
        WHEN os.Node.PercentMemoryUsed IS NULL THEN 'Not found. Manually gather.'
        ELSE CONCAT(os.Node.PercentMemoryUsed, '% of ', ROUND(os.Node.TotalMemory / 1024 / 1024 / 1024, 0), ' GB')
    END AS [Percent Memory Used]
FROM Orion.OrionServers os
```


---

### Query: Custom Properties List with Values (Orion Platform - Administration)

/* Lists all custom properties along with their current values, target entity, description, and mandatory flag. | Entities: `Orion.CustomProperty`, `Orion.CustomPropertyValues` */

```sql
SELECT
    cp.TargetEntity,
    cp.Field,
    cpv.Value,
    cp.Description,
    cp.Mandatory
FROM Orion.CustomProperty AS cp
JOIN Orion.CustomPropertyValues AS cpv ON cpv.Field = cp.Field
-- WHERE cp.TargetEntity = 'Orion.NodesCustomProperties'
```


---

### Query: Custom Properties by Object Type and Usage (Orion Platform - Administration)

/* Lists all custom properties with their data type, mandatory flag, and flags indicating where each property is used (alerting, filtering, grouping, reporting, entity detail views). | Entities: `Orion.CustomProperty` (with navigation property `Usage`) */

```sql
SELECT
    Field AS [Custom Property Name],
    Description,
    cp.Usage.Table AS [Object Type],
    CASE
        WHEN DataType = 'nvarchar' THEN 'Text'
        WHEN DataType = 'bit' THEN 'Yes/No'
        WHEN DataType = 'real' THEN 'Floating Point Number'
        WHEN DataType = 'int' THEN 'Integer Number'
        WHEN DataType = 'datetime' THEN 'Date/Time'
    END AS [Format],
    Mandatory,
    CASE WHEN cp.Usage.IsForAlerting = 'True' THEN 'X' ELSE '' END AS [Used for Alerting],
    CASE WHEN cp.Usage.IsForFiltering = 'True' THEN 'X' ELSE '' END AS [Used for Filtering],
    CASE WHEN cp.Usage.IsForGrouping = 'True' THEN 'X' ELSE '' END AS [Used for Grouping],
    CASE WHEN cp.Usage.IsForReporting = 'True' THEN 'X' ELSE '' END AS [Used for Reporting],
    CASE WHEN cp.Usage.IsForEntityDetail = 'True' THEN 'X' ELSE '' END AS [Used for Object Details Views]
FROM Orion.CustomProperty cp
ORDER BY Table, Field
```


---

### Query: Count of Views by View Type (Orion Platform - Administration)

/* Counts the number of active classic views grouped by their view type (e.g., Summary, Detail, etc.). | Entities: `Orion.Views` */

```sql
SELECT
    ViewType AS [View Type],
    COUNT(*) AS Number
FROM Orion.Views
WHERE IsActive = 'True'
GROUP BY ViewType
ORDER BY ViewType
```


---

### Query: Counts of Views by Classic or Modern and OOTB vs Custom (Orion Platform - Administration)

/* Provides a comprehensive breakdown of all views across Classic and Modern dashboards, split by OOTB (out-of-the-box) and Custom, with totals for each. | Entities: `Orion.Views`, `Orion.Dashboards.Instances` */

```sql
SELECT Type, Number
FROM (
    SELECT 'OOTB Classic Views' AS [Type],
        COUNT(*) AS [Number]
    FROM Orion.Views
    WHERE IsActive = 'True' AND (System = 'Y' OR System = '1')

    UNION ALL

    (SELECT 'Custom Classic Views' AS [Type],
        COUNT(*) AS [Number]
    FROM Orion.Views
    WHERE IsActive = 'True' AND (System = 'N' OR System = '0'))

    UNION ALL

    (SELECT 'Total Classic Views' AS [Type],
        COUNT(*) AS [Number]
    FROM Orion.Views
    WHERE IsActive = 'True')

    UNION ALL

    (SELECT 'OOTB Modern Views' AS [Type],
        COUNT(*) AS [Total Number]
    FROM Orion.Dashboards.Instances
    WHERE IsActive = 'True'
        AND Owner = '_system' AND IsSystem = 'True')

    UNION ALL

    (SELECT 'Custom Modern Views' AS [Type],
        COUNT(*) AS [Total Number]
    FROM Orion.Dashboards.Instances
    WHERE IsActive = 'True'
        AND Owner != '_system')

    UNION ALL

    (SELECT 'Total Modern Views' AS [Type],
        COUNT(*) AS [Total Number]
    FROM Orion.Dashboards.Instances
    WHERE IsActive = 'True'
        AND ((Owner = '_system' AND IsSystem = 'True') OR Owner != '_system'))
)
ORDER BY CASE
    WHEN Type = 'OOTB Classic Views' THEN 1
    WHEN Type = 'Custom Classic Views' THEN 2
    WHEN Type = 'Total Classic Views' THEN 3
    WHEN Type = 'OOTB Modern Views' THEN 4
    WHEN Type = 'Custom Modern Views' THEN 5
    WHEN Type = 'Total Modern Views' THEN 6
END
```


---

### Query: Classic Views with Left-Hand Tabs by Number of Tabs (Orion Platform - Administration)

/* Lists classic views that use tabbed navigation (left-hand tabs), showing how many tabs each view group contains. | Entities: `Orion.Views` */

```sql
SELECT
    ViewGroupName,
    COUNT(*) AS [Number of Tabs]
FROM Orion.Views
WHERE ViewGroupName IS NOT NULL AND ViewGroup IS NOT NULL
GROUP BY ViewGroupName
ORDER BY [Number of Tabs] DESC
```


---

### Query: Classic Views with Limitations (Orion Platform - Administration)

/* Lists all active classic views that have limitations (filters) applied, showing the limitation type, table, field, selection method, definition, and WHERE clause. | Entities: `Orion.Views`, `Orion.Limitations`, `Orion.LimitationTypes` */

```sql
SELECT
    CASE
        WHEN ViewGroupPosition IS NULL THEN ViewTitle
        ELSE ViewGroupName
    END AS [View Name],
    ViewType,
    lt.Name AS [Limitation Type],
    lt.Table,
    lt.Field,
    lt.Method AS [Selection Method],
    l.Definition AS [Limitation Definition],
    l.WhereClause AS [Limitation Where Clause]
FROM Orion.Views v
JOIN Orion.Limitations l ON v.LimitationID = l.LimitationID
JOIN Orion.LimitationTypes lt ON l.LimitationTypeID = lt.LimitationTypeID
WHERE IsActive = 'True'
    AND (LimitationID IS NOT NULL AND LimitationID <> 0)
    AND (ViewGroupPosition IS NULL OR ViewGroupPosition = '1')
ORDER BY [View Name]
```


---

### Query: Custom Modern Dashboards by Owner and Public or Private (Orion Platform - Administration)

/* Lists all custom (non-system) Modern Dashboards showing the display name, owner, and whether they are public or private. | Entities: `Orion.Dashboards.Instances` */

```sql
SELECT
    DisplayName AS [Name],
    Owner,
    CASE
        WHEN Private = 'True' THEN 'Private'
        WHEN Private = 'False' THEN 'Public'
    END AS [Public or Private]
FROM Orion.Dashboards.Instances
WHERE IsActive = 'True'
    AND Owner != '_system'
ORDER BY Owner, DisplayName
```


---

### Query: Count of Custom Reports Created by Owners (Orion Platform - Administration)

/* Counts the number of custom reports per owner, ordered by count descending to show the most prolific report creators first. | Entities: `Orion.Report` */

```sql
SELECT
    Owner,
    COUNT(*) AS [Number]
FROM Orion.Report
WHERE Owner IS NOT NULL
GROUP BY Owner
ORDER BY [Number] DESC
```


---

### Query: Count of OOTB vs Custom Reports (Orion Platform - Administration)

/* Provides a simple count comparing Out of the Box reports (no owner) vs. Custom reports (with an owner). | Entities: `Orion.Report` */

```sql
SELECT 'OOTB Reports' AS [Report Type],
    COUNT(*) AS [Number]
FROM Orion.Report
WHERE Owner IS NULL

UNION ALL

(SELECT 'Custom Reports' AS [Report Type],
    COUNT(*) AS [Number]
FROM Orion.Report
WHERE Owner IS NOT NULL)
```


---

### Query: List of Custom Reports and Owners (Orion Platform - Administration)

/* Lists all custom reports with their names and owners, ordered alphabetically by owner then report name. | Entities: `Orion.Report` */

```sql
SELECT
    Name,
    Owner
FROM Orion.Report
WHERE Owner IS NOT NULL
ORDER BY Owner, Name
```


---

### Query: Report Categories and Report Counts (Orion Platform - Administration)

/* Lists all report categories with the number of reports in each, useful for understanding the distribution of reports across categories. | Entities: `Orion.Report` */

```sql
SELECT
    Category,
    COUNT(*) AS [Number]
FROM Orion.Report
GROUP BY Category
ORDER BY Category
```


---

## SWQL Orion Platform - Core Configuration Queries

### Query: Account Types with Counts (Orion Platform - Core Configuration)

/* Summarizes user account types and their counts, including the Orion Service Account (type 0) which is excluded in the Administration version. | Entities: `Orion.Accounts` */

```sql
SELECT
    CASE
        WHEN AccountType = 0 THEN 'Orion Service Account'
        WHEN AccountType = 1 THEN 'Local Orion'
        WHEN AccountType = 2 THEN 'AD Individual'
        WHEN AccountType = 3 THEN 'AD Group'
        WHEN AccountType = 6 THEN 'SAML'
    END AS [Account Type],
    CONCAT(COUNT(*), '') AS [Count]
FROM Orion.Accounts
WHERE AccountType != 4
-- WHERE AccountType IN ('0','1','2','3','6')
GROUP BY AccountType
```


---

### Query: Alert Summary with Trigger History (Orion Platform - Core Configuration)

/* Provides a comprehensive alert summary including total/enabled/active alert counts, oldest and newest active alerts, a 7-day trigger history by day, and the top 5 most-triggered nodes. | Entities: `Orion.AlertDefinitions`, `Orion.AlertActive`, `Orion.AlertHistory`, `Orion.AlertObjects`, `Orion.Nodes` */

```sql
SELECT a.metric, a.v
FROM (
    SELECT 'Total Alerts' AS [Metric], CONCAT(COUNT(*), '') AS [v], 1 AS [o]
    FROM Orion.AlertDefinitions

    UNION ALL

    (SELECT 'Enabled Alerts' AS [c], CONCAT(COUNT(*), '') AS [v], 2 AS [o]
    FROM Orion.AlertDefinitions
    WHERE Enabled = 1)

    UNION ALL

    (SELECT 'Active Alerts' AS [c], CONCAT(COUNT(*), '') AS [v], 3 AS [o]
    FROM Orion.AlertActive)

    UNION ALL

    (SELECT 'Oldest Alert' AS [c], CONCAT(MIN(ToLocal(TriggeredDateTime)), '') AS [v], 4 AS [o]
    FROM Orion.AlertActive)

    UNION ALL

    (SELECT 'Newest Alert' AS [c], CONCAT(MAX(ToLocal(TriggeredDateTime)), '') AS [v], 5 AS [o]
    FROM Orion.AlertActive)

    UNION ALL

    (SELECT TOP 1 '=== ALERT Triggers ===' AS [c], 'Last 7 days' AS [v], 6 AS [o]
    FROM Orion.Nodes)

    UNION ALL

    (SELECT
        CONCAT(YEAR(ah.TimeStamp), '-', MONTH(ah.TimeStamp), '-', DAY(ah.TimeStamp)) AS [date],
        ToString(IsNull(COUNT(*), 0)) AS [Triggered], 7 AS [o]
    FROM Orion.AlertHistory ah
    WHERE DAYDIFF(ToLocal(ah.TimeStamp), GETDATE()) < 7
        AND ah.EventType = 0
    GROUP BY CONCAT(YEAR(ah.TimeStamp), '-', MONTH(ah.TimeStamp), '-', DAY(ah.TimeStamp)))

    UNION ALL

    (SELECT TOP 1 '=== Triggered NODE Top 5 ===' AS [c], 'Last 7 days' AS [v], 8 AS [o]
    FROM Orion.Nodes)

    UNION ALL

    (SELECT TOP 5
        n.Caption AS [a],
        ToString(IsNull(COUNT(*), 0)) AS [Triggered], 9 AS [o]
    FROM Orion.AlertHistory ah
    JOIN Orion.AlertObjects ao ON ao.AlertObjectID = ah.AlertObjectID
    JOIN Orion.Nodes n ON n.NodeID = ao.RelatedNodeId
    WHERE DAYDIFF(ToLocal(ah.TimeStamp), GETDATE()) <= 7
        AND n.Caption IS NOT NULL
        AND ah.EventType = 0
    GROUP BY n.Caption
    ORDER BY COUNT(CASE WHEN ah.EventType = 0 THEN 1 ELSE NULL END) DESC)
) a
ORDER BY a.o
```


---

### Query: Custom Pollers - Device Studio (Orion Platform - Core Configuration)

/* Summarizes Device Studio pollers showing total count, enabled count, and a breakdown by author and technology. | Entities: `Orion.DeviceStudio.Pollers` */

```sql
SELECT TOP 1 '=== Device Pollers ===' AS [c], NULL AS [v]
FROM Orion.Nodes

UNION ALL

(SELECT 'Total' AS [c], COUNT(*) AS [v]
FROM Orion.DeviceStudio.Pollers)

UNION ALL

(SELECT 'Enabled' AS [c], COUNT(*) AS [v]
FROM Orion.DeviceStudio.Pollers
WHERE Enabled = 1)

UNION ALL

(SELECT
    CONCAT('By: ', Author, ' (', p.Technology.Name, ')') AS [c],
    COUNT(*) AS [v]
FROM Orion.DeviceStudio.Pollers p
GROUP BY Author, p.Technology.Name)
```


---

### Query: Config Change Templates (Orion Platform - Core Configuration)

/* Summarizes NCM config change snippets/templates, distinguishing between built-in templates and custom ones, and lists the custom template names. | Entities: `Cirrus.ConfigSnippets` */

```sql
SELECT 'TOTAL' AS [Metric], COUNT(*) AS [Value]
FROM Cirrus.ConfigSnippets

UNION ALL

(SELECT 'Template' AS [Metric], COUNT(*) AS [Value]
FROM Cirrus.ConfigSnippets
WHERE AdvancedScript LIKE '%CHANGE_TEMPLATE_DESCRIPTION%')

UNION ALL

(SELECT 'Custom' AS [Metric], COUNT(*) AS [Value]
FROM Cirrus.ConfigSnippets
WHERE AdvancedScript NOT LIKE '%CHANGE_TEMPLATE_DESCRIPTION%')

UNION ALL

(SELECT Name AS [Metric], NULL AS [Value]
FROM Cirrus.ConfigSnippets
WHERE AdvancedScript NOT LIKE '%CHANGE_TEMPLATE_DESCRIPTION%')
```


---

### Query: Custom Pollers - UnDP (Orion Platform - Core Configuration)

/* Summarizes Universal Device Pollers (UnDP) including total/enabled counts, and details each poller assignment with associated node count and polling interval. | Entities: `Orion.NPM.CustomPollers`, `Orion.NPM.CustomPollerAssignment`, `Orion.Nodes` */

```sql
SELECT TOP 1 '=== UnDP ===' AS [Metric], '' AS [Value]
FROM Orion.Nodes

UNION ALL

(SELECT 'TOTAL UnDP' AS [c], CONCAT(IsNull(COUNT(*), 0), '') AS [v]
FROM Orion.NPM.CustomPollers)

UNION ALL

(SELECT 'Enabled UnDP' AS [c], CONCAT(IsNull(COUNT(*), 0), '') AS [v]
FROM Orion.NPM.CustomPollers
WHERE Enabled = 1)

UNION ALL

(SELECT TOP 1 '=== UnDP: Poller, num of nodes, interval ===' AS [c], '' AS [v]
FROM Orion.Nodes)

UNION ALL

(SELECT
    CONCAT('UnDP: ', cp.GroupName, ' - ', cpa.CustomPollerName) AS [c],
    CASE
        WHEN cp.PollInterval != 0 THEN CONCAT(IsNull(COUNT(cpa.NodeID), 0), ' nodes  at ', cp.PollInterval, ' mins')
        ELSE CONCAT(IsNull(COUNT(cpa.NodeID), 0), ' nodes  at ', n.StatCollection, ' mins')
    END AS [v]
FROM Orion.NPM.CustomPollerAssignment cpa
JOIN Orion.NPM.CustomPollers cp ON cp.CustomPollerID = cpa.CustomPollerID
JOIN Orion.Nodes n ON n.NodeID = cpa.NodeID
WHERE cpa.Status = 1
GROUP BY cpa.CustomPollerName, cp.GroupName, cp.PollInterval, n.StatCollection)
```


---

### Query: Custom Properties Summary by Target (Orion Platform - Core Configuration)

/* Counts the number of custom properties defined for each target entity type (Nodes, Interfaces, Volumes, etc.). | Entities: `Orion.CustomProperty` */

```sql
SELECT
    REPLACE(TargetEntity, 'CustomProperties', '') AS [Target],
    COUNT(Field) AS [Custom Property]
FROM Orion.CustomProperty
GROUP BY TargetEntity
```


---

### Query: Dependencies (Orion Platform - Core Configuration)

/* Summarizes dependency configurations showing total, automatic, and user-defined counts, plus lists the names of all user-defined dependencies. | Entities: `Orion.Dependencies` */

```sql
SELECT 'Total' AS [Metric], COUNT(IsNull(DependencyId, 0)) AS [Count]
FROM Orion.Dependencies

UNION ALL

(SELECT 'Automatic' AS [c], COUNT(*) AS [v]
FROM Orion.Dependencies
WHERE AutoManaged = 1)

UNION ALL

(SELECT 'User-Defined' AS [c], COUNT(*) AS [v]
FROM Orion.Dependencies
WHERE AutoManaged = 0)

UNION ALL

(SELECT d.Name AS [c], NULL AS [v]
FROM Orion.Dependencies d
WHERE AutoManaged = 0)
```


---

### Query: Groups Summary (Orion Platform - Core Configuration)

/* Counts total groups and identifies how many contain dynamic membership rules. | Entities: `Orion.Container`, `Orion.ContainerMemberDefinition` */

```sql
SELECT 'Total' AS [Metric], CONCAT(COUNT(ContainerID), '') AS [Count]
FROM Orion.Container

UNION ALL

(SELECT 'Dynamic' AS [Metric], CONCAT(COUNT(DISTINCT ContainerID), '') AS [Count]
FROM Orion.ContainerMemberDefinition cd
WHERE cd.Definition LIKE 'filter%')
```


---

### Query: Integration Status (Orion Platform - Core Configuration)

/* Checks whether DPA (Database Performance Analyzer) and SEM (Security Event Manager) integrations are enabled or disabled. | Entities: `Orion.DPA.DpaServer`, `Orion.SEM.Nodes` */

```sql
SELECT 'DPA Integration' AS [Metric],
    CASE WHEN COUNT(*) > 0 THEN 'Enabled' ELSE 'Disabled' END AS [v]
FROM Orion.DPA.DpaServer

UNION ALL

(SELECT 'SEM Integration' AS [c],
    CASE WHEN COUNT(*) > 0 THEN 'Enabled' ELSE 'Disabled' END AS [v]
FROM Orion.SEM.Nodes)
```


---

### Query: Maps Configuration (Orion Platform - Core Configuration)

/* Reports on World Map configuration (geolocation setting, node/group/map counts) and Orion Maps project counts by account. | Entities: `Orion.Nodes`, `Orion.Settings`, `Orion.WorldMap.Point`, `Orion.Maps.Projects` */

```sql
SELECT TOP 1 '=== World Map ===' AS [c], ' ' AS [v]
FROM Orion.Nodes

UNION ALL

(SELECT 'Automatic Geolocation' AS [c],
    CASE WHEN CurrentValue = 1 THEN 'ENABLED' ELSE 'DISABLED' END AS [v]
FROM Orion.Settings
WHERE SettingID = 'AutomaticGeolocation-Enable')

UNION ALL

(SELECT 'World Map Nodes' AS [c], CONCAT(IsNull(COUNT(*), 0), '') AS [v]
FROM Orion.WorldMap.Point AS [v]
WHERE Instance = 'Orion.Nodes')

UNION ALL

(SELECT 'World Map Groups' AS [c], CONCAT(IsNull(COUNT(*), 0), '') AS [v]
FROM Orion.WorldMap.Point AS [v]
WHERE Instance = 'Orion.Groups')

UNION ALL

(SELECT 'World Map Maps' AS [c], CONCAT(IsNull(COUNT(*), 0), '') AS [v]
FROM Orion.WorldMap.Point AS [v]
WHERE Instance = 'Orion.WorldMap.PointLabel')

UNION ALL

(SELECT TOP 1 '=== Orion Maps ===' AS [c], ' ' AS [d]
FROM Orion.Nodes)

UNION ALL

(SELECT [AccountID] AS [c], CONCAT(IsNull(COUNT(*), 0), ' maps') AS [v]
FROM Orion.Maps.Projects
GROUP BY AccountID)
```


---

### Query: Monitored Devices by Vendor (Orion Platform - Core Configuration)

/* Groups all monitored nodes by vendor and machine type to understand the device composition of the environment. | Entities: `Orion.Nodes` */

```sql
SELECT
    CONCAT(Vendor, ' - ', MachineType) AS [Vendor],
    COUNT(*) AS [Count]
FROM Orion.Nodes
GROUP BY Vendor, MachineType
```


---

### Query: Polling Method Distribution (Orion Platform - Core Configuration)

/* Counts nodes by their polling method (ObjectSubType) to show the distribution of SNMP, WMI, ICMP, and Agent-polled nodes. | Entities: `Orion.Nodes` */

```sql
SELECT
    ObjectSubType AS [Polling Method],
    COUNT(*) AS [Count]
FROM Orion.Nodes
GROUP BY ObjectSubType
```


---

### Query: Proxy Setting (Orion Platform - Core Configuration)

/* Retrieves the HTTP proxy configuration for the Orion platform, translating the stored value into a human-readable description. | Entities: `Orion.Setting` */

```sql
SELECT
    CASE
        WHEN Value = 'system://default' THEN 'Use Default OS Settings'
        WHEN Value = 'system://disabled' THEN 'Do not use an HTTP proxy'
        WHEN Value LIKE 'http%' THEN 'Use the following settings'
    END AS [Metric],
    Value AS [Value]
FROM Orion.Setting
WHERE Name = 'Orion.HttpProxy.Uri'
```


---

### Query: Reports by Category and Owner (Orion Platform - Core Configuration)

/* Counts custom reports grouped by both category and owner, providing insight into which categories each user is creating reports in. | Entities: `Orion.Report` */

```sql
SELECT
    Category,
    Owner,
    IsNull(COUNT(*), 0) AS [Count]
FROM Orion.Report
WHERE Owner IS NOT NULL
GROUP BY Category, Owner
```


---

### Query: Thresholds and Retention Settings (Orion Platform - Core Configuration)

/* Comprehensive report of all database retention settings, stale element removal settings, and threshold values from Orion.Settings. | Entities: `Orion.Settings`, `Orion.Nodes` */

```sql
SELECT TOP 1 '=== DATABASE SETTINGS ===' AS [Metric], '' AS [v]
FROM Orion.Nodes

UNION ALL

(SELECT 'Node Detailed' AS [c],
    CONCAT(CurrentValue, ' ', Units,
        CASE WHEN CurrentValue <> DefaultValue THEN CONCAT(' <', DefaultValue) ELSE '' END) AS [v]
FROM Orion.Settings
WHERE SettingID = 'SWNetPerfMon-Settings-Retain Detail'
GROUP BY CurrentValue, Units, DefaultValue)

UNION ALL

(SELECT 'Node Hourly' AS [c],
    CONCAT(CurrentValue, ' ', Units,
        CASE WHEN CurrentValue <> DefaultValue THEN CONCAT(' <', DefaultValue) ELSE '' END) AS [v]
FROM Orion.Settings
WHERE SettingID = 'SWNetPerfMon-Settings-Retain Hourly'
GROUP BY CurrentValue, Units, DefaultValue)

UNION ALL

(SELECT 'Node Daily' AS [c],
    CONCAT(CurrentValue, ' ', Units,
        CASE WHEN CurrentValue <> DefaultValue THEN CONCAT(' <', DefaultValue) ELSE '' END) AS [v]
FROM Orion.Settings
WHERE SettingID = 'SWNetPerfMon-Settings-Retain Daily'
GROUP BY CurrentValue, Units, DefaultValue)

UNION ALL

(SELECT TOP 1 '------' AS [c], '------' AS [v] FROM Orion.Nodes)

UNION ALL

(SELECT 'Container Detailed' AS [c],
    CONCAT(CurrentValue, ' ', Units,
        CASE WHEN CurrentValue <> DefaultValue THEN CONCAT(' <', DefaultValue) ELSE '' END) AS [v]
FROM Orion.Settings
WHERE SettingID = 'SWNetPerfMon-Settings-Retain Container Detail'
GROUP BY CurrentValue, Units, DefaultValue)

UNION ALL

(SELECT 'Container Hourly' AS [c],
    CONCAT(CurrentValue, ' ', Units,
        CASE WHEN CurrentValue <> DefaultValue THEN CONCAT(' <', DefaultValue) ELSE '' END) AS [v]
FROM Orion.Settings
WHERE SettingID = 'SWNetPerfMon-Settings-Retain Container Hourly'
GROUP BY CurrentValue, Units, DefaultValue)

UNION ALL

(SELECT 'Container Daily' AS [c],
    CONCAT(CurrentValue, ' ', Units,
        CASE WHEN CurrentValue <> DefaultValue THEN CONCAT(' <', DefaultValue) ELSE '' END) AS [v]
FROM Orion.Settings
WHERE SettingID = 'SWNetPerfMon-Settings-Retain Container Daily'
GROUP BY CurrentValue, Units, DefaultValue)

UNION ALL

(SELECT TOP 1 '------' AS [c], '------' AS [v] FROM Orion.Nodes)

UNION ALL

(SELECT 'Interface Detailed' AS [c],
    CONCAT(CurrentValue, ' ', Units,
        CASE WHEN CurrentValue <> DefaultValue THEN CONCAT(' <', DefaultValue, ')') ELSE '' END) AS [v]
FROM Orion.Settings
WHERE SettingID = 'NPM_Settings_InterfaceAvailability_Retain_Detail'
GROUP BY CurrentValue, Units, DefaultValue)

UNION ALL

(SELECT 'Interface Hourly' AS [c],
    CONCAT(CurrentValue, ' ', Units,
        CASE WHEN CurrentValue <> DefaultValue THEN CONCAT(' <', DefaultValue, ')') ELSE '' END) AS [v]
FROM Orion.Settings
WHERE SettingID = 'NPM_Settings_InterfaceAvailability_Retain_Hourly'
GROUP BY CurrentValue, Units, DefaultValue)

UNION ALL

(SELECT 'Interface Daily' AS [c],
    CONCAT(CurrentValue, ' ', Units,
        CASE WHEN CurrentValue <> DefaultValue THEN CONCAT(' <', DefaultValue, ')') ELSE '' END) AS [v]
FROM Orion.Settings
WHERE SettingID = 'NPM_Settings_InterfaceAvailability_Retain_Daily'
GROUP BY CurrentValue, Units, DefaultValue)

UNION ALL

(SELECT TOP 1 '------' AS [c], '------' AS [v] FROM Orion.Nodes)

UNION ALL

(SELECT 'Delete Stale Interface' AS [c],
    (CASE WHEN CurrentValue = 1 THEN 'YES <NO)' ELSE 'No' END) AS [v]
FROM Orion.Settings
WHERE SettingID = 'NPM_Settings_StaleInterfaces_RemovalEnabled'
GROUP BY CurrentValue, Units)

UNION ALL

(SELECT 'Delete Interface After' AS [c],
    CONCAT(CurrentValue, ' ', Units) AS [v]
FROM Orion.Settings
WHERE SettingID = 'NPM_Settings_StaleInterfaces_RemovalIntervalDays'
GROUP BY CurrentValue, Units)

UNION ALL

(SELECT 'Delete Stale Volumes' AS [c],
    (CASE WHEN CurrentValue = 1 THEN 'YES <NO' ELSE 'No' END) AS [v]
FROM Orion.Settings
WHERE SettingID = 'SWNetPerfMon-Settings-StaleVolume-RemovalEnabled'
GROUP BY CurrentValue, Units)

UNION ALL

(SELECT 'Delete Volumes After' AS [c],
    CONCAT(CurrentValue, ' ', Units) AS [v]
FROM Orion.Settings
WHERE SettingID = 'SWNetPerfMon-Settings-StaleVolume-RemovalIntervalDays'
GROUP BY CurrentValue, Units)

UNION ALL

(SELECT TOP 1 '------' AS [c], '------' AS [v] FROM Orion.Nodes)

UNION ALL

(SELECT 'UnDP Detailed' AS [c],
    CONCAT(CurrentValue, ' ', Units,
        CASE WHEN CurrentValue <> DefaultValue THEN CONCAT(' <', DefaultValue, ')') ELSE '' END) AS [v]
FROM Orion.Settings
WHERE SettingID = 'NPM_Settings_UnDP_Retain_Detail'
GROUP BY CurrentValue, Units, DefaultValue)

UNION ALL

(SELECT 'UnDP Hourly' AS [c],
    CONCAT(CurrentValue, ' ', Units,
        CASE WHEN CurrentValue <> DefaultValue THEN CONCAT(' <', DefaultValue, ')') ELSE '' END) AS [v]
FROM Orion.Settings
WHERE SettingID = 'NPM_Settings_UnDP_Retain_Hourly'
GROUP BY CurrentValue, Units, DefaultValue)

UNION ALL

(SELECT 'UnDP Daily' AS [c],
    CONCAT(CurrentValue, ' ', Units,
        CASE WHEN CurrentValue <> DefaultValue THEN CONCAT(' <', DefaultValue, ')') ELSE '' END) AS [v]
FROM Orion.Settings
WHERE SettingID = 'NPM_Settings_UnDP_Retain_Daily'
GROUP BY CurrentValue, Units, DefaultValue)

UNION ALL

(SELECT TOP 1 '------' AS [c], '------' AS [v] FROM Orion.Nodes)

UNION ALL

(SELECT 'Wireless Detailed' AS [c],
    CONCAT(CurrentValue, ' ', Units,
        CASE WHEN CurrentValue <> DefaultValue THEN CONCAT(' <', DefaultValue, ')') ELSE '' END) AS [v]
FROM Orion.Settings
WHERE SettingID = 'NPM_Settings_Wireless_Retain_Detail'
GROUP BY CurrentValue, Units, DefaultValue)

UNION ALL

(SELECT 'Wireless Hourly' AS [c],
    CONCAT(CurrentValue, ' ', Units,
        CASE WHEN CurrentValue <> DefaultValue THEN CONCAT(' <', DefaultValue, ')') ELSE '' END) AS [v]
FROM Orion.Settings
WHERE SettingID = 'NPM_Settings_Wireless_Retain_Hourly'
GROUP BY CurrentValue, Units, DefaultValue)

UNION ALL

(SELECT 'Wireless Daily' AS [c],
    CONCAT(CurrentValue, ' ', Units,
        CASE WHEN CurrentValue <> DefaultValue THEN CONCAT(' <', DefaultValue, ')') ELSE '' END) AS [v]
FROM Orion.Settings
WHERE SettingID = 'NPM_Settings_Wireless_Retain_Daily'
GROUP BY CurrentValue, Units, DefaultValue)

UNION ALL

(SELECT 'Disappeared AP Retention' AS [c],
    CONCAT(CurrentValue, ' days') AS [v]
FROM Orion.Settings
WHERE SettingID = 'NPM_Settings_Wireless_Retain_Disappeared_AccessPoints')

UNION ALL

(SELECT TOP 1 '------' AS [c], '------' AS [v] FROM Orion.Nodes)

UNION ALL

(SELECT 'Events Retention' AS [c],
    CONCAT(CurrentValue, ' ', Units,
        CASE WHEN CurrentValue <> DefaultValue THEN CONCAT(' <', DefaultValue, ')') ELSE '' END) AS [v]
FROM Orion.Settings
WHERE SettingID = 'SWNetPerfMon-Settings-Retain Events'
GROUP BY CurrentValue, Units, DefaultValue)

UNION ALL

(SELECT 'Auditing Trail' AS [c],
    CONCAT(CurrentValue, ' ', Units,
        CASE WHEN CurrentValue <> DefaultValue THEN CONCAT(' <', DefaultValue, ')') ELSE '' END) AS [v]
FROM Orion.Settings
WHERE SettingID = 'SWNetPerfMon-Settings-Retain Auditing Trails'
GROUP BY CurrentValue, Units, DefaultValue)

UNION ALL

(SELECT 'Syslog' AS [c],
    CONCAT(CurrentValue, ' ', Units,
        CASE WHEN CurrentValue <> DefaultValue THEN CONCAT(' <', DefaultValue, ')') ELSE '' END) AS [v]
FROM Orion.Settings
WHERE SettingID = 'SysLog-MaxMessageAge'
GROUP BY CurrentValue, Units, DefaultValue)

UNION ALL

(SELECT 'Traps' AS [c],
    CONCAT(CurrentValue, ' ', Units,
        CASE WHEN CurrentValue <> DefaultValue THEN CONCAT(' <', DefaultValue, ')') ELSE '' END) AS [v]
FROM Orion.Settings
WHERE SettingID = 'Trap-MaxMessageAge'
GROUP BY CurrentValue, Units, DefaultValue)

UNION ALL

(SELECT 'Baseline' AS [c],
    CONCAT(CurrentValue, ' ', Units,
        CASE WHEN CurrentValue <> DefaultValue THEN CONCAT(' <', DefaultValue, ')') ELSE '' END) AS [v]
FROM Orion.Settings
WHERE SettingID = 'SWNetPerfMon-Settings-Baseline Collection Duration'
GROUP BY CurrentValue, Units, DefaultValue)

UNION ALL

(SELECT 'Node Warning Level' AS [c],
    CONCAT(CurrentValue, ' ', Units,
        CASE WHEN CurrentValue <> 120 THEN ' <120)' ELSE '' END) AS [v]
FROM Orion.Settings
WHERE SettingID = 'SWNetPerfMon-Settings-Default Fast Poll Interval'
GROUP BY CurrentValue, Units)
```


---

## SWQL Orion Platform - Polling Queries

### Query: Manage Pollers by Type (Orion Platform - Polling)

/* Counts pollers (status pollers) by their type, focusing on Agent, ICMP, and SNMP native status pollers. | Entities: `Orion.Pollers` */

```sql
SELECT
    REPLACE(REPLACE(REPLACE(PollerType, '.native', ''), 'N.', ''), '.', '-') AS [Poller Type],
    COUNT(PollerID) AS [Total]
FROM Orion.Pollers
WHERE PollerType = 'N.Status.Agent.Native'
    OR PollerType = 'N.Status.ICMP.Native'
    OR PollerType = 'N.Status.SNMP.Native'
GROUP BY PollerType
```


---

### Query: Counts of Nodes by Polling Method (Orion Platform - Polling)

/* Provides a detailed breakdown of node counts by polling method, including individual SNMP version counts (v1, v2, v3), a total SNMP count, and WMI/ICMP/Agent counts. | Entities: `Orion.Nodes` */

```sql
SELECT 'Agent' AS [Polling Method], COUNT(*) AS [Number of Nodes]
FROM Orion.Nodes
WHERE ObjectSubType = 'Agent'

UNION ALL

(SELECT 'ICMP' AS [Polling Method], COUNT(*) AS [Number of Nodes]
FROM Orion.Nodes
WHERE ObjectSubType = 'ICMP')

UNION ALL

(SELECT 'SNMP v1' AS [Polling Method], COUNT(*) AS [Number of Nodes]
FROM Orion.Nodes
WHERE ObjectSubType = 'SNMP' AND SNMPVersion = '1')

UNION ALL

(SELECT 'SNMP v2' AS [Polling Method], COUNT(*) AS [Number of Nodes]
FROM Orion.Nodes
WHERE ObjectSubType = 'SNMP' AND SNMPVersion = '2')

UNION ALL

(SELECT 'SNMP v3' AS [Polling Method], COUNT(*) AS [Number of Nodes]
FROM Orion.Nodes
WHERE ObjectSubType = 'SNMP' AND SNMPVersion = '3')

UNION ALL

(SELECT 'Total SNMP' AS [Polling Method], COUNT(*) AS [Number of Nodes]
FROM Orion.Nodes
WHERE ObjectSubType = 'SNMP')

UNION ALL

(SELECT 'WMI' AS [Polling Method], COUNT(*) AS [Number of Nodes]
FROM Orion.Nodes
WHERE ObjectSubType = 'WMI')
```


---

### Query: List of WMI Nodes and Their Credentials (Orion Platform - Polling)

/* Lists all WMI-polled nodes with their credential names, useful for auditing WMI credential assignments across the environment. | Entities: `Orion.Credential`, `Orion.NodeSettings`, `Orion.Nodes` */

```sql
SELECT
    n.Caption AS Server,
    n.IP_Address AS [IP Address],
    c.Name AS [Credential Name]
FROM Orion.Credential c
JOIN Orion.NodeSettings ns ON c.ID = ns.SettingValue
JOIN Orion.Nodes n ON ns.NodeID = n.NodeID
WHERE ns.SettingName = 'WMICredential'
ORDER BY c.Name, n.Caption
```


---

## SWQL Orion Platform - Server Queries

### Query: Count of Disabled Actions (Orion Platform - Servers)

/* Returns a simple count of how many alert actions are currently disabled across all alerts. | Entities: `Orion.Actions` */

```sql
SELECT
    COUNT(*) AS [Number of Disabled Actions]
FROM Orion.Actions
WHERE Enabled = 'False'
```


---


