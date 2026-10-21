# SWQL NTA Entity Schema Reference

> Detailed schema reference for SolarWinds NetFlow Traffic Analyzer (NTA) SWQL entities.
> Covers flow data sources, flow records, application classification, CBQoS policies, NBAR2, IP address groups, and protocol definitions.

---

## Orion.Netflow.Source (SWQL)

Represents a NetFlow-enabled node or interface configured as a flow data source. Controls which devices send flow data to the NTA collector.

### SWQL Properties

| Property | Type | Description |
|----------|------|-------------|
| NodeID | Int32 | FK to Orion.Nodes. The source node sending flow data |
| InterfaceID | Int32 | FK to Orion.NPM.Interfaces. The specific interface (0 = node-level) |
| Enabled | Boolean | Whether flow collection is active for this source |
| EngineID | Int32 | Polling engine handling this source |
| LastTime | DateTime | Timestamp of the most recent flow data received |
| FlowCount | Int64 | Total number of flow records collected |
| NetflowVersion | Int32 | NetFlow version (5, 9, 10/IPFIX, sFlow) |
| ExportMode | String | Flow export mode (NetFlow, sFlow, J-Flow, etc.) |

### SWQL Navigation Properties

- **Node** navigates to Orion.Nodes -- the node exporting flow data
- **Interface** navigates to Orion.NPM.Interfaces -- the specific interface (when applicable)

### Example SWQL Queries

**List all active NetFlow sources with last collection time:**

```sql
SELECT
    ns.Node.Caption AS [Node],
    ns.Node.IPAddress,
    ns.Enabled,
    ns.NetflowVersion AS [Version],
    ToLocal(ns.LastTime) AS [Last Received]
FROM Orion.Netflow.Source AS ns
WHERE ns.Enabled = true
ORDER BY ns.LastTime DESC
```

**NetFlow sources that have not sent data in 24 hours:**

```sql
SELECT
    ns.Node.Caption AS [Node],
    ns.Node.IPAddress,
    ToLocal(ns.LastTime) AS [Last Received],
    HOURDIFF(ns.LastTime, GETUTCDATE()) AS [Hours Silent]
FROM Orion.Netflow.Source AS ns
WHERE ns.Enabled = true
  AND HOURDIFF(ns.LastTime, GETUTCDATE()) > 24
ORDER BY ns.LastTime ASC
```

---

## Orion.Netflow.Flows (SWQL)

Represents individual or aggregated NetFlow records. Contains the core traffic data including source/destination IPs, ports, protocols, and byte counts.

### SWQL Properties

| Property | Type | Description |
|----------|------|-------------|
| FlowID | Int64 | Primary key. Unique flow record identifier |
| TimeStamp | DateTime | When the flow was recorded |
| SourceIP | String | Source IP address of the traffic |
| DestIP | String | Destination IP address of the traffic |
| SourcePort | Int32 | Source TCP/UDP port |
| DestPort | Int32 | Destination TCP/UDP port |
| Protocol | Int32 | IP protocol number (6=TCP, 17=UDP, 1=ICMP) |
| Bytes | Int64 | Total bytes transferred in this flow |
| Packets | Int64 | Total packets in this flow |
| NodeID | Int32 | FK to Orion.Nodes. Reporting node |
| InterfaceID | Int32 | FK to Orion.NPM.Interfaces. Reporting interface |
| Direction | Int32 | Traffic direction (1=Ingress, 2=Egress) |
| ApplicationID | Int32 | FK to Orion.Netflow.Applications |
| ToS | Int32 | Type of Service / DSCP value |

### SWQL Navigation Properties

- **Node** navigates to Orion.Nodes -- the node that reported this flow
- **Interface** navigates to Orion.NPM.Interfaces -- the interface where the flow was observed
- **Application** navigates to Orion.Netflow.Applications -- classified application

### Example SWQL Queries

**Top 10 talkers by bytes in the last hour:**

