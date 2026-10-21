# SWQL High Availability, Database Optimization & High-Level Design Cookbook

> Consolidated queries for SolarWinds High Availability (HA) pool diagnostics, SQL Server database optimization checks, and high-level platform design (licensing/module inventory).
> HA and High-Level Design sections use SWQL; Database Optimization sections use direct SQL against the SolarWinds SQL Server instance.

---

## SWQL High Availability Queries

### Query: HA Pool Optimization Diagnostic

/* Perform a comprehensive diagnostic of all HA pools, their members, reachability, resource instances, and facility instances to verify HA is properly configured. | Entities: `Orion.HA.Pools`, `Orion.HA.PoolMembers`, `Orion.HA.ReachabilityInfo`, `Orion.HA.ResourcesInstances`, `Orion.HA.FacilitiesInstances` */

```sql
SELECT
    p.PoolId,
    p.DisplayName                 AS PoolName,
    p.VirtualIpAddress            AS VirtualIP,
    p.Enabled                     AS PoolEnabled,
    p.CurrentStatus               AS PoolStatus,
    p.CurrentStatusTimestamp,

    pm.PoolMemberId,
    pm.HostName                   AS MemberHost,
    pm.PreferredStatus            AS IsPreferred,
    pm.Status                     AS MemberStatus,
    pm.LastHeartBeatTimestamp,

    ri.IP                         AS ReachableIP,
    ri.EngineId                   AS ReachableEngineId,
    ri.IsVirtual                  AS IsVirtual,
    ri.CanActAsEngines            AS HA_Capable,

    res.CurrentStatus             AS ResourceStatus,
    fac.CurrentStatus             AS FacilityStatus,

    CASE WHEN pm.PoolMemberId IS NULL THEN 'Missing' ELSE 'Linked' END AS HasMember,
    CASE WHEN ri.HostName IS NULL THEN 'Missing' ELSE 'Linked' END AS ReachabilityLinked,
    CASE WHEN res.RefId IS NULL THEN 'Missing' ELSE 'Linked' END AS ResourcesLinked,
    CASE WHEN fac.RefId IS NULL THEN 'Missing' ELSE 'Linked' END AS FacilitiesLinked

FROM Orion.HA.Pools p
LEFT JOIN Orion.HA.PoolMembers pm
    ON p.PoolId = pm.PoolId
LEFT JOIN Orion.HA.ReachabilityInfo ri
    ON pm.HostName = ri.HostName
LEFT JOIN Orion.HA.ResourcesInstances res
    ON res.PoolMemberId = pm.PoolMemberId
LEFT JOIN Orion.HA.FacilitiesInstances fac
    ON fac.PoolMemberId = pm.PoolMemberId
ORDER BY p.DisplayName, pm.HostName;
```

**Key points**:
- Uses `LEFT JOIN` across all HA entities to reveal broken or incomplete configurations -- rows with "Missing" indicators signal configuration gaps.
- Includes both enabled and disabled pools (no filter on `p.Enabled`) to surface partially configured HA setups.
- The `HasMember`, `ReachabilityLinked`, `ResourcesLinked`, and `FacilitiesLinked` columns act as quick health indicators for each join relationship.
- `PreferredStatus` identifies which pool member is the designated primary; `MemberStatus` shows active/standby state.
- `HA_Capable` from `ReachabilityInfo` confirms whether the server can serve as an HA engine.
- `LastHeartBeatTimestamp` helps diagnose connectivity issues between pool members.

---

### Query: HA Cluster Alert Notification Settings

/* List all enabled alerts that have notifications configured and are associated with HA entity types. | Entities: `Orion.AlertConfigurations`, `Orion.AlertObjects` */

```sql
SELECT
    ac.AlertID,
    ac.Name AS AlertName,
    ac.NotifyEnabled,
    ac.NotificationSettings,
    ao.EntityType
FROM Orion.AlertConfigurations ac
JOIN Orion.AlertObjects ao
    ON ao.AlertID = ac.AlertID
WHERE
    ac.Enabled = true
    AND ac.NotifyEnabled = true
    AND ao.EntityType LIKE '%HA%'
ORDER BY ac.Name;
```

**Key points**:
- Filters for alerts that are both enabled (`Enabled = true`) and have notifications turned on (`NotifyEnabled = true`).
- The `EntityType LIKE '%HA%'` filter isolates alerts specifically targeting HA-related entities (pools, pool members, failover events).
- `NotificationSettings` contains the serialized notification configuration (email recipients, trigger conditions, etc.).
- Useful for verifying that HA failover events will generate notifications to the operations team.

---

## SolarWinds Database Optimization Queries

> **Note**: The queries in this section are standard SQL (T-SQL), not SWQL. They are executed directly against the SQL Server instance hosting the SolarWinds database.

### Query: MaxDOP and Cost Threshold for Parallelism

**Purpose**: Check the current SQL Server MaxDOP (Max Degree of Parallelism) and Cost Threshold for Parallelism settings.
**Target**: `sys.configurations`

```sql
SELECT name AS configuration_name,
       value_in_use
FROM sys.configurations
WHERE name IN ('max degree of parallelism', 'cost threshold for parallelism');
```

**Key points**:
- **MaxDOP**: SolarWinds recommends setting MaxDOP based on the number of CPU cores (typically 1 for OLTP-heavy workloads or matching the NUMA node core count).
- **Cost Threshold for Parallelism**: The default of 5 is often too low for SolarWinds workloads; values of 25-50 are commonly recommended.
- Both settings directly impact query plan optimization and overall database performance under the SolarWinds polling workload.

