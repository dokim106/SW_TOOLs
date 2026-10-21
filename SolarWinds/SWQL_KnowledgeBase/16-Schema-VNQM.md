# SWQL VNQM Entity Schema Reference

> Detailed schema reference for SolarWinds VoIP & Network Quality Manager (VNQM) SWQL entities.
> Covers IP SLA operations, call manager monitoring, VoIP gateways, sites, phones, and operation results.
> The SWQL namespace uses `Orion.IpSla.*` for most VNQM entities.

---

## Orion.IpSla.Operations (SWQL)

Represents an IP SLA or VoIP quality monitoring operation. Each operation defines a source-to-target probe that measures latency, jitter, packet loss, and MOS scores.

### SWQL Properties

| Property | Type | Description |
|----------|------|-------------|
| OperationID | Int32 | Primary key. Unique operation identifier |
| OperationType | String | Operation type (Echo, UdpJitter, IcmpJitter, VoIP, HTTP, etc.) |
| SourceNodeID | Int32 | FK to Orion.Nodes. The node running the IP SLA responder/sender |
| TargetNodeID | Int32 | FK to Orion.Nodes. The target node (may be NULL for external targets) |
| TargetAddress | String | Target IP address or hostname |
| Status | Int32 | Current operation status code |
| StatusDescription | String | Human-readable status |
| Enabled | Boolean | Whether the operation is active |
| OperationName | String | Display name of the operation |
| Frequency | Int32 | Probe frequency in seconds |
| Threshold | Int32 | Latency threshold in milliseconds |
| AvgLatency | Double | Current average latency in ms |
| PacketLoss | Double | Current packet loss percentage |
| Jitter | Double | Current jitter in ms |
| MOS | Double | Current Mean Opinion Score (1.0-5.0) |
| ICPIF | Double | Calculated Planning Impairment Factor |
| SourcePort | Int32 | Source port for the probe |
| TargetPort | Int32 | Target port for the probe |
| Codec | String | VoIP codec used (G.711, G.729, etc.) |
| Protocol | String | Transport protocol |
| LastUpdate | DateTime | Timestamp of most recent result |

### SWQL Navigation Properties

- **SourceNode** navigates to Orion.Nodes -- the node initiating the operation
- **TargetNode** navigates to Orion.Nodes -- the target node (when managed)
- **Results** navigates to Orion.IpSla.OperationResults (collection) -- historical results

### Example SWQL Queries

**All active IP SLA operations with current metrics:**

```sql
SELECT
    op.OperationName AS [Operation],
    op.OperationType AS [Type],
    op.SourceNode.Caption AS [Source],
    op.TargetAddress AS [Target],
    op.AvgLatency AS [Latency ms],
    op.Jitter AS [Jitter ms],
    op.PacketLoss AS [Loss %],
    op.MOS,
    op.StatusDescription AS [Status]
FROM Orion.IpSla.Operations AS op
WHERE op.Enabled = true
ORDER BY op.MOS ASC
```

**Operations exceeding latency threshold:**

```sql
SELECT
    op.OperationName AS [Operation],
    op.SourceNode.Caption AS [Source],
    op.TargetAddress AS [Target],
    op.AvgLatency AS [Latency ms],
    op.Threshold AS [Threshold ms],
    op.MOS
FROM Orion.IpSla.Operations AS op
WHERE op.Enabled = true
  AND op.AvgLatency > op.Threshold
ORDER BY op.AvgLatency DESC
```

---

## Orion.IpSla.OperationResults (SWQL)

Stores historical results for IP SLA operations. Each record represents a single probe execution with measured quality metrics.

### SWQL Properties

