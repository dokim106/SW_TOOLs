# SWQL NPM (Network Performance Monitor) Entity Schema Reference

## Orion.NPM.Interfaces Entity Schema (SWQL)

Primary entity for monitored network interfaces; used extensively for capacity planning and troubleshooting.

### Properties

| Property | Type | Notes |
|----------|------|-------|
| InterfaceID | Int32 | **Primary Key.** Unique identifier for the interface. |
| NodeID | Int32 | Foreign key to `Orion.Nodes`. The parent device hosting this interface. |
| Caption | String | Human-readable label (usually auto-generated from device MIB data). |
| InterfaceName | String | Raw SNMP interface name (ifName). |
| InterfaceIcon | String | Icon identifier used in the Orion web console. |
| Status | Int32 | Current monitoring status code (1 = Up, 2 = Down, 3 = Warning, etc.). |
| StatusDescription | String | Human-readable status label corresponding to the Status code. |
| InterfaceType | Int32 | IANA ifType numeric code (e.g., 6 = ethernetCsmacd, 53 = propVirtual). |
| InterfaceTypeName | String | Short name for the interface type. |
| InterfaceTypeDescription | String | Longer description of the interface type. |
| Speed | Double | Negotiated speed in bps as reported by the device. |
| InBandwidth | Double | Receive bandwidth capacity in bps (may differ from Speed on asymmetric links). |
| OutBandwidth | Double | Transmit bandwidth capacity in bps. |
| InPercentUtil | Single | Current inbound utilization as a percentage of InBandwidth (0-100). |
| OutPercentUtil | Single | Current outbound utilization as a percentage of OutBandwidth (0-100). |
| OperStatus | Int32 | SNMP ifOperStatus: 1 = up, 2 = down, 3 = testing. |
| AdminStatus | Int32 | SNMP ifAdminStatus: 1 = up, 2 = down, 3 = testing. |
| InterfaceAlias | String | SNMP ifAlias (often the port description configured on the device). |
| InterfaceIndex | Int32 | SNMP ifIndex value on the device. |
| FullName | String | Fully qualified name combining node caption and interface caption. |
| Counter64 | Boolean | True if the device supports 64-bit counters on this interface. |
| InterfaceMTU | Int32 | Maximum transmission unit in bytes. |
| InterfaceSpeed | Double | Raw interface speed in bps (ifSpeed or ifHighSpeed). |
| Duplex | Int32 | Duplex mode: 0 = Unknown, 1 = Half, 2 = Full. |
| InDiscard | Int32 | Current inbound discards count. |
| InErrors | Int32 | Current inbound errors count. |
| OutDiscard | Int32 | Current outbound discards count. |
| OutErrors | Int32 | Current outbound errors count. |
| UnPluggable | Boolean | Whether this is a pluggable transceiver port. |
| PollInterval | Int32 | Polling frequency in seconds. |
| NextPoll | DateTime | Scheduled time of the next statistics poll. |
| NextRediscovery | DateTime | Scheduled time of the next interface rediscovery. |
| StatCollection | Int32 | Statistics collection mode (0 = None, 1 = Basic, 9 = Full). |
| RediscoveryInterval | Int32 | Interval between rediscoveries in minutes. |
| Uri | String | SWIS URI for this entity instance. |
| DisplayName | String | Formatted display name used in the web console. |

### SWQL Navigation Properties

| Navigation Property | Target Entity | Cardinality | Description |
|---------------------|---------------|-------------|-------------|
| Node | Orion.Nodes | Reference (single) | The parent node hosting this interface. |
| CustomProperties | Orion.NPM.InterfacesCustomProperties | Reference (single) | Custom property bag for this interface. |
| InterfaceTraffic | Orion.NPM.InterfaceTraffic | Collection | Historical traffic statistics records. |
| InterfaceErrors | Orion.NPM.InterfaceErrors | Collection | Historical error and discard statistics. |

### Example SWQL Queries

**Interfaces with high inbound utilization (over 80%):**

```sql
SELECT
    i.Node.Caption AS NodeName,
    i.Caption AS InterfaceName,
    i.InPercentUtil,
    i.OutPercentUtil,
    i.InBandwidth / 1000000 AS InBandwidthMbps,
    i.StatusDescription
FROM Orion.NPM.Interfaces AS i
WHERE i.InPercentUtil > 80
  AND i.Status = 1
ORDER BY i.InPercentUtil DESC
```

**All operationally down interfaces on nodes that are up:**

```sql
SELECT
    i.Node.Caption AS NodeName,
    i.Caption AS InterfaceName,
    i.InterfaceAlias AS Description,
    i.OperStatus,
    i.AdminStatus,
    i.StatusDescription
FROM Orion.NPM.Interfaces AS i
WHERE i.OperStatus = 2
  AND i.Node.Status = 1
ORDER BY i.Node.Caption, i.Caption
```

