# SWQL IPAM Entity Schema Reference

> Detailed schema reference for SolarWinds IP Address Manager (IPAM) SWQL entities.
> Covers subnet management, IP node tracking, DHCP/DNS server integration, conflict detection, group hierarchy, IP requests, and scanning.

---

## IPAM.Subnet (SWQL)

Represents a managed IP subnet within IPAM. Each subnet tracks address utilization, CIDR notation, scan configuration, and group membership.

### SWQL Properties

| Property | Type | Description |
|----------|------|-------------|
| SubnetId | Int32 | Primary key. Unique subnet identifier |
| Address | String | Network address of the subnet (e.g., 192.0.2.0) |
| CIDR | Int32 | CIDR prefix length (e.g., 24 for /24) |
| FriendlyName | String | Human-readable name assigned to the subnet |
| DisplayName | String | Display label (often combines Address/CIDR) |
| PercentUsed | Double | Percentage of addresses currently in use |
| GroupID | Int32 | FK to IPAM.GroupNode. Parent group in the hierarchy |
| SubnetType | String | Subnet type (e.g., IPv4, IPv6) |
| VLANID | Int32 | Associated VLAN identifier |
| Location | String | Site/location label |
| Comments | String | Administrator notes |
| ScanInterval | Int32 | Scan frequency in minutes |
| LastScan | DateTime | Timestamp of the most recent scan |
| TotalCount | Int32 | Total number of IP addresses in the subnet |
| UsedCount | Int32 | Number of addresses currently allocated |
| AvailableCount | Int32 | Number of addresses currently free |
| TransientCount | Int32 | Number of addresses in transient state |
| ReservedCount | Int32 | Number of addresses marked as reserved |
| StatusIcon | String | Icon identifier reflecting subnet health |
| GroupTypeText | String | Scan type label (SNMP, ICMP, etc.) |

### SWQL Navigation Properties

- **GroupNode** navigates to IPAM.GroupNode -- parent group in the IP hierarchy
- **IPNodes** navigates to IPAM.IPNode (collection) -- individual IP addresses in this subnet
- **ScanInstances** navigates to IPAM.ScanInstance (collection) -- scan history for this subnet

### Example SWQL Queries

**Subnets with utilization above 90%:**

```sql
SELECT
    s.FriendlyName,
    s.Address,
    CONCAT('/', ToString(s.CIDR)) AS [Prefix],
    s.PercentUsed,
    s.UsedCount,
    s.TotalCount
FROM IPAM.Subnet AS s
WHERE s.PercentUsed > 90
ORDER BY s.PercentUsed DESC
```

**Subnet inventory grouped by VLAN:**

```sql
SELECT
    s.VLANID,
    COUNT(*) AS [Subnet Count],
    AVG(s.PercentUsed) AS [Avg Utilization]
FROM IPAM.Subnet AS s
WHERE s.VLANID IS NOT NULL
GROUP BY s.VLANID
ORDER BY [Avg Utilization] DESC
```

---

## IPAM.IPNode (SWQL)

Represents an individual IP address tracked within a subnet. Stores DNS, MAC, and status information gathered during subnet scans.

### SWQL Properties

| Property | Type | Description |
|----------|------|-------------|
| IPNodeId | Int32 | Primary key. Unique IP node identifier |
| SubnetId | Int32 | FK to IPAM.Subnet. Parent subnet |
| IPAddress | String | The IP address (dotted-decimal or IPv6) |
| Status | Int32 | Current status code (1=Used, 2=Available, 4=Transient, 8=Reserved) |
| StatusName | String | Human-readable status label |
| DnsBackward | String | Reverse DNS (PTR) name |
| DnsForward | String | Forward DNS (A record) name |
| MACAddress | String | Discovered MAC address |
| LastScan | DateTime | Timestamp of last scan that detected this address |
| LastBoot | DateTime | Last boot time discovered via SNMP |
| SystemName | String | SNMP sysName or hostname |
| Comments | String | Administrator notes |
| ResponseTime | Int32 | ICMP response time in milliseconds |
| SkipScan | Boolean | Whether this IP is excluded from scanning |
| AllocPolicy | String | Allocation policy (Static, Dynamic) |

