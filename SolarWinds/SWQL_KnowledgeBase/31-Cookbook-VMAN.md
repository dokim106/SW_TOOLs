# SWQL VMAN (Virtualization Manager) Query Cookbook

> Consolidated SWQL queries for SolarWinds Virtualization Manager (VMAN).
> Covers VM performance, capacity planning, chargeback, cloud monitoring, Hyper-V, orphaned VMDKs, recommendations, and VMware node management.

---

## Ballooning

### Query: Balloon Memory VMs Count

/* Count the total number of powered-on VMs experiencing memory ballooning above 1%. | Entities: `Orion.VIM.VirtualMachines` */

```sql
SELECT
    COUNT(vm.[DisplayName]) AS [Total]
FROM
    Orion.VIM.VirtualMachines AS vm
WHERE
    vm.[PowerState] = 'poweredOn'
    AND vm.[BalloonMemloadPercent] > 1;
```

**Key points**:
- Filters only powered-on VMs to avoid false positives from offline machines.
- A balloon memory load percent threshold of 1% indicates the hypervisor is actively reclaiming memory from the guest OS.
- High ballooning values suggest memory overcommitment on the host.

---

## CPU Ready

### Query: VM CPU Ready Threshold Summary

/* Count VMs grouped by CPU Ready thresholds -- those above 0ms, in warning state, and in critical state. | Entities: `Orion.VIM.VirtualMachines` (with `CpuReadyThreshold` navigation property) */

```sql
SELECT
    COUNT(CASE WHEN E0.[CpuReadyThreshold].[CurrentValue] > 0 THEN 1 END) AS [CPU Ready > 0ms],
    COUNT(CASE WHEN E0.[CpuReadyThreshold].[IsLevel1State] = 1 THEN 1 END) AS [CPU Ready Warning],
    COUNT(CASE WHEN E0.[CpuReadyThreshold].[IsLevel2State] = 1 THEN 1 END) AS [CPU Ready Critical]
FROM
    Orion.VIM.VirtualMachines AS E0
WHERE
    E0.[CpuReadyThreshold].[CurrentValue] > 0
    OR E0.[CpuReadyThreshold].[IsLevel1State] = 1
    OR E0.[CpuReadyThreshold].[IsLevel2State] = 1;
```

**Key points**:
- Uses SWQL navigation properties (`CpuReadyThreshold.CurrentValue`, `.IsLevel1State`, `.IsLevel2State`) to access threshold sub-properties.
- CPU Ready time measures how long a VM waits for physical CPU resources; high values indicate CPU contention.
- Level 1 = Warning, Level 2 = Critical based on VMAN threshold configuration.

---

## Capacity Planning

### Query: Capacity Planning Reports Count

/* Count the total number of capacity planning reports that have been generated. | Entities: `Orion.VIM.CapacityPlanning.ReportResults` */

```sql
SELECT
    COUNT(ID) AS [Capacity Reports Created]
FROM
    Orion.VIM.CapacityPlanning.ReportResults;
```

**Key points**:
- Simple count to verify capacity planning reports exist and are being generated.
- Useful for auditing whether the capacity planning module is actively in use.

---

## Chargeback

### Query: Chargeback Reports Count

/* Count the total number of chargeback reports created in VMAN. | Entities: `Orion.VIM.ChargebackReports` */

```sql
SELECT
    COUNT(Name) AS [Chargeback Reports Created]
FROM
    Orion.VIM.ChargebackReports;
```

**Key points**:
- Chargeback reports allocate virtualization costs to business units or departments.
- A zero count may indicate the chargeback feature is not configured or in use.

---

## Cloud Infrastructure Monitoring

### Query: Cloud VMs Monitored by Provider

/* Count the number of cloud-hosted VMs monitored, grouped by cloud provider. | Entities: `Orion.Cloud.Instances` */

```sql
SELECT
    Provider,
    COUNT(VirtualMachineID) AS [VMs Monitored]
FROM
    Orion.Cloud.Instances
GROUP BY
    Provider
ORDER BY
    Provider;
```

