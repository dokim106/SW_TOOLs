# SWQL SRM Entity Schema Reference

> Detailed schema reference for SolarWinds Storage Resource Monitor (SRM) SWQL entities.
> Covers storage arrays, providers, volumes, LUNs, storage pools, vServers, and file shares.
> The SWQL namespace uses `Orion.SRM.*` for SRM entities.

---

## Orion.SRM.StorageArrays (SWQL)

Represents a storage array (SAN/NAS appliance) discovered and monitored by SRM.

### SWQL Properties

| Property | Type | Description |
|----------|------|-------------|
| ArrayID | Int32 | Primary key. Unique storage array identifier |
| Name | String | Storage array display name |
| DisplayName | String | Full display name |
| Vendor | String | Array vendor (NetApp, Dell EMC, Pure Storage, HPE, etc.) |
| Model | String | Array hardware model |
| SerialNumber | String | Array serial number |
| FirmwareVersion | String | Current firmware version |
| Status | Int32 | Monitoring status code |
| StatusDescription | String | Human-readable status |
| TotalCapacity | Int64 | Total raw capacity in bytes |
| UsedCapacity | Int64 | Used capacity in bytes |
| FreeCapacity | Int64 | Free capacity in bytes |
| PercentUsed | Double | Capacity utilization percentage |
| VolumeCount | Int32 | Number of volumes on this array |
| LUNCount | Int32 | Number of LUNs presented |
| PoolCount | Int32 | Number of storage pools |
| ProviderID | Int32 | FK to Orion.SRM.Providers |
| IPAddress | String | Management IP address |
| IOPSRead | Double | Current read IOPS |
| IOPSWrite | Double | Current write IOPS |
| Latency | Double | Current average latency in ms |
| Throughput | Double | Current throughput in bytes/sec |

### SWQL Navigation Properties

- **Provider** navigates to Orion.SRM.Providers -- the storage provider managing this array
- **Volumes** navigates to Orion.SRM.Volumes (collection) -- volumes on this array
- **LUNs** navigates to Orion.SRM.LUNs (collection) -- LUNs presented by this array
- **Pools** navigates to Orion.SRM.Pools (collection) -- storage pools

### Example SWQL Queries

**Storage array capacity overview:**

```sql
SELECT
    sa.Name AS [Array],
    sa.Vendor,
    sa.Model,
    sa.TotalCapacity / 1099511627776 AS [Total TB],
    sa.UsedCapacity / 1099511627776 AS [Used TB],
    sa.FreeCapacity / 1099511627776 AS [Free TB],
    sa.PercentUsed AS [Used %],
    sa.VolumeCount AS [Volumes],
    sa.StatusDescription AS [Status]
FROM Orion.SRM.StorageArrays AS sa
ORDER BY sa.PercentUsed DESC
```

**Arrays with high latency:**

```sql
SELECT
    sa.Name AS [Array],
    sa.Vendor,
    sa.Latency AS [Latency ms],
    sa.IOPSRead AS [Read IOPS],
    sa.IOPSWrite AS [Write IOPS],
    sa.Throughput / 1048576 AS [Throughput MB/s]
FROM Orion.SRM.StorageArrays AS sa
WHERE sa.Latency > 10
ORDER BY sa.Latency DESC
```

---

## Orion.SRM.Providers (SWQL)

Represents a storage provider (management connection) used by SRM to communicate with storage arrays.

### SWQL Properties

| Property | Type | Description |
|----------|------|-------------|
| ProviderID | Int32 | Primary key. Unique provider identifier |
| Name | String | Provider display name |
| Type | String | Provider type (SMI-S, REST API, SNMP, vendor-specific) |
| Status | Int32 | Connection status code |
| StatusDescription | String | Human-readable status |
| Hostname | String | Provider hostname or IP |
| Port | Int32 | Connection port |
| Protocol | String | Communication protocol (HTTPS, HTTP, etc.) |
| Version | String | Provider/API version |
| ArrayCount | Int32 | Number of arrays managed through this provider |
| LastPoll | DateTime | Last successful poll time |
| PollInterval | Int32 | Poll interval in minutes |

### SWQL Navigation Properties