### SWQL Navigation Properties

- **Subnet** navigates to IPAM.Subnet -- parent subnet for this IP
- **Node** navigates to Orion.Nodes -- linked Orion node (if any)

### Example SWQL Queries

**Find IPs with DNS forward/reverse mismatch:**

```sql
SELECT
    ip.IPAddress,
    ip.DnsForward,
    ip.DnsBackward,
    ip.Subnet.FriendlyName AS [Subnet]
FROM IPAM.IPNode AS ip
WHERE ip.DnsForward IS NOT NULL
  AND ip.DnsBackward IS NOT NULL
  AND ip.DnsForward <> ip.DnsBackward
```

**List all used IPs with their MAC and hostname in a specific subnet:**

```sql
SELECT
    ip.IPAddress,
    ip.MACAddress,
    ip.DnsBackward AS [Hostname],
    ip.SystemName,
    ip.ResponseTime
FROM IPAM.IPNode AS ip
WHERE ip.SubnetId = 42
  AND ip.Status = 1
ORDER BY ip.IPAddress
```

---

## IPAM.DhcpServer (SWQL)

Represents a DHCP server managed by IPAM. Links to the Orion node for the server and provides scope enumeration.

### SWQL Properties

| Property | Type | Description |
|----------|------|-------------|
| DhcpServerId | Int32 | Primary key. Unique DHCP server identifier |
| NodeId | Int32 | FK to Orion.Nodes. The monitored node running DHCP |
| DisplayName | String | Friendly display name of the DHCP server |
| ServerType | String | DHCP server type (Microsoft, ISC, Cisco, etc.) |
| ServerIP | String | IP address of the DHCP server |
| Status | Int32 | Current server status code |
| LastDiscovery | DateTime | Last time scopes were discovered |

### SWQL Navigation Properties

- **Node** navigates to Orion.Nodes -- the Orion node hosting this DHCP server
- **Scopes** navigates to IPAM.DhcpScope (collection) -- scopes managed by this server

### Example SWQL Queries

**List all DHCP servers with scope counts:**

```sql
SELECT
    ds.DisplayName AS [DHCP Server],
    ds.ServerIP,
    ds.ServerType,
    COUNT(sc.DhcpScopeId) AS [Scope Count]
FROM IPAM.DhcpServer AS ds
LEFT JOIN IPAM.DhcpScope AS sc ON sc.DhcpServerId = ds.DhcpServerId
GROUP BY ds.DisplayName, ds.ServerIP, ds.ServerType
ORDER BY ds.DisplayName
```

---

## IPAM.DhcpScope (SWQL)

Represents a DHCP scope (address pool) configured on a DHCP server. Tracks utilization and subnet association.

### SWQL Properties

| Property | Type | Description |
|----------|------|-------------|
| DhcpScopeId | Int32 | Primary key. Unique scope identifier |
| DhcpServerId | Int32 | FK to IPAM.DhcpServer |
| NodeId | Int32 | FK to Orion.Nodes |
| DisplayName | String | Scope name/description |
| SubnetAddress | String | Network address of the scope |
| StartAddress | String | First IP in the scope range |
| EndAddress | String | Last IP in the scope range |
| PercentUsed | Double | Percentage of scope addresses leased |
| AvailableCount | Int32 | Number of available addresses |
| LeaseCount | Int32 | Number of active leases |
| ReservedCount | Int32 | Number of reserved addresses |
| Enabled | Boolean | Whether the scope is active |

### SWQL Navigation Properties

- **DhcpServer** navigates to IPAM.DhcpServer -- parent DHCP server
- **Node** navigates to Orion.Nodes -- the hosting node

### Example SWQL Queries

**DHCP scopes nearing exhaustion (above 85% used):**

```sql
SELECT
    sc.DisplayName AS [Scope],
    sc.SubnetAddress,
    sc.PercentUsed,
    sc.AvailableCount AS [Available],
    sc.LeaseCount AS [Leases],
    ds.DisplayName AS [DHCP Server]
FROM IPAM.DhcpScope AS sc
JOIN IPAM.DhcpServer AS ds ON ds.DhcpServerId = sc.DhcpServerId
WHERE sc.PercentUsed > 85
  AND sc.Enabled = true
ORDER BY sc.PercentUsed DESC
```

