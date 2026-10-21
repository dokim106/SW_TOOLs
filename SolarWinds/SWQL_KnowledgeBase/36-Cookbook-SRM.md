# SWQL SRM (Storage Resource Monitor) Query Cookbook

> Consolidated SWQL queries for SolarWinds Storage Resource Monitor (SRM).
> Covers storage arrays, end-to-end topology mapping, credentials, global threshold settings, device groups, server-volume mapping, and providers.

---

## Arrays

### Query: Count Storage Arrays

/* Count the total number of distinct storage arrays being monitored by SRM. | Entities: `Orion.SRM.StorageArrays` */

```sql
SELECT
    COUNT(DISTINCT StorageArrayID) AS [Storage Array Count]
FROM
    Orion.SRM.StorageArrays;
```

**Key points**:
- Uses `COUNT(DISTINCT StorageArrayID)` to ensure each physical or virtual storage array is counted once.
- Storage arrays are the top-level objects in the SRM hierarchy (arrays contain pools, LUNs, controllers, etc.).
- A zero count means no storage arrays have been added to SRM for monitoring.

---

## End-to-End Mapping (Automatic)

### Query: Count Automatic End-to-End Mappings

/* Count the number of automatically discovered server-to-storage topology mappings. | Entities: `Orion.SRM.Topology` */

```sql
SELECT
    'Automatic' AS [Mapping Type],
    COUNT(*) AS [Count]
FROM
    Orion.SRM.Topology AS t
WHERE
    Manual = 'false'
GROUP BY
    'Automatic'
ORDER BY
    [Mapping Type];
```

**Key points**:
- Filters on `Manual = 'false'` to isolate topology entries that SRM discovered automatically.
- End-to-end mapping links servers (compute) to their storage resources (LUNs, volumes) through the fabric path.
- Automatic mappings are created by SRM's discovery process and updated on each rediscovery cycle.
- Compare this count with the manual mapping count to assess how much of your storage topology is auto-discovered.

---

## End-to-End Mapping (Manual)

### Query: Count Manual Server-Volume Mappings

/* Count the number of manually configured server-to-storage topology mappings. | Entities: `Orion.SRM.Topology` */

```sql
SELECT
    'Manual' AS [Mapping Type],
    COUNT(*) AS [Count]
FROM
    Orion.SRM.Topology AS t
WHERE
    Manual = 'true'
GROUP BY
    'Manual'
ORDER BY
    [Mapping Type];
```

**Key points**:
- Filters on `Manual = 'true'` to isolate topology entries that were manually created by an administrator.
- Manual mappings are typically needed when automatic discovery cannot trace the full path (e.g., through unsupported fabric switches).
- A high ratio of manual-to-automatic mappings may indicate discovery configuration issues worth investigating.

---

## Credentials

### Query: List SRM Credentials

/* Display all credentials assigned to SRM, showing their display name and credential type. | Entities: `Orion.Credential` */

```sql
SELECT
    Name AS [Credential Display Name],
    Substring(
        CredentialType,
        CharIndex('Credentials.', CredentialType) + 12,
        (length(CredentialType) - CharIndex('.Credentials.', CredentialType))
    ) AS [Credential Type]
FROM
    Orion.Credential
WHERE
    credentialowner = 'SRM';
```

**Key points**:
- Filters by `credentialowner = 'SRM'` to show only credentials assigned to the Storage Resource Monitor module.
- The `Substring` / `CharIndex` combination extracts the human-readable credential type from the fully qualified .NET type name (e.g., extracts "SNMPv2Credentials" from the full namespace).
- `Orion.Credential` is a shared entity; other modules (NPM, SAM, NCM) also store their credentials here with different `credentialowner` values.
- Useful for auditing which credential sets are configured for storage array access.

---

## Global Settings (All)

### Query: SRM Global Threshold Settings by Category

/* Display all SRM global warning and critical threshold settings, organized by storage category (Array, Pool, LUN, NAS Volume, File Share, Vserver, Storage Controller, Storage Controller Port). | Entities: `Orion.Settings` */

