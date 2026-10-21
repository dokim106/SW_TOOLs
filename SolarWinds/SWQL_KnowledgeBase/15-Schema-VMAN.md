# SWQL VMAN Entity Schema Reference

> Detailed schema reference for SolarWinds Virtualization Manager (VMAN) SWQL entities.
> Covers virtual machines, hypervisor hosts, datastores, clusters, disk files, vCenters, snapshots, and capacity recommendations.

---

## Orion.VIM.VirtualMachines (SWQL)

Represents a monitored virtual machine. Stores identity, resource allocation, power state, and performance metrics.

### SWQL Properties

| Property | Type | Description |
|----------|------|-------------|
| VirtualMachineID | Int32 | Primary key. Unique VM identifier |
| NodeID | Int32 | FK to Orion.Nodes. Corresponding Orion node (if polled) |
| Name | String | VM display name |
| DisplayName | String | Full display name |
| CPUCount | Int32 | Number of virtual CPUs assigned |
| MemoryMB | Int64 | Memory allocated in megabytes |
| Status | Int32 | Current monitoring status code |
| StatusDescription | String | Human-readable status label |
| PowerState | String | Power state (poweredOn, poweredOff, suspended) |
| GuestState | String | Guest OS running state |
| HostID | Int32 | FK to Orion.VIM.Hosts. Hosting hypervisor |
| ClusterID | Int32 | FK to Orion.VIM.Clusters |
| VMToolsStatus | String | VMware Tools status (running, notRunning, notInstalled) |
| GuestOS | String | Guest operating system name |
| IPAddress | String | Primary IP address of the VM |
| CPULoad | Double | Current CPU utilization percentage |
| MemoryUsage | Double | Current memory utilization percentage |
| NICCount | Int32 | Number of virtual NICs |
| DiskCount | Int32 | Number of virtual disks |
| SnapshotCount | Int32 | Number of active snapshots |
| TotalDiskSpaceGB | Double | Total provisioned disk space in GB |
| UsedDiskSpaceGB | Double | Actual disk space consumed in GB |
| BalloonMemloadPercent | Double | Memory ballooning percentage (VMware) |
| Annotation | String | VM notes/annotation field |
| UUID | String | VM unique identifier (hypervisor-assigned) |
| DatastoreID | Int32 | FK to Orion.VIM.Datastores. Primary datastore |

### SWQL Navigation Properties

- **Node** navigates to Orion.Nodes -- the Orion node object for this VM
- **Host** navigates to Orion.VIM.Hosts -- the hypervisor host running this VM
- **Cluster** navigates to Orion.VIM.Clusters -- the cluster containing the host
- **CpuReadyThreshold** navigates to threshold sub-properties for CPU Ready
- **Snapshots** navigates to Orion.VIM.Snapshots (collection) -- VM snapshots
- **DiskFiles** navigates to Orion.VIM.DiskFiles (collection) -- virtual disk files

### Example SWQL Queries

**Powered-on VMs with high CPU load:**

```sql
SELECT
    vm.Name AS [VM],
    vm.Host.Name AS [Host],
    vm.CPUCount AS [vCPUs],
    vm.CPULoad AS [CPU %],
    vm.MemoryMB / 1024 AS [Memory GB],
    vm.MemoryUsage AS [Mem %],
    vm.GuestOS
FROM Orion.VIM.VirtualMachines AS vm
WHERE vm.PowerState = 'poweredOn'
  AND vm.CPULoad > 80
ORDER BY vm.CPULoad DESC
```

**VMs with snapshots older than 7 days (snapshot sprawl):**

```sql
SELECT
    vm.Name AS [VM],
    vm.Host.Name AS [Host],
    vm.SnapshotCount AS [Snapshots],
    vm.TotalDiskSpaceGB AS [Provisioned GB],
    vm.UsedDiskSpaceGB AS [Used GB]
FROM Orion.VIM.VirtualMachines AS vm
WHERE vm.SnapshotCount > 0
  AND vm.PowerState = 'poweredOn'
ORDER BY vm.SnapshotCount DESC
```

**Powered-off VMs consuming datastore space:**

```sql
SELECT
    vm.Name AS [VM],
    vm.GuestOS,
    vm.TotalDiskSpaceGB AS [Provisioned GB],
    vm.UsedDiskSpaceGB AS [Used GB],
    vm.Host.Name AS [Last Host]
FROM Orion.VIM.VirtualMachines AS vm
WHERE vm.PowerState = 'poweredOff'
  AND vm.UsedDiskSpaceGB > 50
ORDER BY vm.UsedDiskSpaceGB DESC
```

---

