# SWQL VNQM (VoIP & Network Quality Manager) Query Cookbook

> Consolidated SWQL queries for SolarWinds VoIP & Network Quality Manager (VNQM).
> Covers CDR reception, Call Manager inventory, IP SLA operations, phone registration, site definitions, and VoIP gateways.
>
> **Note**: Many VNQM queries should be verified on a live system with active VoIP data to confirm results.

---

## CDR Reception

### Query: CDR Records Received Count

/* Count the total number of Call Detail Records (CDRs) received by VNQM. | Entities: `Orion.IpSla.CDRDetails` */

```sql
SELECT
    COUNT(ID) AS [CDR Received]
FROM
    Orion.IpSla.CDRDetails;
```

**Key points**:
- CDRs contain detailed information about individual VoIP calls (source, destination, duration, quality metrics).
- A zero count may indicate CDR forwarding is not configured on the call manager or that VNQM is not receiving data.
- Should be verified on a live system with active call data.

---

## Call Manager Type

### Query: Call Manager Monitoring Type Details

/* Retrieve Call Manager details including caption, CCM name, cluster, version, and monitoring type description. | Entities: `Orion.IpSla.CCMMonitoring` (with `MonitoringType` navigation property) */

```sql
SELECT
    cm.Caption AS [Caption],
    cm.CcmName AS [CCM Name],
    cm.ClusterName AS [Cluster Name],
    cm.Version AS [Version],
    cm.MonitoringType.Description AS [Monitoring Type]
FROM
    Orion.IpSla.CCMMonitoring AS cm;
```

**Key points**:
- Uses `MonitoringType.Description` navigation property to resolve the monitoring type to a human-readable description.
- Displays both individual CCM names and their cluster membership.
- Useful for auditing which call managers are monitored and how they are configured.

---

## Call Managers

### Query: Call Manager Inventory

/* List all monitored Call Managers with their caption, CCM name, cluster, and software version. | Entities: `Orion.IpSla.CCMMonitoring` */

```sql
SELECT
    cm.Caption AS [Caption],
    cm.CcmName AS [CCM Name],
    cm.ClusterName AS [Cluster Name],
    cm.Version AS [Version]
FROM
    Orion.IpSla.CCMMonitoring AS cm;
```

**Key points**:
- Similar to the Call Manager Type query but without the monitoring type; focused on basic inventory.
- Useful for a quick overview of all monitored Cisco Unified Communications Managers.
- Should be verified on a live system with data.

---

## Job Status

### Query: VNQM Job Status

/* Placeholder query for VNQM job status monitoring. | Entities: *To be determined -- requires live system verification* */

```sql
-- TODO: Query requires live system verification to determine
-- applicable entities and fields for VNQM job status monitoring.
```

**Key points**:
- This query requires verification on a live system with VNQM data to determine the correct entity and fields.
- Potential entities to investigate: `Orion.IpSla.Jobs`, `Orion.IpSla.Operations`.

---

## Network Service Assurance (IP SLA Operations)

### Query: IP SLA Operations Summary by Type and Status

/* Summarize IP SLA operations grouped by operation type and status, showing total count for each combination. | Entities: `Orion.IpSla.Operations` (with `OperationStatus` navigation property) */

```sql
SELECT
    o.OperationType AS [Operation Type],
    o.OperationStatus.OperationStatus AS [Operation Status],
    COUNT(*) AS [Total Operations]
FROM
    Orion.IpSla.Operations AS o
GROUP BY
    o.OperationType,
    o.OperationStatus.OperationStatus
ORDER BY
    [Total Operations] DESC;
```

**Key points**:
- IP SLA (Service Level Agreement) operations measure network performance metrics such as jitter, latency, and packet loss.
- Uses navigation property `OperationStatus.OperationStatus` to resolve the status to a readable value.
- Results sorted by total operations descending to highlight the most common operation type/status combinations.
- Operation types may include UDP Jitter, ICMP Echo, HTTP, DNS, etc.

---

## Phones Registered

### Query: Registered Phones per Call Manager

/* Count the number of registered phones grouped by Call Manager name. | Entities: `Orion.IpSla.ConnectedPhonesReport` */

```sql
SELECT
    CallManagerName AS [Call Manager Name],
    COUNT(PhoneName) AS [Phone Count]
FROM
    Orion.IpSla.ConnectedPhonesReport
WHERE
    PhoneName IS NOT NULL
GROUP BY
    CallManagerName
ORDER BY
    [Phone Count] DESC;
```

**Key points**:
- Filters out null phone names to ensure accurate counts of actually registered devices.
- Results ordered by phone count descending to show the busiest call managers first.
- Useful for capacity planning and identifying call manager load distribution.

---

## Sites Defined

### Query: VNQM Site Count

/* Count the total number of sites defined in VNQM. | Entities: `Orion.IpSla.Sites` */

```sql
SELECT
    COUNT(SiteID) AS [Site Count]
FROM
    Orion.IpSla.Sites;
```

**Key points**:
- Sites in VNQM represent physical or logical locations used for VoIP quality correlation.
- A zero count indicates no sites have been configured, which limits location-based VoIP analysis.

---

## VoIP Gateways

### Query: VoIP Gateway Inventory

/* List all VoIP gateways with their display name and device name. | Entities: `Orion.IpSla.VoipGateways` */

```sql
SELECT
    vg.DisplayName AS [Gateway Display Name],
    vg.DeviceName AS [Device Name]
FROM
    Orion.IpSla.VoipGateways AS vg;
```

**Key points**:
- VoIP gateways convert between traditional telephony (PSTN/TDM) and VoIP protocols.
- Monitoring gateways is essential for tracking call quality at network boundaries.
- `DisplayName` is the user-friendly label; `DeviceName` is typically the hostname or FQDN.

---



