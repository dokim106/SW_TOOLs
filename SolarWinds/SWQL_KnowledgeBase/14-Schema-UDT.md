# SWQL UDT Entity Schema Reference

> Detailed schema reference for SolarWinds User Device Tracker (UDT) SWQL entities.
> Covers switch port monitoring, IP-to-MAC resolution, user-device association, watch lists, rogue endpoint detection, and discovery jobs.

---

## Orion.UDT.Port (SWQL)

Represents a tracked switch port monitored by UDT. Stores port identity, monitoring state, and connected endpoint information.

### SWQL Properties

| Property | Type | Description |
|----------|------|-------------|
| PortID | Int32 | Primary key. Unique port tracking identifier |
| NodeID | Int32 | FK to Orion.Nodes. The switch node owning this port |
| PortName | String | Port name/label (e.g., GigabitEthernet0/1) |
| PortIndex | Int32 | SNMP ifIndex of the port |
| IsMonitored | Boolean | Whether UDT is actively tracking this port |
| Status | Int32 | Current port status code |
| VlanId | Int32 | VLAN assigned to this port |
| VlanName | String | VLAN name |
| PortType | String | Port type (Access, Trunk, Hybrid) |
| Speed | Int64 | Port speed in bps |
| DuplexMode | String | Duplex setting (Full, Half, Auto) |
| PortDescription | String | Port description from switch config |
| LastChange | DateTime | Timestamp of the last status change |

### SWQL Navigation Properties

- **Node** navigates to Orion.Nodes -- the switch where this port exists
- **IPAddresses** navigates to Orion.UDT.IPAddressCurrent (collection) -- IPs currently seen on this port
- **MACAddresses** navigates to Orion.UDT.MACCurrentInfo (collection) -- MACs currently seen on this port

### Example SWQL Queries

**Monitored ports with VLAN assignment:**

```sql
SELECT
    p.Node.Caption AS [Switch],
    p.PortName,
    p.VlanId,
    p.VlanName,
    p.PortType,
    p.Status
FROM Orion.UDT.Port AS p
WHERE p.IsMonitored = true
ORDER BY p.Node.Caption, p.PortName
```

**Ports with multiple MAC addresses (potential hubs or unauthorized switches):**

```sql
SELECT
    p.Node.Caption AS [Switch],
    p.PortName,
    COUNT(m.MACAddress) AS [MAC Count]
FROM Orion.UDT.Port AS p
JOIN Orion.UDT.MACCurrentInfo AS m ON m.PortID = p.PortID
WHERE p.IsMonitored = true
GROUP BY p.Node.Caption, p.PortName
HAVING COUNT(m.MACAddress) > 1
ORDER BY [MAC Count] DESC
```

---

## Orion.UDT.IPAddressCurrent (SWQL)

Represents the current IP-to-MAC-to-port mapping observed by UDT. Contains the most recently discovered endpoint data.

### SWQL Properties

| Property | Type | Description |
|----------|------|-------------|
| IPAddressID | Int32 | Primary key. Unique IP tracking identifier |
| IPAddress | String | The discovered IP address |
| MACAddress | String | Associated MAC address |
| PortID | Int32 | FK to Orion.UDT.Port. Switch port where this IP was seen |
| NodeID | Int32 | FK to Orion.Nodes. Switch where this IP was discovered |
| FirstSeen | DateTime | When this IP-MAC binding was first observed |
| LastSeen | DateTime | When this IP-MAC binding was last confirmed |
| DnsName | String | Reverse DNS hostname |
| VlanId | Int32 | VLAN where this IP was observed |

### SWQL Navigation Properties

- **Port** navigates to Orion.UDT.Port -- the switch port
- **Node** navigates to Orion.Nodes -- the switch node

### Example SWQL Queries

**Current IP-to-port mappings for a specific switch:**

```sql
SELECT
    ip.IPAddress,
    ip.MACAddress,
    ip.DnsName AS [Hostname],
    p.PortName,
    ip.VlanId,
    ToLocal(ip.LastSeen) AS [Last Seen]
FROM Orion.UDT.IPAddressCurrent AS ip
JOIN Orion.UDT.Port AS p ON p.PortID = ip.PortID
WHERE ip.NodeID = @NodeId
ORDER BY ip.IPAddress
```

---

## Orion.UDT.IPAddressHistory (SWQL)

Stores historical IP-to-MAC-to-port associations. Used for tracking endpoint movement over time.

### SWQL Properties