```sql
SELECT
    CASE
        WHEN SettingID LIKE 'SRM_Array_%' THEN 'Array'
        WHEN SettingID LIKE 'SRM_Pool_%' THEN 'Pool'
        WHEN SettingID LIKE 'SRM_Lun_%' THEN 'LUN'
        WHEN SettingID LIKE 'SRM_NASVolume_%' THEN 'NAS Volume'
        WHEN SettingID LIKE 'SRM_FileShare_%' THEN 'File Share'
        WHEN SettingID LIKE 'SRM_Vserver_%' THEN 'Vserver'
        WHEN SettingID LIKE 'SRM_StorageController_%' AND SettingID NOT LIKE '%Port%' THEN 'Storage Controller'
        WHEN SettingID LIKE 'SRM_StorageControllerPort_%' THEN 'Storage Controller Port'
    END AS [Category],
    CONCAT(
        CASE
            WHEN Name LIKE '%Cache Hit Ratio%' THEN 'Cache Hit Ratio'
            WHEN Name LIKE '%Disk Busy%' THEN 'Disk Busy'
            WHEN Name LIKE '%File System Used Capacity%' THEN 'File System Used Capacity'
            WHEN Name LIKE '%Provisioned Capacity%' THEN 'Provisioned Capacity'
            WHEN Name LIKE '%Queue Length %' THEN 'Queue Length'
            WHEN Name LIKE '%R/W IOPS Ratio%' THEN 'R/W IOPS Ratio'
            WHEN Name LIKE '%Utilization%' THEN 'Utilization'
            WHEN Name LIKE '%IOPS%' THEN 'IOPS'
            WHEN Name LIKE '%IOSize%' THEN 'IO Size'
            WHEN Name LIKE '%Latency%' THEN 'Latency'
            WHEN Name LIKE '%Throughput%' THEN 'Throughput'
        END,
        CASE
            WHEN Name LIKE '%Other%' THEN ' (Other)'
            WHEN Name LIKE '%Read%' THEN ' (Read)'
            WHEN Name LIKE '%Write%' THEN ' (Write)'
            WHEN Name LIKE '%Total%' THEN ' (Total)'
            WHEN Name LIKE '%Distribution%' THEN ' Distribution'
        END
    ) AS [Setting Name],
    MAX(CASE
        WHEN Name LIKE '%Warning Level%' THEN
            CONCAT(ToString(
                CASE
                    WHEN Units = 'IOPS' AND ABS(CurrentValue) >= 1000 AND ABS(CurrentValue) < 1000000 THEN (CurrentValue / 1000)
                    WHEN Units = 'IOPS' AND ABS(CurrentValue) >= 1000000 THEN (CurrentValue / 1000000)
                    WHEN Units LIKE '%B%' AND ABS(CurrentValue) >= 1000 AND ABS(CurrentValue) < 1000000 THEN (CurrentValue / 1000)
                    WHEN Units LIKE '%B%' AND ABS(CurrentValue) >= 1000000 AND ABS(CurrentValue) < 1000000000 THEN (CurrentValue / 1000000)
                    WHEN Units LIKE '%B%' AND ABS(CurrentValue) >= 1000000000 THEN (CurrentValue / 1000000000)
                    ELSE CurrentValue
                END), ' ',
                CASE
                    WHEN Units = 'IOPS' AND ABS(CurrentValue) < 1000 THEN ''
                    WHEN Units = 'IOPS' AND ABS(CurrentValue) >= 1000 AND ABS(CurrentValue) < 1000000 THEN 'k'
                    WHEN Units = 'IOPS' AND ABS(CurrentValue) >= 1000000 THEN 'mil'
                    WHEN Units = 'B' AND ABS(CurrentValue) >= 1000 AND ABS(CurrentValue) < 1000000 THEN 'kB'
                    WHEN Units = 'B' AND ABS(CurrentValue) >= 1000000 AND ABS(CurrentValue) < 1000000000 THEN 'MB'
                    WHEN Units = 'B' AND ABS(CurrentValue) >= 1000000000 THEN 'GB'
                    WHEN Units LIKE '%/s%' AND ABS(CurrentValue) >= 1000 AND ABS(CurrentValue) < 1000000 THEN 'kB/s'
                    WHEN Units LIKE '%/s%' AND ABS(CurrentValue) >= 1000000 AND ABS(CurrentValue) < 1000000000 THEN 'MB/s'
                    WHEN Units LIKE '%/s%' AND ABS(CurrentValue) >= 1000000000 THEN 'GB/s'
                    ELSE Units
                END)
    END) AS [Warning Threshold],
    MAX(CASE
        WHEN Name LIKE '%Warning Level%' AND ABS(CurrentValue) <> ABS(DefaultValue) THEN
            CONCAT(ToString(
                CASE
                    WHEN Units = 'IOPS' AND ABS(DefaultValue) >= 1000 AND ABS(DefaultValue) < 1000000 THEN (DefaultValue / 1000)
                    WHEN Units = 'IOPS' AND ABS(DefaultValue) >= 1000000 THEN (DefaultValue / 1000000)
                    WHEN Units LIKE '%B%' AND ABS(DefaultValue) >= 1000 AND ABS(DefaultValue) < 1000000 THEN (DefaultValue / 1000)
                    WHEN Units LIKE '%B%' AND ABS(DefaultValue) >= 1000000 AND ABS(DefaultValue) < 1000000000 THEN (DefaultValue / 1000000)
                    WHEN Units LIKE '%B%' AND ABS(DefaultValue) >= 1000000000 THEN (DefaultValue / 1000000000)
                    ELSE DefaultValue
                END), ' ',
                CASE
                    WHEN Units = 'IOPS' AND ABS(DefaultValue) < 1000 THEN ''
                    WHEN Units = 'IOPS' AND ABS(DefaultValue) >= 1000 AND ABS(DefaultValue) < 1000000 THEN 'k'
                    WHEN Units = 'IOPS' AND ABS(DefaultValue) >= 1000000 THEN 'mil'
                    WHEN Units = 'B' AND ABS(DefaultValue) >= 1000 AND ABS(DefaultValue) < 1000000 THEN 'kB'
                    WHEN Units = 'B' AND ABS(DefaultValue) >= 1000000 AND ABS(DefaultValue) < 1000000000 THEN 'MB'
                    WHEN Units = 'B' AND ABS(DefaultValue) >= 1000000000 THEN 'GB'
                    WHEN Units LIKE '%/s%' AND ABS(DefaultValue) >= 1000 AND ABS(DefaultValue) < 1000000 THEN 'kB/s'
                    WHEN Units LIKE '%/s%' AND ABS(DefaultValue) >= 1000000 AND ABS(DefaultValue) < 1000000000 THEN 'MB/s'
                    WHEN Units LIKE '%/s%' AND ABS(DefaultValue) >= 1000000000 THEN 'GB/s'
                    ELSE Units
                END)
        WHEN Name LIKE '%Warning Level%' AND ABS(CurrentValue) = ABS(DefaultValue) THEN 'Same'
    END) AS [Default Warning Threshold],
    MAX(CASE
        WHEN Name LIKE '%Critical Level%' THEN
            CONCAT(ToString(
                CASE
                    WHEN Units = 'IOPS' AND ABS(CurrentValue) >= 1000 AND ABS(CurrentValue) < 1000000 THEN (CurrentValue / 1000)
                    WHEN Units = 'IOPS' AND ABS(CurrentValue) >= 1000000 THEN (CurrentValue / 1000000)
                    WHEN Units LIKE '%B%' AND ABS(CurrentValue) >= 1000 AND ABS(CurrentValue) < 1000000 THEN (CurrentValue / 1000)
                    WHEN Units LIKE '%B%' AND ABS(CurrentValue) >= 1000000 AND ABS(CurrentValue) < 1000000000 THEN (CurrentValue / 1000000)
                    WHEN Units LIKE '%B%' AND ABS(CurrentValue) >= 1000000000 THEN (CurrentValue / 1000000000)
                    ELSE CurrentValue
                END), ' ',
                CASE
                    WHEN Units = 'IOPS' AND ABS(CurrentValue) < 1000 THEN ''
                    WHEN Units = 'IOPS' AND ABS(CurrentValue) >= 1000 AND ABS(CurrentValue) < 1000000 THEN 'k'
                    WHEN Units = 'IOPS' AND ABS(CurrentValue) >= 1000000 THEN 'mil'
                    WHEN Units = 'B' AND ABS(CurrentValue) >= 1000 AND ABS(CurrentValue) < 1000000 THEN 'kB'
                    WHEN Units = 'B' AND ABS(CurrentValue) >= 1000000 AND ABS(CurrentValue) < 1000000000 THEN 'MB'
                    WHEN Units = 'B' AND ABS(CurrentValue) >= 1000000000 THEN 'GB'
                    WHEN Units LIKE '%/s%' AND ABS(CurrentValue) >= 1000 AND ABS(CurrentValue) < 1000000 THEN 'kB/s'
                    WHEN Units LIKE '%/s%' AND ABS(CurrentValue) >= 1000000 AND ABS(CurrentValue) < 1000000000 THEN 'MB/s'
                    WHEN Units LIKE '%/s%' AND ABS(CurrentValue) >= 1000000000 THEN 'GB/s'
                    ELSE Units
                END)
    END) AS [Critical Threshold],
    MAX(CASE
        WHEN Name LIKE '%Critical Level%' AND ABS(CurrentValue) <> ABS(DefaultValue) THEN
            CONCAT(ToString(
                CASE
                    WHEN Units = 'IOPS' AND ABS(DefaultValue) >= 1000 AND ABS(DefaultValue) < 1000000 THEN (DefaultValue / 1000)
                    WHEN Units = 'IOPS' AND ABS(DefaultValue) >= 1000000 THEN (DefaultValue / 1000000)
                    WHEN Units LIKE '%B%' AND ABS(DefaultValue) >= 1000 AND ABS(DefaultValue) < 1000000 THEN (DefaultValue / 1000)
                    WHEN Units LIKE '%B%' AND ABS(DefaultValue) >= 1000000 AND ABS(DefaultValue) < 1000000000 THEN (DefaultValue / 1000000)
                    WHEN Units LIKE '%B%' AND ABS(DefaultValue) >= 1000000000 THEN (DefaultValue / 1000000000)
                    ELSE DefaultValue
                END), ' ',
                CASE
                    WHEN Units = 'IOPS' AND ABS(DefaultValue) < 1000 THEN ''
                    WHEN Units = 'IOPS' AND ABS(DefaultValue) >= 1000 AND ABS(DefaultValue) < 1000000 THEN 'k'
                    WHEN Units = 'IOPS' AND ABS(DefaultValue) >= 1000000 THEN 'mil'
                    WHEN Units = 'B' AND ABS(DefaultValue) >= 1000 AND ABS(DefaultValue) < 1000000 THEN 'kB'
                    WHEN Units = 'B' AND ABS(DefaultValue) >= 1000000 AND ABS(DefaultValue) < 1000000000 THEN 'MB'
                    WHEN Units = 'B' AND ABS(DefaultValue) >= 1000000000 THEN 'GB'
                    WHEN Units LIKE '%/s%' AND ABS(DefaultValue) >= 1000 AND ABS(DefaultValue) < 1000000 THEN 'kB/s'
                    WHEN Units LIKE '%/s%' AND ABS(DefaultValue) >= 1000000 AND ABS(DefaultValue) < 1000000000 THEN 'MB/s'
                    WHEN Units LIKE '%/s%' AND ABS(DefaultValue) >= 1000000000 THEN 'GB/s'
                    ELSE Units
                END)
        WHEN Name LIKE '%Critical Level%' AND ABS(CurrentValue) = ABS(DefaultValue) THEN 'Same'
    END) AS [Default Critical Threshold]
FROM
    Orion.Settings
WHERE
    SettingID LIKE '%srm%'
    AND SettingID NOT IN (
        'SRM_Array_ControllerInterval', 'SRM_Array_RediscoveryInterval',
        'SRM_Array_StatCollection', 'SRM_Array_TopologyInterval',
        'SRM_Array_Thresholds_IOSize_Other_Critical', 'SRM_Array_Thresholds_IOSize_Other_Warning',
        'SRM_Array_Thresholds_Throughput_Other_Critical', 'SRM_Array_Thresholds_Throughput_Other_Warning',
        'SRM_Pool_Thresholds_IOSize_Other_Critical', 'SRM_Pool_Thresholds_IOSize_Other_Warning',
        'SRM_Pool_Thresholds_Throughput_Other_Critical', 'SRM_Pool_Thresholds_Throughput_Other_Warning',
        'SRM_Lun_Thresholds_FileSystemUsedCapacity_Critical', 'SRM_Lun_Thresholds_FileSystemUsedCapacity_Warning',
        'SRM_Lun_Thresholds_IOSize_Other_Critical', 'SRM_Lun_Thresholds_IOSize_Other_Warning',
        'SRM_Lun_Thresholds_ProvisionedCapacity_Critical', 'SRM_Lun_Thresholds_ProvisionedCapacity_Warning',
        'SRM_Lun_Thresholds_Throughput_Other_Critical', 'SRM_Lun_Thresholds_Throughput_Other_Warning',
        'SRM_NasVolume_Thresholds_IOSize_Other_Critical', 'SRM_NasVolume_Thresholds_IOSize_Other_Warning',
        'SRM_NasVolume_Thresholds_Throughput_Other_Critical', 'SRM_NasVolume_Thresholds_Throughput_Other_Warning',
        'SRM_Vserver_Thresholds_CacheHitRatio_Critical', 'SRM_Vserver_Thresholds_CacheHitRatio_Warning',
        'SRM_Vserver_Thresholds_IOSize_Other_Critical', 'SRM_Vserver_Thresholds_IOSize_Other_Warning',
        'SRM_Vserver_Thresholds_Throughput_Other_Critical', 'SRM_Vserver_Thresholds_Throughput_Other_Warning',
        'SRM_StorageController_Thresholds_IOSize_Other_Critical', 'SRM_StorageController_Thresholds_IOSize_Other_Warning',
        'SRM_CriticalThreshold_CapacityRunOut', 'SRM_CriticalThresholdDays',
        'SRM_CriticalThresholdLatencyMS', 'SRM_Provider_PollingInterval',
        'SRM_RunOutTimePeriod_Arrays', 'SRM_RunOutTimePeriod_Luns',
        'SRM_RunOutTimePeriod_Pools', 'SRM_RunOutTimePeriod_Volumes',
        'SRM_RunOutTimePeriod_Vservers', 'SRM_WarningThreshold_CapacityRunOut',
        'SRM_WarningThresholdDays', 'SRM_WarningThresholdLatencyMS'
    )
GROUP BY
    CASE
        WHEN SettingID LIKE 'SRM_Array_%' THEN 'Array'
        WHEN SettingID LIKE 'SRM_Pool_%' THEN 'Pool'
        WHEN SettingID LIKE 'SRM_Lun_%' THEN 'LUN'
        WHEN SettingID LIKE 'SRM_NASVolume_%' THEN 'NAS Volume'
        WHEN SettingID LIKE 'SRM_FileShare_%' THEN 'File Share'
        WHEN SettingID LIKE 'SRM_Vserver_%' THEN 'Vserver'
        WHEN SettingID LIKE 'SRM_StorageController_%' AND SettingID NOT LIKE '%Port%' THEN 'Storage Controller'
        WHEN SettingID LIKE 'SRM_StorageControllerPort_%' THEN 'Storage Controller Port'
    END,
    CONCAT(
        CASE
            WHEN Name LIKE '%Cache Hit Ratio%' THEN 'Cache Hit Ratio'
            WHEN Name LIKE '%Disk Busy%' THEN 'Disk Busy'
            WHEN Name LIKE '%File System Used Capacity%' THEN 'File System Used Capacity'
            WHEN Name LIKE '%Provisioned Capacity%' THEN 'Provisioned Capacity'
            WHEN Name LIKE '%Queue Length %' THEN 'Queue Length'
            WHEN Name LIKE '%R/W IOPS Ratio%' THEN 'R/W IOPS Ratio'
            WHEN Name LIKE '%Utilization%' THEN 'Utilization'
            WHEN Name LIKE '%IOPS%' THEN 'IOPS'
            WHEN Name LIKE '%IOSize%' THEN 'IO Size'
            WHEN Name LIKE '%Latency%' THEN 'Latency'
            WHEN Name LIKE '%Throughput%' THEN 'Throughput'
        END,
        CASE
            WHEN Name LIKE '%Other%' THEN ' (Other)'
            WHEN Name LIKE '%Read%' THEN ' (Read)'
            WHEN Name LIKE '%Write%' THEN ' (Write)'
            WHEN Name LIKE '%Total%' THEN ' (Total)'
            WHEN Name LIKE '%Distribution%' THEN ' Distribution'
        END
    )
ORDER BY [Category], [Setting Name] ASC;
```