- **Arrays** navigates to Orion.SRM.StorageArrays (collection) -- arrays managed by this provider

### Example SWQL Queries

**All storage providers with connection status:**

```sql
SELECT
    p.Name AS [Provider],
    p.Type AS [Type],
    p.Hostname,
    p.Port,
    p.StatusDescription AS [Status],
    p.ArrayCount AS [Arrays],
    ToLocal(p.LastPoll) AS [Last Poll],
    p.PollInterval AS [Interval min]
FROM Orion.SRM.Providers AS p
ORDER BY p.Name
```

**Providers with stale data (last poll more than 2x interval):**

```sql
SELECT
    p.Name AS [Provider],
    p.Type,
    p.StatusDescription AS [Status],
    ToLocal(p.LastPoll) AS [Last Poll],
    MINUTEDIFF(p.LastPoll, GETUTCDATE()) AS [Minutes Ago],
    p.PollInterval AS [Expected Interval]
FROM Orion.SRM.Providers AS p
WHERE MINUTEDIFF(p.LastPoll, GETUTCDATE()) > (p.PollInterval * 2)
ORDER BY [Minutes Ago] DESC
```

---

## Orion.SRM.Volumes (SWQL)

Represents a storage volume (aggregate, FlexVol, virtual disk, etc.) on a storage array.

### SWQL Properties

| Property | Type | Description |
|----------|------|-------------|
| VolumeID | Int32 | Primary key. Unique volume identifier |
| ArrayID | Int32 | FK to Orion.SRM.StorageArrays |
| Name | String | Volume name |
| DisplayName | String | Full display name |
| Capacity | Int64 | Total volume capacity in bytes |
| UsedSpace | Int64 | Used space in bytes |
| FreeSpace | Int64 | Available free space in bytes |
| PercentUsed | Double | Utilization percentage |
| Status | Int32 | Volume status code |
| StatusDescription | String | Human-readable status |
| VolumeType | String | Volume type (Thick, Thin, Aggregate, FlexVol, etc.) |
| IsOnline | Boolean | Whether the volume is online |
| IOPSRead | Double | Current read IOPS |
| IOPSWrite | Double | Current write IOPS |
| Latency | Double | Current average latency in ms |
| PoolID | Int32 | FK to Orion.SRM.Pools |
| SnapshotReserve | Int64 | Snapshot reserve space in bytes |
| SnapshotUsed | Int64 | Snapshot space consumed in bytes |
| DeduplicationRatio | Double | Deduplication savings ratio |
| CompressionRatio | Double | Compression savings ratio |

### SWQL Navigation Properties

- **Array** navigates to Orion.SRM.StorageArrays -- parent array
- **Pool** navigates to Orion.SRM.Pools -- parent storage pool
- **LUNs** navigates to Orion.SRM.LUNs (collection) -- LUNs in this volume

### Example SWQL Queries

**Volumes nearing capacity:**

```sql
SELECT
    v.Name AS [Volume],
    v.Array.Name AS [Array],
    v.VolumeType AS [Type],
    v.Capacity / 1099511627776 AS [Capacity TB],
    v.UsedSpace / 1099511627776 AS [Used TB],
    v.PercentUsed AS [Used %],
    v.StatusDescription AS [Status]
FROM Orion.SRM.Volumes AS v
WHERE v.PercentUsed > 85
  AND v.IsOnline = true
ORDER BY v.PercentUsed DESC
```

**Volume performance metrics:**

```sql
SELECT
    v.Name AS [Volume],
    v.Array.Name AS [Array],
    v.IOPSRead AS [Read IOPS],
    v.IOPSWrite AS [Write IOPS],
    v.Latency AS [Latency ms]
FROM Orion.SRM.Volumes AS v
WHERE v.IsOnline = true
  AND v.Latency > 5
ORDER BY v.Latency DESC
```

**Volumes with deduplication/compression savings:**

```sql
SELECT
    v.Name AS [Volume],
    v.Array.Name AS [Array],
    v.Capacity / 1073741824 AS [Capacity GB],
    v.DeduplicationRatio AS [Dedup Ratio],
    v.CompressionRatio AS [Compress Ratio]
FROM Orion.SRM.Volumes AS v
WHERE v.DeduplicationRatio > 1
   OR v.CompressionRatio > 1
ORDER BY v.DeduplicationRatio DESC
```