## Orion.VIM.Hosts (SWQL)

Represents a hypervisor host (ESXi, Hyper-V, etc.) monitored by VMAN.

### SWQL Properties

| Property | Type | Description |
|----------|------|-------------|
| HostID | Int32 | Primary key. Unique host identifier |
| NodeID | Int32 | FK to Orion.Nodes. Corresponding Orion node |
| Name | String | Hostname |
| DisplayName | String | Full display name |
| CPUCount | Int32 | Number of physical CPU sockets |
| CPUCoreCount | Int32 | Total number of CPU cores |
| MemoryGB | Double | Total physical memory in GB |
| VMCount | Int32 | Number of VMs currently on this host |
| Status | Int32 | Monitoring status code |
| StatusDescription | String | Human-readable status |
| CPULoad | Double | Current CPU utilization percentage |
| MemoryUsage | Double | Current memory utilization percentage |
| Model | String | Server hardware model |
| Vendor | String | Server vendor (Dell, HP, etc.) |
| HypervisorType | String | Hypervisor platform (VMware, Hyper-V, etc.) |
| HypervisorVersion | String | Hypervisor software version |
| ClusterID | Int32 | FK to Orion.VIM.Clusters |
| DatacenterID | Int32 | FK to datacenter entity |
| NICCount | Int32 | Number of physical NICs |
| DatastoreCount | Int32 | Number of connected datastores |
| PowerState | String | Host power state |

### SWQL Navigation Properties

- **Node** navigates to Orion.Nodes -- the Orion node for this host
- **Cluster** navigates to Orion.VIM.Clusters -- parent cluster
- **VirtualMachines** navigates to Orion.VIM.VirtualMachines (collection) -- VMs on this host
- **Datastores** navigates to Orion.VIM.Datastores (collection) -- connected datastores

### Example SWQL Queries

**Host capacity summary with VM density:**

```sql
SELECT
    h.Name AS [Host],
    h.CPUCoreCount AS [Cores],
    h.MemoryGB AS [RAM GB],
    h.VMCount AS [VM Count],
    h.CPULoad AS [CPU %],
    h.MemoryUsage AS [Mem %],
    h.HypervisorVersion AS [Version]
FROM Orion.VIM.Hosts AS h
ORDER BY h.VMCount DESC
```

**Hosts with memory overcommit (total VM memory exceeds physical):**

```sql
SELECT
    h.Name AS [Host],
    h.MemoryGB AS [Physical GB],
    SUM(vm.MemoryMB) / 1024 AS [Allocated VM GB],
    (SUM(vm.MemoryMB) / 1024) / h.MemoryGB AS [Overcommit Ratio]
FROM Orion.VIM.Hosts AS h
JOIN Orion.VIM.VirtualMachines AS vm ON vm.HostID = h.HostID
WHERE vm.PowerState = 'poweredOn'
GROUP BY h.Name, h.MemoryGB
HAVING SUM(vm.MemoryMB) / 1024 > h.MemoryGB
ORDER BY [Overcommit Ratio] DESC
```

---

## Orion.VIM.Datastores (SWQL)

Represents a storage datastore accessible by hypervisor hosts.

### SWQL Properties

| Property | Type | Description |
|----------|------|-------------|
| DatastoreID | Int32 | Primary key. Unique datastore identifier |
| Name | String | Datastore name |
| DisplayName | String | Full display name |
| Capacity | Int64 | Total capacity in bytes |
| FreeSpace | Int64 | Available free space in bytes |
| Type | String | Datastore type (VMFS, NFS, vSAN, etc.) |
| Status | Int32 | Monitoring status code |
| PercentFree | Double | Percentage of capacity that is free |
| PercentUsed | Double | Percentage of capacity that is used |
| ProvisionedSpace | Int64 | Total provisioned space (may exceed capacity with thin provisioning) |
| VMCount | Int32 | Number of VMs using this datastore |
| HostCount | Int32 | Number of hosts connected to this datastore |
| Accessible | Boolean | Whether the datastore is currently accessible |
| Url | String | Datastore URL/path |

### SWQL Navigation Properties

- **Hosts** navigates to Orion.VIM.Hosts (collection) -- connected hypervisor hosts
- **VirtualMachines** navigates to Orion.VIM.VirtualMachines (collection) -- VMs stored here
- **DiskFiles** navigates to Orion.VIM.DiskFiles (collection) -- disk files on this datastore

### Example SWQL Queries

**Datastores with low free space:**