---

### Query: Database Recovery Model

**Purpose**: List the recovery model for all databases on the SQL Server instance.
**Target**: `sys.databases`

```sql
SELECT name AS database_name,
       recovery_model_desc
FROM sys.databases;
```

**Key points**:
- SolarWinds databases should typically use the **SIMPLE** recovery model unless SQL AlwaysOn Availability Groups require **FULL**.
- Running the SolarWinds database in FULL recovery without regular log backups causes transaction log growth that can fill the disk.
- System databases (master, model, msdb, tempdb) will also appear in results and can be filtered out if needed.

---

### Query: Autogrowth and File Sizes

**Purpose**: Display data file and log file sizes along with their autogrowth configuration for the SolarWinds database.
**Target**: `sys.master_files`

```sql
SELECT db_name(database_id) AS database_name,
       name AS file_name,
       type_desc AS file_type,
       size*8/1024 AS size_mb,
       growth,
       CASE WHEN is_percent_growth = 1 THEN 'PERCENT' ELSE 'MB' END AS growth_type,
       growth*8/1024 AS growth_mb
FROM sys.master_files
WHERE database_id = DB_ID('YourSolarWindsDatabaseName');
```

**Key points**:
- Replace `'YourSolarWindsDatabaseName'` with the actual SolarWinds database name (commonly `SolarWindsOrion`).
- **Percent-based autogrowth** is discouraged because growth increments become increasingly large as the file grows, potentially causing I/O stalls.
- SolarWinds best practice: pre-size data files appropriately and use fixed-size growth increments (e.g., 512 MB or 1024 MB).
- The `size*8/1024` conversion transforms the raw page count (8 KB pages) into megabytes.

---

### Query: CPU Count vs Data File Count Ratio

**Purpose**: Compare the SQL Server CPU count against the number of primary data files for the SolarWinds database to check alignment.
**Target**: `sys.dm_os_sys_info`, `sys.master_files`

```sql
SELECT (SELECT cpu_count FROM sys.dm_os_sys_info) AS cpu_count,
       COUNT(*) AS primary_file_count
FROM sys.master_files
WHERE database_id = DB_ID('YourSolarWindsDatabaseName')
  AND type_desc = 'ROWS';
```

**Key points**:
- Replace `'YourSolarWindsDatabaseName'` with the actual SolarWinds database name.
- Best practice is to have the number of primary data files (ROWS type) be a factor of the CPU core count (e.g., 1 file per 4 cores), up to a maximum of 8 files.
- Multiple data files enable parallel I/O operations and reduce contention on allocation structures (PFS, GAM, SGAM pages).
- TempDB should follow a similar guideline (typically 1 file per core up to 8).

---

### Query: Availability Group Replicas and Roles

**Purpose**: List all SQL Server Availability Group replicas with their current roles, commit modes, and failover modes.
**Target**: `sys.availability_groups`, `sys.availability_replicas`, `sys.dm_hadr_availability_replica_states`

```sql
SELECT
    ag.name AS AGName,
    ar.replica_server_name AS ReplicaServer,
    ars.role_desc AS ReplicaRole,
    ar.availability_mode_desc AS CommitMode,
    ar.failover_mode_desc AS FailoverMode
FROM sys.availability_groups AS ag
JOIN sys.availability_replicas AS ar
    ON ag.group_id = ar.group_id
LEFT JOIN sys.dm_hadr_availability_replica_states AS ars
    ON ar.group_id = ars.group_id
   AND ar.replica_id = ars.replica_id
ORDER BY ag.name, ar.replica_server_name;
```

**Key points**:
- Only relevant when the SolarWinds database is part of a SQL AlwaysOn Availability Group.
- `ReplicaRole` shows PRIMARY or SECONDARY for each replica, indicating which server is actively serving the SolarWinds database.
- `CommitMode`: SYNCHRONOUS_COMMIT ensures no data loss on failover but adds latency; ASYNCHRONOUS_COMMIT allows data loss but has lower latency.
- `FailoverMode`: AUTOMATIC allows SQL Server to fail over without manual intervention; MANUAL requires DBA action.
- SolarWinds HA pools should be configured to recognize the AG listener address rather than individual replica server names.

---

## SWQL High-Level Design Queries

### Query: Installed Modules and Licensing Summary

/* Retrieve a comprehensive list of all installed SolarWinds modules with their license names, versions, evaluation status, and expiration details for high-level design documentation. | Entities: `Orion.InstalledModule` */

```sql
SELECT
    DisplayName AS [Module Name],
    LicenseName AS [License Name],
    Version,
    CASE
        WHEN IsEval = 'True' THEN 'X'
        ELSE '-'
    END AS [Evaluation],
    DaysRemaining AS [Days Left],
    CASE
        WHEN IsExpired = 'True' THEN 'X'
        ELSE '-'
    END AS [Expired]
FROM Orion.InstalledModule
ORDER BY LicenseName;
```

**Key points**:
- Provides a single-query inventory of all SolarWinds modules installed on the platform, ideal for populating a High-Level Design (HLD) document.
- The `Evaluation` column flags modules running on evaluation licenses with "X" for easy identification.
- `DaysRemaining` shows how many days are left on evaluation or subscription licenses; NULL or negative values indicate expiration.
- The `Expired` column flags fully expired licenses that need renewal or removal.
- Results are ordered by `LicenseName` to group related module licenses together (e.g., all NPM licenses, all SAM licenses).
- Useful during platform audits, upgrade planning, or when preparing customer-facing documentation.

---