| Property | Type | Description |
|----------|------|-------------|
| IPAddressHistoryID | Int32 | Primary key |
| IPAddress | String | The IP address |
| MACAddress | String | Associated MAC address at the time |
| PortID | Int32 | FK to Orion.UDT.Port |
| NodeID | Int32 | FK to Orion.Nodes |
| FirstSeen | DateTime | When this binding was first observed |
| LastSeen | DateTime | When this binding was last confirmed |
| DnsName | String | Reverse DNS hostname at the time |
| VlanId | Int32 | VLAN at the time of observation |

### Example SWQL Queries

**Track an IP address's port history over the last 30 days:**

```sql
SELECT
    h.IPAddress,
    h.MACAddress,
    h.Port.PortName AS [Port],
    h.Port.Node.Caption AS [Switch],
    ToLocal(h.FirstSeen) AS [First Seen],
    ToLocal(h.LastSeen) AS [Last Seen]
FROM Orion.UDT.IPAddressHistory AS h
WHERE h.IPAddress = '192.0.2.50'
  AND DAYDIFF(h.LastSeen, GETUTCDATE()) < 30
ORDER BY h.FirstSeen DESC
```

---

## Orion.UDT.MACAddressInfo (SWQL)

Provides MAC address details including vendor OUI lookup information.

### SWQL Properties

| Property | Type | Description |
|----------|------|-------------|
| MACAddressID | Int32 | Primary key |
| MACAddress | String | The MAC address (colon-separated hex) |
| Vendor | String | Vendor name from OUI lookup |
| Description | String | Administrator-assigned description |
| LastSeen | DateTime | Last time this MAC was observed anywhere |

---

## Orion.UDT.MACCurrentInfo (SWQL)

Represents the current MAC-to-port association observed by UDT.

### SWQL Properties

| Property | Type | Description |
|----------|------|-------------|
| MACAddressID | Int32 | Primary key |
| MACAddress | String | The MAC address |
| PortID | Int32 | FK to Orion.UDT.Port. Current switch port |
| NodeID | Int32 | FK to Orion.Nodes. Current switch |
| VlanId | Int32 | Current VLAN |
| FirstSeen | DateTime | When first seen on this port |
| LastSeen | DateTime | Most recent observation on this port |
| Vendor | String | Vendor from OUI lookup |

### SWQL Navigation Properties

- **Port** navigates to Orion.UDT.Port
- **Node** navigates to Orion.Nodes

### Example SWQL Queries

**Find a device by MAC address across all switches:**

```sql
SELECT
    m.MACAddress,
    m.Vendor,
    m.Port.PortName AS [Port],
    m.Port.Node.Caption AS [Switch],
    m.VlanId,
    ToLocal(m.LastSeen) AS [Last Seen]
FROM Orion.UDT.MACCurrentInfo AS m
WHERE m.MACAddress LIKE '%AA:BB:CC%'
```

---

## Orion.UDT.User (SWQL)

Represents a user-to-device association currently observed by UDT. Tracks which user accounts are logged in to which endpoints.

### SWQL Properties

| Property | Type | Description |
|----------|------|-------------|
| UserID | Int32 | Primary key |
| UserName | String | Logged-in username |
| DomainName | String | Windows domain name |
| IPAddress | String | IP address where the user is logged in |
| MACAddress | String | MAC address of the endpoint |
| PortID | Int32 | FK to Orion.UDT.Port |
| NodeID | Int32 | FK to Orion.Nodes |
| FirstSeen | DateTime | When this user session was first detected |
| LastSeen | DateTime | Last confirmation of this user session |

### SWQL Navigation Properties

- **Port** navigates to Orion.UDT.Port
- **Node** navigates to Orion.Nodes

### Example SWQL Queries

**Find where a specific user is currently connected:**

```sql
SELECT
    u.UserName,
    u.DomainName,
    u.IPAddress,
    u.MACAddress,
    u.Port.PortName AS [Port],
    u.Port.Node.Caption AS [Switch],
    ToLocal(u.LastSeen) AS [Last Seen]
FROM Orion.UDT.User AS u
WHERE u.UserName LIKE '%jsmith%'
```

---

## Orion.UDT.UserHistory (SWQL)

Stores historical user-to-device associations for forensic endpoint tracking.

### SWQL Properties

| Property | Type | Description |
|----------|------|-------------|
| UserHistoryID | Int32 | Primary key |
| UserName | String | Username at the time |
| DomainName | String | Domain name at the time |
| IPAddress | String | IP address at the time |
| MACAddress | String | MAC address at the time |
| PortID | Int32 | FK to Orion.UDT.Port |
| FirstSeen | DateTime | Session start time |
| LastSeen | DateTime | Session end time |

### Example SWQL Queries

**User connection history for the past 7 days:**