```sql
SELECT TOP 10
    f.SourceIP,
    SUM(f.Bytes) AS [Total Bytes],
    COUNT(*) AS [Flow Count]
FROM Orion.Netflow.Flows AS f
WHERE MINUTEDIFF(f.TimeStamp, GETUTCDATE()) < 60
GROUP BY f.SourceIP
ORDER BY [Total Bytes] DESC
```

**Traffic by protocol in the last 24 hours:**

```sql
SELECT
    CASE f.Protocol
        WHEN 6 THEN 'TCP'
        WHEN 17 THEN 'UDP'
        WHEN 1 THEN 'ICMP'
        ELSE CONCAT('Protocol ', ToString(f.Protocol))
    END AS [Protocol],
    SUM(f.Bytes) / 1073741824 AS [Total GB],
    COUNT(*) AS [Flow Count]
FROM Orion.Netflow.Flows AS f
WHERE DAYDIFF(f.TimeStamp, GETUTCDATE()) < 1
GROUP BY f.Protocol
ORDER BY [Total GB] DESC
```

---

## Orion.Netflow.Applications (SWQL)

Defines application classifications used to identify traffic by port and protocol combinations.

### SWQL Properties

| Property | Type | Description |
|----------|------|-------------|
| ApplicationID | Int32 | Primary key. Unique application identifier |
| Name | String | Application name (e.g., HTTP, DNS, SMTP) |
| Port | Int32 | Primary port number for single-port applications |
| Protocol | Int32 | IP protocol number (6=TCP, 17=UDP) |
| Enabled | Boolean | Whether this classification is active |
| Multiport | Boolean | Whether the application spans multiple ports |
| Description | String | Application description |

### Example SWQL Queries

**All enabled application classifications with ports:**

```sql
SELECT
    a.Name AS [Application],
    a.Port,
    CASE a.Protocol
        WHEN 6 THEN 'TCP'
        WHEN 17 THEN 'UDP'
        ELSE ToString(a.Protocol)
    END AS [Protocol],
    CASE a.Multiport
        WHEN true THEN 'Multi-Port'
        ELSE 'Single-Port'
    END AS [Type]
FROM Orion.Netflow.Applications AS a
WHERE a.Enabled = true
ORDER BY a.Name
```

---

## Orion.Netflow.CBQoSPolicy (SWQL)

Represents a Class-Based Quality of Service policy observed on NetFlow-enabled interfaces.

### SWQL Properties

| Property | Type | Description |
|----------|------|-------------|
| PolicyID | Int32 | Primary key. Unique policy identifier |
| PolicyName | String | Name of the QoS policy |
| NodeID | Int32 | FK to Orion.Nodes. Node where the policy is applied |
| InterfaceID | Int32 | FK to Orion.NPM.Interfaces |
| Direction | String | Policy direction (Ingress/Egress) |
| Enabled | Boolean | Whether monitoring is active |

### SWQL Navigation Properties

- **Node** navigates to Orion.Nodes
- **Interface** navigates to Orion.NPM.Interfaces
- **ClassMaps** navigates to Orion.Netflow.CBQoSClassMap (collection)

### Example SWQL Queries

**All CBQoS policies with their node and direction:**

```sql
SELECT
    p.PolicyName,
    p.Node.Caption AS [Node],
    p.Interface.Caption AS [Interface],
    p.Direction,
    p.Enabled
FROM Orion.Netflow.CBQoSPolicy AS p
ORDER BY p.Node.Caption, p.PolicyName
```

---

## Orion.Netflow.CBQoSClassMap (SWQL)

Represents a class map within a CBQoS policy. Class maps define traffic classification rules within a QoS policy.

### SWQL Properties

| Property | Type | Description |
|----------|------|-------------|
| ClassMapID | Int32 | Primary key. Unique class map identifier |
| PolicyID | Int32 | FK to Orion.Netflow.CBQoSPolicy |
| ClassName | String | Name of the traffic class |
| MatchType | String | Match criteria type |
| PrePolicyRate | Int64 | Traffic rate before policy enforcement (bps) |
| PostPolicyRate | Int64 | Traffic rate after policy enforcement (bps) |
| DropRate | Int64 | Drop rate for this class (bps) |