```sql
SELECT
    ds.Name AS [Datastore],
    ds.Type,
    ds.Capacity / 1073741824 AS [Capacity GB],
    ds.FreeSpace / 1073741824 AS [Free GB],
    ds.PercentUsed AS [Used %],
    ds.VMCount AS [VM Count]
FROM Orion.VIM.Datastores AS ds
WHERE ds.PercentUsed > 85
ORDER BY ds.PercentUsed DESC
```

**Datastores with thin provisioning overcommit:**

```sql
SELECT
    ds.Name AS [Datastore],
    ds.Capacity / 1073741824 AS [Capacity GB],
    ds.ProvisionedSpace / 1073741824 AS [Provisioned GB],
    (ds.ProvisionedSpace * 100) / ds.Capacity AS [Provision %]
FROM Orion.VIM.Datastores AS ds
WHERE ds.ProvisionedSpace > ds.Capacity
ORDER BY [Provision %] DESC
```

---

## Orion.VIM.Clusters (SWQL)

Represents a virtual machine cluster (e.g., VMware HA/DRS cluster).

### SWQL Properties

| Property | Type | Description |
|----------|------|-------------|
| ClusterID | Int32 | Primary key. Unique cluster identifier |
| Name | String | Cluster name |
| DisplayName | String | Full display name |
| TotalCPU | Int64 | Total CPU capacity in MHz |
| TotalMemory | Int64 | Total memory in bytes |
| TotalHosts | Int32 | Number of hosts in the cluster |
| TotalVMs | Int32 | Number of VMs in the cluster |
| Status | Int32 | Monitoring status code |
| DRSEnabled | Boolean | Whether DRS is enabled |
| HAEnabled | Boolean | Whether HA is enabled |
| OverallCPUUsage | Int64 | Current CPU usage in MHz |
| OverallMemoryUsage | Int64 | Current memory usage in bytes |
| DatacenterID | Int32 | FK to the parent datacenter |

### SWQL Navigation Properties

- **Hosts** navigates to Orion.VIM.Hosts (collection) -- hosts in this cluster
- **VirtualMachines** navigates to Orion.VIM.VirtualMachines (collection) -- VMs in this cluster

### Example SWQL Queries

**Cluster capacity overview:**

```sql
SELECT
    c.Name AS [Cluster],
    c.TotalHosts AS [Hosts],
    c.TotalVMs AS [VMs],
    c.TotalCPU / 1000 AS [Total GHz],
    c.OverallCPUUsage / 1000 AS [Used GHz],
    c.TotalMemory / 1073741824 AS [Total GB],
    c.OverallMemoryUsage / 1073741824 AS [Used GB],
    c.DRSEnabled AS [DRS],
    c.HAEnabled AS [HA]
FROM Orion.VIM.Clusters AS c
ORDER BY c.TotalVMs DESC
```

---

## Orion.VIM.DiskFiles (SWQL)

Represents virtual disk files (VMDKs, VHDs) stored on datastores.

### SWQL Properties

| Property | Type | Description |
|----------|------|-------------|
| DiskFileID | Int32 | Primary key. Unique disk file identifier |
| FileName | String | Disk file name (e.g., vm-flat.vmdk) |
| FileSize | Int64 | Actual disk file size in bytes |
| DatastoreID | Int32 | FK to Orion.VIM.Datastores |
| VirtualMachineID | Int32 | FK to Orion.VIM.VirtualMachines |
| ProvisionedSize | Int64 | Provisioned (maximum) size in bytes |
| DiskType | String | Disk type (Thin, Thick Eager Zero, Thick Lazy Zero) |
| FilePath | String | Full path to the disk file on the datastore |

### SWQL Navigation Properties

- **Datastore** navigates to Orion.VIM.Datastores -- hosting datastore
- **VirtualMachine** navigates to Orion.VIM.VirtualMachines -- owning VM

### Example SWQL Queries

**Largest virtual disk files across all datastores:**

```sql
SELECT TOP 20
    df.FileName,
    df.VirtualMachine.Name AS [VM],
    df.Datastore.Name AS [Datastore],
    df.FileSize / 1073741824 AS [Actual GB],
    df.ProvisionedSize / 1073741824 AS [Provisioned GB],
    df.DiskType
FROM Orion.VIM.DiskFiles AS df
ORDER BY df.FileSize DESC
```

**Orphaned disk files (no associated VM):**

```sql
SELECT
    df.FileName,
    df.FilePath,
    df.Datastore.Name AS [Datastore],
    df.FileSize / 1073741824 AS [Size GB]
FROM Orion.VIM.DiskFiles AS df
WHERE df.VirtualMachineID IS NULL
ORDER BY df.FileSize DESC
```

---

## Orion.VIM.VCenters (SWQL)

Represents vCenter Server instances managed by VMAN.