---

## IPAM.DnsServer (SWQL)

Represents a DNS server managed by IPAM.

### SWQL Properties

| Property | Type | Description |
|----------|------|-------------|
| DnsServerId | Int32 | Primary key. Unique DNS server identifier |
| NodeId | Int32 | FK to Orion.Nodes |
| DisplayName | String | Friendly display name |
| ServerType | String | DNS server type (Microsoft, BIND, etc.) |
| ServerIP | String | IP address of the DNS server |
| Status | Int32 | Current server status code |
| ZoneCount | Int32 | Number of zones hosted |
| LastDiscovery | DateTime | Last zone discovery time |

### SWQL Navigation Properties

- **Node** navigates to Orion.Nodes -- the Orion node hosting this DNS server
- **Zones** navigates to IPAM.DnsZone (collection) -- zones hosted by this server

### Example SWQL Queries

**DNS servers with zone counts:**

```sql
SELECT
    dns.DisplayName AS [DNS Server],
    dns.ServerIP,
    dns.ServerType,
    COUNT(z.DnsZoneId) AS [Zone Count]
FROM IPAM.DnsServer AS dns
LEFT JOIN IPAM.DnsZone AS z ON z.DnsServerId = dns.DnsServerId
GROUP BY dns.DisplayName, dns.ServerIP, dns.ServerType
ORDER BY [Zone Count] DESC
```

---

## IPAM.DnsZone (SWQL)

Represents a DNS zone hosted on a managed DNS server.

### SWQL Properties

| Property | Type | Description |
|----------|------|-------------|
| DnsZoneId | Int32 | Primary key. Unique zone identifier |
| DnsServerId | Int32 | FK to IPAM.DnsServer |
| Name | String | Zone name (e.g., example.com) |
| ZoneType | String | Zone type (Primary, Secondary, Stub, Forward) |
| RecordCount | Int32 | Number of DNS records in the zone |
| Status | Int32 | Current zone status code |
| IsSigned | Boolean | Whether DNSSEC is enabled |
| IsDynamicUpdate | Boolean | Whether dynamic updates are allowed |

### SWQL Navigation Properties

- **DnsServer** navigates to IPAM.DnsServer -- parent DNS server

### Example SWQL Queries

**List all primary zones with record counts:**

```sql
SELECT
    z.Name AS [Zone],
    z.ZoneType,
    z.RecordCount,
    z.IsSigned AS [DNSSEC],
    ds.DisplayName AS [DNS Server]
FROM IPAM.DnsZone AS z
JOIN IPAM.DnsServer AS ds ON ds.DnsServerId = z.DnsServerId
WHERE z.ZoneType = 'Primary'
ORDER BY z.RecordCount DESC
```

---

## IPAM.Conflict (SWQL)

Represents an IP address conflict detected during IPAM scanning. A conflict occurs when the same IP address is associated with multiple MAC addresses.

### SWQL Properties

| Property | Type | Description |
|----------|------|-------------|
| ConflictId | Int32 | Primary key. Unique conflict identifier |
| IPAddress | String | The conflicting IP address |
| MACAddress1 | String | First MAC address claiming this IP |
| MACAddress2 | String | Second MAC address claiming this IP |
| DetectedDate | DateTime | When the conflict was first detected |
| SubnetId | Int32 | FK to IPAM.Subnet where the conflict was found |
| Status | Int32 | Conflict resolution status |

### Example SWQL Queries

**All active IP address conflicts with subnet details:**

```sql
SELECT
    c.IPAddress,
    c.MACAddress1,
    c.MACAddress2,
    c.DetectedDate,
    s.FriendlyName AS [Subnet],
    CONCAT(s.Address, '/', ToString(s.CIDR)) AS [CIDR]
FROM IPAM.Conflict AS c
JOIN IPAM.Subnet AS s ON s.SubnetId = c.SubnetId
ORDER BY c.DetectedDate DESC
```

---

## IPAM.GroupNode (SWQL)

Represents a group in the hierarchical IP address space tree. Groups organize subnets and other groups into a navigable hierarchy.