---

## Orion.SRM.LUNs (SWQL)

Represents a Logical Unit Number (LUN) presented by a storage array to hosts.

### SWQL Properties

| Property | Type | Description |
|----------|------|-------------|
| LUNID | Int32 | Primary key. Unique LUN identifier |
| ArrayID | Int32 | FK to Orion.SRM.StorageArrays |
| VolumeID | Int32 | FK to Orion.SRM.Volumes |
| Name | String | LUN name or identifier |
| DisplayName | String | Full display name |
| Capacity | Int64 | LUN capacity in bytes |
| UsedSpace | Int64 | Used space in bytes |
| PercentUsed | Double | Utilization percentage |
| Status | Int32 | LUN status code |
| StatusDescription | String | Human-readable status |
| LUNNumber | Int32 | LUN number as presented to hosts |
| IsOnline | Boolean | Whether the LUN is online |
| IsThinProvisioned | Boolean | Whether thin provisioning is enabled |
| IOPSRead | Double | Current read IOPS |
| IOPSWrite | Double | Current write IOPS |
| Latency | Double | Current average latency in ms |
| HostMapping | String | Host or host group mapped to this LUN |

### SWQL Navigation Properties

- **Array** navigates to Orion.SRM.StorageArrays -- parent array
- **Volume** navigates to Orion.SRM.Volumes -- parent volume

### Example SWQL Queries

**LUN inventory with capacity and performance:**

```sql
SELECT
    l.Name AS [LUN],
    l.Array.Name AS [Array],
    l.Capacity / 1073741824 AS [Capacity GB],
    l.PercentUsed AS [Used %],
    l.IsThinProvisioned AS [Thin],
    l.IOPSRead AS [Read IOPS],
    l.IOPSWrite AS [Write IOPS],
    l.Latency AS [Latency ms],
    l.HostMapping AS [Mapped To]
FROM Orion.SRM.LUNs AS l
WHERE l.IsOnline = true
ORDER BY l.Latency DESC
```

---

## Orion.SRM.Pools (SWQL)

Represents a storage pool (RAID group, disk pool, aggregate) on a storage array.

### SWQL Properties

| Property | Type | Description |
|----------|------|-------------|
| PoolID | Int32 | Primary key. Unique pool identifier |
| ArrayID | Int32 | FK to Orion.SRM.StorageArrays |
| Name | String | Pool name |
| DisplayName | String | Full display name |
| Capacity | Int64 | Total pool capacity in bytes |
| UsedSpace | Int64 | Used space in bytes |
| FreeSpace | Int64 | Available free space in bytes |
| PercentUsed | Double | Utilization percentage |
| Status | Int32 | Pool status code |
| StatusDescription | String | Human-readable status |
| RaidLevel | String | RAID level (RAID1, RAID5, RAID6, RAID-DP, etc.) |
| DiskCount | Int32 | Number of disks in the pool |
| DiskType | String | Disk media type (SSD, SAS, NL-SAS, etc.) |
| VolumeCount | Int32 | Number of volumes in this pool |

### SWQL Navigation Properties

- **Array** navigates to Orion.SRM.StorageArrays -- parent array
- **Volumes** navigates to Orion.SRM.Volumes (collection) -- volumes in this pool

### Example SWQL Queries

**Storage pool capacity and configuration:**

```sql
SELECT
    sp.Name AS [Pool],
    sp.Array.Name AS [Array],
    sp.RaidLevel AS [RAID],
    sp.DiskType AS [Media],
    sp.DiskCount AS [Disks],
    sp.Capacity / 1099511627776 AS [Capacity TB],
    sp.PercentUsed AS [Used %],
    sp.VolumeCount AS [Volumes],
    sp.StatusDescription AS [Status]
FROM Orion.SRM.Pools AS sp
ORDER BY sp.PercentUsed DESC
```

---

## Orion.SRM.VServers (SWQL)

Represents a storage virtual server (SVM/vFiler) on a storage array, commonly used with NetApp systems.