```sql
SELECT
    uh.UserName,
    uh.DomainName,
    uh.IPAddress,
    uh.MACAddress,
    uh.Port.PortName AS [Port],
    uh.Port.Node.Caption AS [Switch],
    ToLocal(uh.FirstSeen) AS [Connected],
    ToLocal(uh.LastSeen) AS [Disconnected]
FROM Orion.UDT.UserHistory AS uh
WHERE DAYDIFF(uh.LastSeen, GETUTCDATE()) < 7
ORDER BY uh.LastSeen DESC
```

---

## Orion.UDT.WatchList (SWQL)

Represents endpoints (MAC or IP) placed on the UDT watch list for proactive alerting when they appear on the network.

### SWQL Properties

| Property | Type | Description |
|----------|------|-------------|
| WatchListID | Int32 | Primary key |
| MACAddress | String | Watched MAC address |
| IPAddress | String | Watched IP address |
| Description | String | Reason for watching this endpoint |
| DateAdded | DateTime | When the entry was added to the watch list |
| AddedBy | String | Administrator who added the entry |
| Status | Int32 | Current detection status |
| LastSeen | DateTime | Last time this endpoint was detected |

### Example SWQL Queries

**All watch list entries with detection status:**

```sql
SELECT
    wl.MACAddress,
    wl.IPAddress,
    wl.Description,
    wl.AddedBy,
    ToLocal(wl.DateAdded) AS [Added],
    ToLocal(wl.LastSeen) AS [Last Detected]
FROM Orion.UDT.WatchList AS wl
ORDER BY wl.DateAdded DESC
```

---

## Orion.UDT.RogueEndpoints (SWQL)

Represents endpoints detected by UDT that are flagged as rogue (unauthorized devices on the network).

### SWQL Properties

| Property | Type | Description |
|----------|------|-------------|
| RogueEndpointID | Int32 | Primary key |
| MACAddress | String | MAC address of the rogue device |
| IPAddress | String | IP address of the rogue device |
| PortID | Int32 | FK to Orion.UDT.Port. Port where detected |
| NodeID | Int32 | FK to Orion.Nodes. Switch where detected |
| DetectedDate | DateTime | When the rogue was first detected |
| Status | Int32 | Rogue status (Active, Acknowledged, etc.) |
| Vendor | String | Device vendor from OUI lookup |

### SWQL Navigation Properties

- **Port** navigates to Orion.UDT.Port
- **Node** navigates to Orion.Nodes

### Example SWQL Queries

**Active rogue endpoints with location:**

```sql
SELECT
    r.MACAddress,
    r.IPAddress,
    r.Vendor,
    r.Port.PortName AS [Port],
    r.Node.Caption AS [Switch],
    ToLocal(r.DetectedDate) AS [Detected]
FROM Orion.UDT.RogueEndpoints AS r
WHERE r.Status = 1
ORDER BY r.DetectedDate DESC
```

---

## Orion.UDT.Job (SWQL)

Represents a UDT discovery or polling job configuration.

### SWQL Properties

| Property | Type | Description |
|----------|------|-------------|
| JobID | Int32 | Primary key |
| JobName | String | Name of the discovery job |
| JobType | String | Job type (Discovery, Poll, etc.) |
| Enabled | Boolean | Whether the job is active |
| Schedule | String | Job schedule description |
| LastRun | DateTime | Last execution time |
| NextRun | DateTime | Next scheduled execution |
| Status | Int32 | Last execution status |

### Example SWQL Queries

**UDT job status overview:**

```sql
SELECT
    j.JobName,
    j.JobType,
    j.Enabled,
    ToLocal(j.LastRun) AS [Last Run],
    ToLocal(j.NextRun) AS [Next Run],
    j.Status
FROM Orion.UDT.Job AS j
ORDER BY j.NextRun
```

---

## Orion.UDT.Setting (SWQL)

Stores UDT module configuration settings as key-value pairs.

### SWQL Properties

| Property | Type | Description |
|----------|------|-------------|
| SettingID | String | Primary key. Setting name/identifier |
| Value | String | Current setting value |
| Description | String | What this setting controls |

### Example SWQL Queries

**View all UDT configuration settings:**

```sql
SELECT
    SettingID AS [Setting],
    Value,
    Description
FROM Orion.UDT.Setting
ORDER BY SettingID
```

---

## SWQL UDT Schema Discovery

Use these metadata queries to explore available UDT entities and properties at runtime:

```sql
-- List all UDT entities
SELECT FullName, EntityName
FROM Metadata.Entity
WHERE FullName LIKE 'Orion.UDT.%'
ORDER BY EntityName

-- List properties of a specific UDT entity
SELECT Name, Type, IsNavigable, IsKey
FROM Metadata.Property
WHERE EntityName = 'Orion.UDT.Port'
```