**Count of monitored interfaces per node:**

```sql
SELECT
    i.Node.Caption AS NodeName,
    i.Node.IPAddress,
    COUNT(i.InterfaceID) AS InterfaceCount
FROM Orion.NPM.Interfaces AS i
GROUP BY i.Node.Caption, i.Node.IPAddress
ORDER BY InterfaceCount DESC
```

---

## Orion.NPM.InterfaceTraffic Entity Schema (SWQL)

Historical traffic statistics (per polling interval); basis for trend analysis and bandwidth reporting.

### Properties

| Property | Type | Notes |
|----------|------|-------|
| InterfaceID | Int32 | Foreign key to `Orion.NPM.Interfaces`. |
| DateTime | DateTime | Timestamp of the polling sample (UTC). |
| InAverageBps | Double | Average inbound throughput in bits per second during the interval. |
| OutAverageBps | Double | Average outbound throughput in bits per second during the interval. |
| InTotalBytes | Double | Total inbound bytes transferred during the interval. |
| OutTotalBytes | Double | Total outbound bytes transferred during the interval. |
| InTotalPkts | Double | Total inbound packets during the interval. |
| OutTotalPkts | Double | Total outbound packets during the interval. |
| InAvgBps | Double | Alternate average inbound bps field (varies by schema version). |
| OutAvgBps | Double | Alternate average outbound bps field. |
| InMinBps | Double | Minimum inbound bps observed during the interval. |
| InMaxBps | Double | Maximum inbound bps observed during the interval. |
| OutMinBps | Double | Minimum outbound bps observed during the interval. |
| OutMaxBps | Double | Maximum outbound bps observed during the interval. |
| InPercentUtil | Single | Inbound utilization as a percentage during the interval. |
| OutPercentUtil | Single | Outbound utilization as a percentage during the interval. |
| TotalBytesIn | Double | Cumulative inbound byte counter. |
| TotalBytesOut | Double | Cumulative outbound byte counter. |
| Percentile95thIn | Double | 95th percentile inbound bps (available on aggregated records). |
| Percentile95thOut | Double | 95th percentile outbound bps (available on aggregated records). |

### Example SWQL Queries

**Average bandwidth consumption over the last 24 hours for a specific interface:**

```sql
SELECT
    AVG(it.InAverageBps) / 1000000 AS AvgInMbps,
    AVG(it.OutAverageBps) / 1000000 AS AvgOutMbps,
    MAX(it.InAverageBps) / 1000000 AS PeakInMbps,
    MAX(it.OutAverageBps) / 1000000 AS PeakOutMbps
FROM Orion.NPM.InterfaceTraffic AS it
WHERE it.InterfaceID = 42
  AND it.DateTime >= ADDDAY(-1, GETUTCDATE())
```

**Top 10 busiest interfaces by average inbound throughput in the past hour:**

```sql
SELECT TOP 10
    it.InterfaceID,
    AVG(it.InAverageBps) / 1000000 AS AvgInMbps,
    AVG(it.OutAverageBps) / 1000000 AS AvgOutMbps
FROM Orion.NPM.InterfaceTraffic AS it
WHERE it.DateTime >= ADDHOUR(-1, GETUTCDATE())
GROUP BY it.InterfaceID
ORDER BY AvgInMbps DESC
```

---

## SWQL NPM Custom Pollers (UnDP) Entities

Universal Device Pollers (UnDP) allow custom SNMP OID monitoring beyond the built-in NPM pollers. The SWQL schema uses three interrelated entities to define, assign, and report on custom pollers.

### Orion.NPM.CustomPollers

Defines a custom poller template (the OID, return type, and display settings).

| Property | Type | Notes |
|----------|------|-------|
| CustomPollerID | Int32 | **Primary Key.** |
| OID | String | SNMP OID to poll. |
| MIB | String | MIB name (informational). |
| Name | String | Human-readable poller name. |
| Description | String | Poller description. |
| UniqueName | String | System-generated unique name. |
| PollerType | String | Rate, Counter, or Raw. |
| Group | String | Logical grouping. |
| ParseMethod | String | How the returned value should be parsed. |

### Orion.NPM.CustomPollerAssignment

Links a custom poller template to a specific node or interface.

| Property | Type | Notes |
|----------|------|-------|
| CustomPollerAssignmentID | Int32 | **Primary Key.** |
| CustomPollerID | Int32 | Foreign key to `Orion.NPM.CustomPollers`. |
| NodeID | Int32 | Foreign key to `Orion.Nodes`. |
| InterfaceID | Int32 | Foreign key to `Orion.NPM.Interfaces` (0 if node-level). |
| Enabled | Boolean | Whether polling is active. |