### SWQL Properties

| Property | Type | Description |
|----------|------|-------------|
| GroupId | Int32 | Primary key. Unique group identifier |
| Name | String | Group name |
| ParentId | Int32 | FK to IPAM.GroupNode. Parent group (NULL for root) |
| Description | String | Group description |
| Comments | String | Administrator notes |
| GroupType | String | Type classification |

### SWQL Navigation Properties

- **Parent** navigates to IPAM.GroupNode -- parent group
- **Children** navigates to IPAM.GroupNode (collection) -- child groups
- **Subnets** navigates to IPAM.Subnet (collection) -- subnets in this group

### Example SWQL Queries

**Full group hierarchy with subnet counts:**

```sql
SELECT
    g.Name AS [Group],
    p.Name AS [Parent Group],
    COUNT(s.SubnetId) AS [Subnet Count]
FROM IPAM.GroupNode AS g
LEFT JOIN IPAM.GroupNode AS p ON p.GroupId = g.ParentId
LEFT JOIN IPAM.Subnet AS s ON s.GroupID = g.GroupId
GROUP BY g.Name, p.Name
ORDER BY g.Name
```

---

## IPAM.IPRequests (SWQL)

Represents IP address provisioning requests submitted through the IPAM request workflow.

### SWQL Properties

| Property | Type | Description |
|----------|------|-------------|
| RequestId | Int32 | Primary key. Unique request identifier |
| IPAddress | String | Requested or assigned IP address |
| SubnetId | Int32 | FK to IPAM.Subnet |
| State | Int32 | Request state (2=Pending, 3=Completed) |
| RequestDate | DateTime | When the request was submitted |
| Requester | String | Username of the requester |
| Comments | String | Request notes |
| CompletedDate | DateTime | When the request was fulfilled |

### Example SWQL Queries

**Pending IP requests older than 7 days:**

```sql
SELECT
    r.IPAddress,
    r.Requester,
    r.RequestDate,
    r.Comments,
    s.FriendlyName AS [Subnet]
FROM IPAM.IPRequests AS r
LEFT JOIN IPAM.Subnet AS s ON s.SubnetId = r.SubnetId
WHERE r.State = 2
  AND DAYDIFF(r.RequestDate, GETUTCDATE()) > 7
ORDER BY r.RequestDate ASC
```

---

## IPAM.ScanInstance (SWQL)

Represents a scan execution record for an IPAM subnet. Tracks when scans ran and their results.

### SWQL Properties

| Property | Type | Description |
|----------|------|-------------|
| ScanInstanceId | Int32 | Primary key. Unique scan instance identifier |
| SubnetId | Int32 | FK to IPAM.Subnet. The scanned subnet |
| ScanType | Int32 | Numeric scan type code |
| StartTime | DateTime | When the scan started |
| EndTime | DateTime | When the scan completed |
| Status | Int32 | Scan result status |
| DiscoveredCount | Int32 | Number of IPs discovered in this scan |

### SWQL Navigation Properties

- **Subnet** navigates to IPAM.Subnet -- the subnet that was scanned

### Example SWQL Queries

**Recent scan results by subnet:**

```sql
SELECT
    s.FriendlyName AS [Subnet],
    CONCAT(s.Address, '/', ToString(s.CIDR)) AS [CIDR],
    si.StartTime,
    si.EndTime,
    si.DiscoveredCount AS [Discovered],
    s.GroupTypeText AS [Scan Type]
FROM IPAM.ScanInstance AS si
JOIN IPAM.Subnet AS s ON s.SubnetId = si.SubnetId
WHERE DAYDIFF(si.StartTime, GETUTCDATE()) < 1
ORDER BY si.StartTime DESC
```

---

## SWQL IPAM Schema Discovery

Use these metadata queries to explore available IPAM entities and properties at runtime:

```sql
-- List all IPAM entities
SELECT FullName, EntityName
FROM Metadata.Entity
WHERE FullName LIKE 'IPAM.%'
ORDER BY EntityName

-- List properties of a specific IPAM entity
SELECT Name, Type, IsNavigable, IsKey
FROM Metadata.Property
WHERE EntityName = 'IPAM.Subnet'
```