### SWQL Properties

| Property | Type | Description |
|----------|------|-------------|
| VCenterID | Int32 | Primary key. Unique vCenter identifier |
| Name | String | vCenter hostname or FQDN |
| DisplayName | String | Full display name |
| IPAddress | String | vCenter IP address |
| Version | String | vCenter Server version |
| Build | String | vCenter build number |
| Status | Int32 | Connection/monitoring status |
| TotalHosts | Int32 | Number of hosts managed by this vCenter |
| TotalVMs | Int32 | Number of VMs managed by this vCenter |
| TotalClusters | Int32 | Number of clusters |
| TotalDatastores | Int32 | Number of datastores |

### SWQL Navigation Properties

- **Clusters** navigates to Orion.VIM.Clusters (collection)
- **Hosts** navigates to Orion.VIM.Hosts (collection)

### Example SWQL Queries

**vCenter inventory summary:**

```sql
SELECT
    vc.Name AS [vCenter],
    vc.Version,
    vc.TotalHosts AS [Hosts],
    vc.TotalVMs AS [VMs],
    vc.TotalClusters AS [Clusters],
    vc.TotalDatastores AS [Datastores]
FROM Orion.VIM.VCenters AS vc
ORDER BY vc.TotalVMs DESC
```

---

## Orion.VIM.Snapshots (SWQL)

Represents VM snapshots tracked by VMAN.

### SWQL Properties

| Property | Type | Description |
|----------|------|-------------|
| SnapshotID | Int32 | Primary key. Unique snapshot identifier |
| VirtualMachineID | Int32 | FK to Orion.VIM.VirtualMachines |
| Name | String | Snapshot name |
| Description | String | Snapshot description |
| CreateDate | DateTime | When the snapshot was created |
| SizeGB | Double | Snapshot size in GB |
| IsCurrent | Boolean | Whether this is the current active snapshot |
| ParentSnapshotID | Int32 | FK to parent snapshot (for snapshot trees) |

### SWQL Navigation Properties

- **VirtualMachine** navigates to Orion.VIM.VirtualMachines -- the owning VM

### Example SWQL Queries

**Snapshots older than 3 days (snapshot sprawl detection):**

```sql
SELECT
    sn.Name AS [Snapshot],
    sn.VirtualMachine.Name AS [VM],
    sn.VirtualMachine.Host.Name AS [Host],
    sn.SizeGB AS [Size GB],
    ToLocal(sn.CreateDate) AS [Created],
    DAYDIFF(sn.CreateDate, GETUTCDATE()) AS [Age Days]
FROM Orion.VIM.Snapshots AS sn
WHERE DAYDIFF(sn.CreateDate, GETUTCDATE()) > 3
ORDER BY [Age Days] DESC
```

---

## Orion.VIM.Recommendations (SWQL)

Stores capacity and optimization recommendations generated by VMAN analysis.

### SWQL Properties

| Property | Type | Description |
|----------|------|-------------|
| RecommendationID | Int32 | Primary key |
| Title | String | Recommendation title |
| Description | String | Detailed recommendation text |
| Category | String | Category (Rightsizing, Sprawl, Performance, etc.) |
| Severity | String | Severity level (Info, Warning, Critical) |
| EntityType | String | Type of entity this recommendation applies to |
| EntityID | Int32 | ID of the target entity |
| CreatedDate | DateTime | When the recommendation was generated |
| Status | String | Current status (Open, Dismissed, Applied) |

### Example SWQL Queries

**Open recommendations by category:**

```sql
SELECT
    r.Category,
    r.Severity,
    COUNT(*) AS [Count]
FROM Orion.VIM.Recommendations AS r
WHERE r.Status = 'Open'
GROUP BY r.Category, r.Severity
ORDER BY r.Category, r.Severity
```

**Top recommendations for oversized VMs:**

```sql
SELECT
    r.Title,
    r.Description,
    r.Severity,
    ToLocal(r.CreatedDate) AS [Created]
FROM Orion.VIM.Recommendations AS r
WHERE r.Category = 'Rightsizing'
  AND r.Status = 'Open'
ORDER BY r.CreatedDate DESC
```

---

## SWQL VMAN Schema Discovery

Use these metadata queries to explore available VMAN entities and properties at runtime:

```sql
-- List all VIM entities
SELECT FullName, EntityName
FROM Metadata.Entity
WHERE FullName LIKE 'Orion.VIM.%'
ORDER BY EntityName

-- List properties of a specific VMAN entity
SELECT Name, Type, IsNavigable, IsKey
FROM Metadata.Property
WHERE EntityName = 'Orion.VIM.VirtualMachines'
```