**Key points**:
- This is a comprehensive query that pivots warning and critical thresholds into a single row per metric per storage category.
- The `NOT IN` exclusion list filters out settings that do not appear in the Global SRM Settings web page (`/Orion/SRM/Admin/Default.aspx`), keeping the output aligned with what administrators see in the UI.
- Unit conversion logic auto-scales raw values (bytes, IOPS, bytes/s) into human-readable units (kB, MB, GB, k, mil).
- The `Default Warning Threshold` and `Default Critical Threshold` columns show "Same" when the current value matches the factory default, making it easy to spot customized thresholds.
- Categories covered: Array, Pool, LUN, NAS Volume, File Share, Vserver, Storage Controller, and Storage Controller Port.
- Uses `MAX(CASE ...)` aggregation to pivot warning and critical values into separate columns within the same grouped row.

---

## Groups

### Query: List SRM Device Groups

/* Display all SRM device groups with their names and descriptions. | Entities: `Orion.SRM.DeviceGroups`, `Orion.SRM.Providers` */

```sql
SELECT
    DG.Name AS [Device Group Name],
    DG.Description AS [Device Group Description]
FROM
    Orion.SRM.DeviceGroups AS DG
JOIN
    Orion.SRM.Providers AS P ON DG.DeviceGroupID = P.DeviceGroupID
ORDER BY
    DG.DeviceGroupID;
```

**Key points**:
- Joins `DeviceGroups` to `Providers` to only show groups that have at least one provider (storage array) assigned.
- Device groups are organizational containers that logically group storage arrays (e.g., by data center, array vendor, or business unit).
- Results are ordered by `DeviceGroupID` to maintain a consistent listing order.

---

## Providers

### Query: Count SRM Providers

/* Count the total number of distinct storage providers configured in SRM. | Entities: `Orion.SRM.Providers` */

```sql
SELECT
    COUNT(DISTINCT ProviderID) AS [Providers Count]
FROM
    Orion.SRM.Providers;
```

**Key points**:
- Providers represent the connection configurations SRM uses to communicate with storage arrays (e.g., SMI-S, NetApp ONTAP API, Pure REST).
- Each storage array typically maps to one provider, but some arrays may have multiple providers for different access methods.
- A zero count means no storage arrays have been onboarded into SRM.

---