**Key points**:
- Groups cloud instances by provider (e.g., AWS, Azure, GCP).
- Uses `VirtualMachineID` to count monitored VM instances per provider.
- Useful for multi-cloud visibility and license tracking.

---

## Hyper-V Nodes

### Query: Hyper-V Hosts Inventory

/* Retrieve Hyper-V host details including hostname, IP, product version, and whether the host is managed as an Orion node. | Entities: `Orion.VIM.Hosts` */

```sql
SELECT
    HostName,
    IPAddress,
    VMwareProductName,
    VMwareProductVersion,
    CASE WHEN NodeID IS NOT NULL THEN 'Yes' ELSE 'No' END AS [Managed as Node]
FROM
    Orion.VIM.Hosts
WHERE
    VMwareProductName LIKE '%hyper-v%'
ORDER BY
    VMwareProductName;
```

**Key points**:
- Despite the column name `VMwareProductName`, the `Orion.VIM.Hosts` entity covers all hypervisor types including Hyper-V.
- The `LIKE '%hyper-v%'` filter isolates Hyper-V hosts from VMware hosts.
- The `Managed as Node` column indicates whether the host is also monitored as a standard Orion node (NodeID is not null).

---

## Orphaned VMDKs

### Query: Orphaned VMDK File Count

/* Count the number of orphaned (unattached) VMDK disk files across all datastores. | Entities: `Orion.VIM.DiskFiles` */

```sql
SELECT
    COUNT(CASE WHEN Orphaned = 'True' THEN 1 END) AS [Orphaned VMDK Count]
FROM
    Orion.VIM.DiskFiles;
```

**Key points**:
- Orphaned VMDKs are virtual disk files not associated with any VM, consuming datastore space unnecessarily.
- Regular monitoring helps reclaim wasted storage.
- The `Orphaned` property is a string field (`'True'`/`'False'`), not a boolean.

---

## Recommendation Policies

### Query: Active Recommendations by VM Impact

/* List active VMAN recommendations with their category and count of affected VMs. | Entities: `Orion.VIM.Recommendations`, `Orion.Recommendations.Actions` */

```sql
SELECT
    r.Name,
    r.Strategy.name AS [Category],
    COUNT(r.RecommendationID) AS [Number of VMs Affected]
FROM
    Orion.VIM.Recommendations AS r
JOIN
    Orion.Recommendations.Actions AS a
    ON r.RecommendationID = a.RecommendationID
WHERE
    a.Primary = 'True'
    AND r.Status = 'Active'
GROUP BY
    r.Name,
    r.Strategy.name
ORDER BY
    r.Name,
    [Category],
    [Number of VMs Affected] ASC;
```

**Key points**:
- Joins recommendations with their primary actions to get actionable results.
- Filters for `Primary = 'True'` to avoid counting secondary/alternative actions.
- `r.Strategy.name` uses SWQL navigation property to get the recommendation category (e.g., right-sizing, consolidation).
- Only active recommendations are included; dismissed or completed ones are excluded.

---

## VMware Nodes

### Query: VM Management Status Summary

/* Summarize VMs by whether they are managed as Orion nodes, showing managed count, unmanaged count, and total. | Entities: `Orion.VIM.VirtualMachines` */

```sql
SELECT
    SUM(CASE WHEN vm.[NodeID] IS NOT NULL THEN 1 ELSE 0 END) AS [Managed as Node],
    SUM(CASE WHEN vm.[NodeID] IS NULL THEN 1 ELSE 0 END) AS [Not Managed as Node],
    COUNT(*) AS [Total VMs]
FROM
    Orion.VIM.VirtualMachines AS vm;
```

**Key points**:
- A VM with a non-null `NodeID` is also monitored as a standard Orion node (with polling, alerts, etc.).
- Useful for identifying VMs that might benefit from full Orion node monitoring or for license reconciliation.
- Returns a single summary row with three columns.

---