| Property | Type | Description |
|----------|------|-------------|
| ResultID | Int64 | Primary key. Unique result identifier |
| OperationID | Int32 | FK to Orion.IpSla.Operations |
| DateTime | DateTime | When this result was collected |
| Latency | Double | Round-trip latency in ms |
| Jitter | Double | Jitter in ms |
| PacketLoss | Double | Packet loss percentage |
| MOS | Double | Mean Opinion Score |
| ICPIF | Double | Calculated Planning Impairment Factor |
| Status | Int32 | Result status code |
| SourceToDestLatency | Double | One-way source-to-destination latency |
| DestToSourceLatency | Double | One-way destination-to-source latency |
| SourceToDestJitter | Double | One-way source-to-destination jitter |
| DestToSourceJitter | Double | One-way destination-to-source jitter |

### SWQL Navigation Properties

- **Operation** navigates to Orion.IpSla.Operations -- parent operation

### Example SWQL Queries

**Hourly average MOS for a specific operation over the last 24 hours:**

```sql
SELECT
    HOUR(r.DateTime) AS [Hour],
    AVG(r.MOS) AS [Avg MOS],
    AVG(r.Latency) AS [Avg Latency],
    AVG(r.Jitter) AS [Avg Jitter],
    AVG(r.PacketLoss) AS [Avg Loss %]
FROM Orion.IpSla.OperationResults AS r
WHERE r.OperationID = @OperationId
  AND DAYDIFF(r.DateTime, GETUTCDATE()) < 1
GROUP BY HOUR(r.DateTime)
ORDER BY [Hour]
```

---

## Orion.IpSla.CCMMonitoring (SWQL)

Represents Cisco Unified Communications Manager (CUCM) instances monitored by VNQM for call manager health and call quality.

### SWQL Properties

| Property | Type | Description |
|----------|------|-------------|
| CCMID | Int32 | Primary key. Unique call manager identifier |
| NodeID | Int32 | FK to Orion.Nodes. The call manager node |
| DisplayName | String | Call manager display name |
| Status | Int32 | Current monitoring status |
| StatusDescription | String | Human-readable status |
| Version | String | CUCM software version |
| RegisteredPhones | Int32 | Number of currently registered phones |
| UnregisteredPhones | Int32 | Number of unregistered phones |
| RejectedPhones | Int32 | Number of rejected phone registrations |
| ActiveCalls | Int32 | Current number of active calls |
| CompletedCalls | Int32 | Total completed calls |
| FailedCalls | Int32 | Total failed calls |
| LastPollTime | DateTime | Timestamp of last data collection |

### SWQL Navigation Properties

- **Node** navigates to Orion.Nodes -- the call manager node
- **Phones** navigates to Orion.IpSla.CCMPhones (collection) -- registered phones

### Example SWQL Queries

**Call manager health dashboard:**

```sql
SELECT
    ccm.DisplayName AS [Call Manager],
    ccm.StatusDescription AS [Status],
    ccm.RegisteredPhones AS [Registered],
    ccm.UnregisteredPhones AS [Unregistered],
    ccm.ActiveCalls AS [Active Calls],
    ccm.FailedCalls AS [Failed],
    ccm.Version
FROM Orion.IpSla.CCMMonitoring AS ccm
ORDER BY ccm.DisplayName
```

---

## Orion.IpSla.VoipGateways (SWQL)

Represents VoIP gateways monitored for call quality and port utilization.

### SWQL Properties

| Property | Type | Description |
|----------|------|-------------|
| GatewayID | Int32 | Primary key. Unique gateway identifier |
| NodeID | Int32 | FK to Orion.Nodes |
| DisplayName | String | Gateway display name |
| Status | Int32 | Current status code |
| StatusDescription | String | Human-readable status |
| TotalPorts | Int32 | Total number of voice ports |
| ActivePorts | Int32 | Number of currently active voice ports |
| PortUtilization | Double | Port utilization percentage |
| ActiveCalls | Int32 | Current number of active calls |
| Model | String | Gateway hardware model |

### SWQL Navigation Properties

- **Node** navigates to Orion.Nodes -- the gateway node

### Example SWQL Queries

**Gateway utilization overview:**