### SWQL Navigation Properties

- **Policy** navigates to Orion.Netflow.CBQoSPolicy -- parent policy

### Example SWQL Queries

**Class maps with significant drop rates:**

```sql
SELECT
    cm.ClassName,
    cm.Policy.PolicyName AS [Policy],
    cm.Policy.Node.Caption AS [Node],
    cm.PrePolicyRate AS [Pre-Policy bps],
    cm.PostPolicyRate AS [Post-Policy bps],
    cm.DropRate AS [Drop bps]
FROM Orion.Netflow.CBQoSClassMap AS cm
WHERE cm.DropRate > 0
ORDER BY cm.DropRate DESC
```

---

## Orion.Netflow.NBAR2Applications (SWQL)

Represents NBAR2 (Network-Based Application Recognition version 2) application classifications discovered from devices supporting NBAR2 export.

### SWQL Properties

| Property | Type | Description |
|----------|------|-------------|
| ApplicationID | Int32 | Primary key. Unique NBAR2 application identifier |
| Name | String | NBAR2 application name |
| Description | String | Application description from NBAR2 taxonomy |
| Category | String | Application category (e.g., Web, Streaming, VoIP) |
| SubCategory | String | Application sub-category |
| Encrypted | Boolean | Whether the application uses encryption |

### Example SWQL Queries

**NBAR2 applications by category:**

```sql
SELECT
    n.Category,
    COUNT(*) AS [App Count]
FROM Orion.Netflow.NBAR2Applications AS n
GROUP BY n.Category
ORDER BY [App Count] DESC
```

---

## Orion.Netflow.IPAddressGroups (SWQL)

Defines IP address group classifications used to categorize traffic as internal, external, or by custom groupings (e.g., DMZ, partner networks).

### SWQL Properties

| Property | Type | Description |
|----------|------|-------------|
| IPAddressGroupID | Int32 | Primary key. Unique group identifier |
| IPAddressGroupName | String | Group name (e.g., Internal, DMZ, Internet) |
| IPRangeStart | String | Start of the IP range (padded numeric format) |
| IPRangeEnd | String | End of the IP range (padded numeric format) |
| Enabled | Boolean | Whether this group definition is active |

### Example SWQL Queries

**All enabled IP address groups:**

```sql
SELECT
    IPAddressGroupName AS [Group Name],
    IPRangeStart AS [Range Start],
    IPRangeEnd AS [Range End],
    Enabled
FROM Orion.Netflow.IPAddressGroups
WHERE Enabled = true
ORDER BY IPAddressGroupName
```

---

## Orion.Netflow.Protocols (SWQL)

Defines protocol definitions used in NetFlow classification.

### SWQL Properties

| Property | Type | Description |
|----------|------|-------------|
| ProtocolID | Int32 | Primary key. Matches the IP protocol number |
| Name | String | Protocol name (TCP, UDP, ICMP, GRE, etc.) |
| Description | String | Protocol description |

### Example SWQL Queries

**List all defined protocols:**

```sql
SELECT
    p.ProtocolID AS [Protocol Number],
    p.Name AS [Protocol],
    p.Description
FROM Orion.Netflow.Protocols AS p
ORDER BY p.ProtocolID
```

---

## SWQL NTA Schema Discovery

Use these metadata queries to explore available NTA entities and properties at runtime:

```sql
-- List all Netflow entities
SELECT FullName, EntityName
FROM Metadata.Entity
WHERE FullName LIKE 'Orion.Netflow.%'
ORDER BY EntityName

-- List properties of a specific NTA entity
SELECT Name, Type, IsNavigable, IsKey
FROM Metadata.Property
WHERE EntityName = 'Orion.Netflow.Flows'
```