### SWQL Properties

| Property | Type | Description |
|----------|------|-------------|
| VServerID | Int32 | Primary key. Unique vServer identifier |
| ArrayID | Int32 | FK to Orion.SRM.StorageArrays |
| Name | String | vServer name |
| DisplayName | String | Full display name |
| Status | Int32 | vServer status code |
| StatusDescription | String | Human-readable status |
| VServerType | String | vServer type (Data, Admin, System) |
| VolumeCount | Int32 | Number of volumes in this vServer |
| ShareCount | Int32 | Number of file shares |
| Protocol | String | Supported protocols (NFS, CIFS, iSCSI, FC) |
| IPAddress | String | Management LIF IP address |

### SWQL Navigation Properties

- **Array** navigates to Orion.SRM.StorageArrays -- parent array
- **FileShares** navigates to Orion.SRM.FileShares (collection) -- shares on this vServer

### Example SWQL Queries

**vServer inventory:**

```sql
SELECT
    vs.Name AS [vServer],
    vs.Array.Name AS [Array],
    vs.VServerType AS [Type],
    vs.Protocol,
    vs.VolumeCount AS [Volumes],
    vs.ShareCount AS [Shares],
    vs.StatusDescription AS [Status]
FROM Orion.SRM.VServers AS vs
ORDER BY vs.Array.Name, vs.Name
```

---

## Orion.SRM.FileShares (SWQL)

Represents a file share (NFS export, CIFS/SMB share) on a storage array or vServer.

### SWQL Properties

| Property | Type | Description |
|----------|------|-------------|
| FileShareID | Int32 | Primary key. Unique file share identifier |
| ArrayID | Int32 | FK to Orion.SRM.StorageArrays |
| VServerID | Int32 | FK to Orion.SRM.VServers |
| Name | String | Share name |
| DisplayName | String | Full display name |
| SharePath | String | Export path or UNC path |
| Protocol | String | Share protocol (NFS, CIFS) |
| Capacity | Int64 | Share capacity in bytes |
| UsedSpace | Int64 | Used space in bytes |
| PercentUsed | Double | Utilization percentage |
| Status | Int32 | Share status code |
| StatusDescription | String | Human-readable status |
| VolumeID | Int32 | FK to Orion.SRM.Volumes |
| IsOnline | Boolean | Whether the share is accessible |

### SWQL Navigation Properties

- **Array** navigates to Orion.SRM.StorageArrays
- **VServer** navigates to Orion.SRM.VServers
- **Volume** navigates to Orion.SRM.Volumes

### Example SWQL Queries

**File shares with utilization:**

```sql
SELECT
    fs.Name AS [Share],
    fs.SharePath AS [Path],
    fs.Protocol,
    fs.Array.Name AS [Array],
    fs.Capacity / 1073741824 AS [Capacity GB],
    fs.UsedSpace / 1073741824 AS [Used GB],
    fs.PercentUsed AS [Used %],
    fs.StatusDescription AS [Status]
FROM Orion.SRM.FileShares AS fs
WHERE fs.IsOnline = true
ORDER BY fs.PercentUsed DESC
```

**Shares nearing capacity across all arrays:**

```sql
SELECT
    fs.Name AS [Share],
    fs.Array.Name AS [Array],
    fs.VServer.Name AS [vServer],
    fs.Protocol,
    fs.PercentUsed AS [Used %],
    (fs.Capacity - fs.UsedSpace) / 1073741824 AS [Free GB]
FROM Orion.SRM.FileShares AS fs
WHERE fs.PercentUsed > 80
  AND fs.IsOnline = true
ORDER BY fs.PercentUsed DESC
```

---

## SWQL SRM Schema Discovery

Use these metadata queries to explore available SRM entities and properties at runtime:

```sql
-- List all SRM entities
SELECT FullName, EntityName
FROM Metadata.Entity
WHERE FullName LIKE 'Orion.SRM.%'
ORDER BY EntityName

-- List properties of a specific SRM entity
SELECT Name, Type, IsNavigable, IsKey
FROM Metadata.Property
WHERE EntityName = 'Orion.SRM.StorageArrays'
```