```sql
SELECT
    gw.DisplayName AS [Gateway],
    gw.StatusDescription AS [Status],
    gw.TotalPorts AS [Total Ports],
    gw.ActivePorts AS [Active Ports],
    gw.PortUtilization AS [Utilization %],
    gw.ActiveCalls AS [Active Calls]
FROM Orion.IpSla.VoipGateways AS gw
ORDER BY gw.PortUtilization DESC
```

---

## Orion.IpSla.Sites (SWQL)

Represents geographic or logical sites defined in VNQM for organizing IP SLA operations and VoIP resources.

### SWQL Properties

| Property | Type | Description |
|----------|------|-------------|
| SiteID | Int32 | Primary key. Unique site identifier |
| Name | String | Site name |
| Description | String | Site description |
| Location | String | Geographic location |
| OperationCount | Int32 | Number of IP SLA operations at this site |
| AvgMOS | Double | Average MOS across operations at this site |
| Status | Int32 | Overall site quality status |

### Example SWQL Queries

**Site quality summary:**

```sql
SELECT
    s.Name AS [Site],
    s.Location,
    s.OperationCount AS [Operations],
    s.AvgMOS AS [Avg MOS],
    CASE
        WHEN s.AvgMOS >= 4.0 THEN 'Good'
        WHEN s.AvgMOS >= 3.5 THEN 'Acceptable'
        WHEN s.AvgMOS >= 3.0 THEN 'Poor'
        ELSE 'Unacceptable'
    END AS [Quality]
FROM Orion.IpSla.Sites AS s
ORDER BY s.AvgMOS ASC
```

---

## Orion.IpSla.CCMPhones (SWQL)

Represents VoIP phones registered with a Cisco Unified Communications Manager.

### SWQL Properties

| Property | Type | Description |
|----------|------|-------------|
| PhoneID | Int32 | Primary key. Unique phone identifier |
| CCMID | Int32 | FK to Orion.IpSla.CCMMonitoring |
| PhoneNumber | String | Directory number / extension |
| Model | String | Phone hardware model |
| Description | String | Phone description / user label |
| IPAddress | String | Current IP address of the phone |
| Status | Int32 | Registration status code |
| StatusDescription | String | Human-readable status (Registered, Unregistered, Rejected) |
| Protocol | String | Signaling protocol (SCCP, SIP) |
| FirmwareVersion | String | Phone firmware version |
| LastRegistration | DateTime | Last registration timestamp |

### SWQL Navigation Properties

- **CallManager** navigates to Orion.IpSla.CCMMonitoring -- parent call manager

### Example SWQL Queries

**Unregistered phones across all call managers:**

```sql
SELECT
    p.PhoneNumber AS [Extension],
    p.Model,
    p.IPAddress,
    p.StatusDescription AS [Status],
    p.CallManager.DisplayName AS [Call Manager],
    ToLocal(p.LastRegistration) AS [Last Registered]
FROM Orion.IpSla.CCMPhones AS p
WHERE p.StatusDescription = 'Unregistered'
ORDER BY p.LastRegistration ASC
```

**Phone inventory by model:**

```sql
SELECT
    p.Model,
    COUNT(*) AS [Count],
    p.CallManager.DisplayName AS [Call Manager]
FROM Orion.IpSla.CCMPhones AS p
GROUP BY p.Model, p.CallManager.DisplayName
ORDER BY [Count] DESC
```

---

## SWQL VNQM Schema Discovery

Use these metadata queries to explore available VNQM entities and properties at runtime:

```sql
-- List all IpSla entities
SELECT FullName, EntityName
FROM Metadata.Entity
WHERE FullName LIKE 'Orion.IpSla.%'
ORDER BY EntityName

-- List properties of a specific VNQM entity
SELECT Name, Type, IsNavigable, IsKey
FROM Metadata.Property
WHERE EntityName = 'Orion.IpSla.Operations'
```