### Orion.NPM.CustomPollerStatus

Current and recent polled values for an assigned custom poller.

| Property | Type | Notes |
|----------|------|-------|
| CustomPollerAssignmentID | Int32 | Foreign key to the assignment. |
| Status | Int32 | Current status code. |
| DateTime | DateTime | Last poll timestamp. |
| RawStatus | String | Raw string value returned from the device. |
| RowID | Int32 | For table pollers, the row index. |

### Example SWQL Queries

**List all custom poller assignments with their current values:**

```sql
SELECT
    cp.Name AS PollerName,
    cpa.NodeID,
    cps.RawStatus AS CurrentValue,
    cps.DateTime AS LastPollTime
FROM Orion.NPM.CustomPollerAssignment AS cpa
INNER JOIN Orion.NPM.CustomPollers AS cp
    ON cpa.CustomPollerID = cp.CustomPollerID
LEFT JOIN Orion.NPM.CustomPollerStatus AS cps
    ON cpa.CustomPollerAssignmentID = cps.CustomPollerAssignmentID
ORDER BY cp.Name, cpa.NodeID
```

---

## SWQL NPM Wireless Entities

NPM includes wireless monitoring entities for managing wireless infrastructure. These entities track wireless controllers, access points, connected clients, and SSIDs.

### Orion.Packages.Wireless.Controllers

Represents wireless LAN controllers (WLCs).

| Property | Type | Notes |
|----------|------|-------|
| ControllerID | Int32 | **Primary Key.** |
| NodeID | Int32 | Foreign key to `Orion.Nodes` for the controller device. |
| Name | String | Controller display name. |
| Status | Int32 | Monitoring status code. |
| Model | String | Hardware model of the controller. |
| FirmwareVersion | String | Running firmware version. |
| TotalAccessPoints | Int32 | Total managed APs. |
| TotalClients | Int32 | Total connected wireless clients. |
| Uri | String | SWIS URI. |

### Orion.Packages.Wireless.AccessPoints

Represents individual access points managed by a controller.

| Property | Type | Notes |
|----------|------|-------|
| AccessPointID | Int32 | **Primary Key.** |
| ControllerID | Int32 | Foreign key to the parent controller. |
| Name | String | AP name/hostname. |
| IPAddress | String | Management IP. |
| MACAddress | String | AP MAC address. |
| Model | String | Hardware model. |
| Status | Int32 | Monitoring status. |
| Location | String | Physical location. |
| ClientCount | Int32 | Current connected client count. |
| Channel | Int32 | Operating radio channel. |
| BandType | String | Radio band (2.4 GHz, 5 GHz, 6 GHz). |

### Orion.Packages.Wireless.Clients

Represents individual wireless clients connected to access points.

| Property | Type | Notes |
|----------|------|-------|
| ClientID | Int32 | **Primary Key.** |
| AccessPointID | Int32 | Foreign key to the parent AP. |
| MACAddress | String | Client MAC address. |
| IPAddress | String | Client IP address. |
| UserName | String | Authenticated username (if available). |
| SSID | String | Connected SSID. |
| SignalStrength | Int32 | Client signal strength in dBm. |
| DataRate | Double | Current data rate in Mbps. |
| ConnectedTime | DateTime | Connection start time. |

### Orion.Packages.Wireless.SSIDs

Represents configured SSIDs (wireless network names).

| Property | Type | Notes |
|----------|------|-------|
| SSIDID | Int32 | **Primary Key.** |
| ControllerID | Int32 | Foreign key to the parent controller. |
| Name | String | SSID name (network name). |
| Enabled | Boolean | Whether the SSID is active. |
| SecurityMode | String | Security protocol (WPA2, WPA3, Open, etc.). |
| VLAN | Int32 | Associated VLAN ID. |
| ClientCount | Int32 | Current client count on this SSID. |

### Example SWQL Queries

**Access points with the most connected clients:**

```sql
SELECT TOP 20
    ap.Name AS AccessPointName,
    ap.Location,
    ap.ClientCount,
    ap.BandType,
    ap.Status
FROM Orion.Packages.Wireless.AccessPoints AS ap
WHERE ap.Status = 1
ORDER BY ap.ClientCount DESC
```

**Wireless clients connected with weak signal:**

```sql
SELECT
    c.MACAddress,
    c.IPAddress,
    c.UserName,
    c.SSID,
    c.SignalStrength,
    c.DataRate
FROM Orion.Packages.Wireless.Clients AS c
WHERE c.SignalStrength < -75
ORDER BY c.SignalStrength ASC
```
