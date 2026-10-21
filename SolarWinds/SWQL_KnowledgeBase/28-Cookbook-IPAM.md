# SWQL IPAM (IP Address Manager) Query Cookbook

## SWQL IPAM Queries

### Query: IP Address Conflicts

/* Counts the total number of IP address conflicts currently detected in IPAM, providing a quick health indicator for address space integrity. | Entities: `IPAM.Conflict` */

```sql
SELECT
    COUNT(*) AS [Conflict Count]
FROM
    IPAM.Conflict
```

**Key points**:
- A non-zero count indicates duplicate IP assignments that require investigation.
- Conflicts are detected during IPAM subnet scans and may involve overlapping DHCP leases or static assignments.
- Pair with the DNS Mismatch query for a complete address hygiene picture.

---

### Query: IP Address Requests by Status

/* Groups IP address requests by their current state (Pending, Completed, or Unknown) with a count for each, helping track the request fulfillment pipeline. | Entities: `IPAM.IPRequests` */

```sql
SELECT
    CASE
        WHEN State = 2 THEN 'Pending'
        WHEN State = 3 THEN 'Completed'
        ELSE 'Unknown'
    END AS [Status],
    COUNT(*) AS [Count]
FROM
    IPAM.IPRequests
GROUP BY
    State
```

**Key points**:
- State value 2 = Pending, 3 = Completed; other values are treated as Unknown.
- A large number of Pending requests may indicate a bottleneck in the IP provisioning workflow.
- IPAM IP request management must be enabled for this entity to contain data.

---

### Query: Scan Job Status by Type

/* Shows the number of subnets associated with each scan type (e.g., SNMP, ICMP, manual) by joining scan instances to their parent subnets, revealing how scanning is distributed across methods. | Entities: `IPAM.ScanInstance`, `IPAM.Subnet` */

```sql
SELECT DISTINCT
    s.GroupTypeText AS [Scan Type],
    COUNT(si.SubnetId) AS [Subnets]
FROM
    IPAM.ScanInstance AS si
JOIN
    IPAM.Subnet AS s ON s.SubnetId = si.SubnetId
GROUP BY
    s.GroupTypeText
```

**Key points**:
- `GroupTypeText` provides a human-readable label for the scan type rather than a numeric code.
- Useful for verifying that all subnets are being scanned and that the expected scan methods are in use.
- A scan type with zero subnets may indicate a misconfigured scan job.

---

### Query: Manage Roles and Permissions

/* Lists all IPAM account roles with their account type (System, SolarWinds, Windows Individual, Windows Group, etc.) and assigned role (Admin, Power User, Operator, Read Only, No Access). | Entities: `IPAM.AccountRoles` */

```sql
SELECT DISTINCT
    AccountID AS [Account Name],
    CASE
        WHEN AccountType = '0' THEN 'System Account'
        WHEN AccountType = '1' THEN 'SolarWinds Account'
        WHEN AccountType = '2' THEN 'Windows Individual Account'
        WHEN AccountType = '3' THEN 'Windows Group Account'
        WHEN AccountType = '4' THEN 'Windows Group User Account'
        ELSE 'Unknown'
    END AS [Account Type],
    CASE
        WHEN Admin IS NOT NULL THEN 'Admin'
        WHEN PowerUser IS NOT NULL THEN 'Power User'
        WHEN Operator IS NOT NULL THEN 'Operator'
        WHEN ReadOnly IS NOT NULL THEN 'Read Only'
        WHEN NoAccess IS NOT NULL THEN 'No Access'
        ELSE 'Unknown'
    END AS [Role]
FROM
    IPAM.AccountRoles
ORDER BY
    [Account Type] ASC
```

**Key points**:
- The role columns (Admin, PowerUser, etc.) are non-null when the account holds that role.
- The CASE priority means an account with both Admin and Operator will show as Admin.
- Useful for RBAC audits and verifying least-privilege access to IPAM.

---

### Query: Retention Settings

/* Displays the configured retention periods for IPAM events and IP history, showing both the custom value (if set) and the default fallback. | Entities: `IPAM.Setting` */

```sql
SELECT
    DISTINCT CASE
        WHEN Name = 'Events.MaxLife' THEN 'IPAM Events'
        ELSE 'IPAM Events (Default)'
    END AS [Retention Name],
    CASE
        WHEN Value IS NULL THEN '90 Days'
        ELSE CONCAT(ToString(Value), ' Days')
    END AS [Retention Interval]
FROM
    IPAM.Setting
WHERE
    Name = 'Events.MaxLife'

UNION ALL

(SELECT
    DISTINCT CASE
        WHEN Name = 'IPHistory.MaxLife' THEN 'History'
        ELSE 'History (Default)'
    END AS [Retention Name],
    CASE
        WHEN Value IS NULL THEN '365 Days'
        ELSE CONCAT(ToString(Value), ' Days')
    END AS [Retention Interval]
 FROM
    IPAM.Setting
 WHERE
    Name = 'IPHistory.MaxLife')
```

**Key points**:
- Default retention is 90 days for events and 365 days for IP history when no custom value is set.
- Reducing retention can help manage database growth; increasing it preserves audit trail.
- `ToString()` is used because the Value column may be a non-string type.

---

### Query: Scan Interval Settings

/* Reports the scan interval configuration for each subnet group type, showing how many groups use each interval and the interval in hours, excluding groups with auto-scanning disabled. | Entities: `IPAM.GroupReport` */

```sql
SELECT
    Grouptypetext AS [Type],
    COUNT(GroupID) AS [Count],
    CONCAT(TOSTRING(ScanInterval / 60), ' hrs') AS [Scan Interval]
FROM
    IPAM.GroupReport
WHERE
    ScanInterval > 60
    AND DisableAutoScanning <> 'true'
GROUP BY
    Grouptypetext,
    ScanInterval
```

**Key points**:
- `ScanInterval` is stored in minutes; dividing by 60 converts to hours for readability.
- The filter `ScanInterval > 60` excludes sub-minute intervals that would be unusual in production.
- Groups with auto-scanning disabled are excluded to focus on actively scanned subnets.

---

### Query: Total Subnets

/* Counts the total number of subnets managed in IPAM, providing a high-level sizing metric. | Entities: `IPAM.Subnet` */

```sql
SELECT
    COUNT(*) AS [Total Subnets]
FROM
    IPAM.Subnet
```

**Key points**:
- A simple count useful for licence capacity checks and environment sizing.
- Includes all subnet types (IPv4, IPv6, supernets) managed within IPAM.
- Combine with the Scan Job Status query to verify all subnets have active scan instances.

---

### Query: Subnet Usage Thresholds

/* Displays the configured warning and critical threshold percentages for subnet usage, along with the description of what each threshold triggers. | Entities: `IPAM.Setting` */

```sql
SELECT
    DISTINCT CASE
        WHEN Name = 'Threshold.SubnetUsageWarning' THEN 'Warning'
        ELSE 'Warning (Default)'
    END AS [Threshold Level],
    CASE
        WHEN Value IS NULL THEN '60 %'
        ELSE CONCAT(ToString(Value), ' %')
    END AS [Threshold Value],
    'Subnet or supernet with IP address space percentage used above this level will appear with "Warning" status.' AS [Description]
FROM
    IPAM.Setting
WHERE
    Name = 'Threshold.SubnetUsageWarning'

UNION ALL

(SELECT
    DISTINCT CASE
        WHEN Name = 'Threshold.SubnetUsageCritical' THEN 'Critical'
        ELSE 'Critical (Default)'
    END AS [Threshold Level],
    CASE
        WHEN Value IS NULL THEN '80 %'
        ELSE CONCAT(ToString(Value), ' %')
    END AS [Threshold Value],
    'Subnet or supernet with IP address space percentage used above this level will appear with "Critical" status.' AS [Description]
 FROM
    IPAM.Setting
 WHERE
    Name = 'Threshold.SubnetUsageCritical')
```

**Key points**:
- Default thresholds are 60% for Warning and 80% for Critical when no custom values are set.
- Adjusting these thresholds affects how subnets are colour-coded in the IPAM web console.
- Lowering the warning threshold provides earlier visibility into subnets approaching exhaustion.

---

### Query: VMware vRealize Orchestrator Integration

/* Lists all nodes registered with the VMware vRealize Orchestrator integration, showing their configuration details such as product type, site, status, and API-only flag. | Entities: `Orion.Orchestrators.Nodes` */

```sql
SELECT
    NodeID,
    OrchestratorNodeID,
    DeviceID,
    ProductType,
    SiteID,
    Caption,
    Status,
    IsApiOnly,
    DetailsUrl
FROM
    Orion.Orchestrators.Nodes
```

**Key points**:
- Returns an empty result set if the vRealize Orchestrator integration is not configured.
- `IsApiOnly` indicates whether the node is managed exclusively through API calls.
- The `DetailsUrl` column provides a direct link to the orchestrator node's detail page.

---

### Query: DHCP Servers and Scope Counts

/* Lists each DHCP server monitored by IPAM along with the number of DHCP scopes associated with it, ordered alphabetically by server name. | Entities: `Orion.Nodes`, `IPAM.DhcpServer`, `IPAM.DhcpScope` */

```sql
SELECT
    server.DisplayName AS [DHCP Server],
    COUNT(scope.DisplayName) AS [Scope Count]
FROM
    Orion.Nodes AS n
    JOIN IPAM.DhcpServer AS server ON server.NodeId = n.NodeID
    JOIN IPAM.DhcpScope AS scope ON scope.NodeId = n.NodeID
GROUP BY
    server.DisplayName
ORDER BY
    server.DisplayName
```

**Key points**:
- Joins through `Orion.Nodes` to link DHCP servers to their scopes via the shared NodeID.
- Useful for verifying that all expected DHCP servers and scopes are being monitored.
- A server with zero scopes may indicate a configuration issue or a recently added server.

---

### Query: DNS Servers with Zones

/* Lists each DNS server and its associated DNS zones, providing a complete inventory of DNS infrastructure monitored by IPAM. | Entities: `Orion.Nodes`, `IPAM.DNSServer`, `IPAM.DnsZone` */

```sql
SELECT DISTINCT
    server.DisplayName AS [DNS Server],
    zone.DisplayName AS [DNS Zone]
FROM
    Orion.Nodes AS n
JOIN
    IPAM.DNSServer AS server ON server.NodeId = n.NodeID
JOIN
    IPAM.DnsZone AS zone ON zone.NodeId = n.NodeID
```

**Key points**:
- `DISTINCT` prevents duplicate rows when multiple zone records exist for the same server-zone pair.
- Useful for verifying that all expected DNS zones are being monitored and for identifying orphaned zones.
- DNS monitoring must be enabled in IPAM for these entities to be populated.

---

### Query: DNS Mismatch Count

/* Counts the total number of DNS mismatches detected by IPAM, where forward and reverse DNS records do not agree. | Entities: `IPAM.DNSMismatch` */

```sql
SELECT
    COUNT(*) AS [DNS Mismatch Count]
FROM
    IPAM.DNSMismatch
```

**Key points**:
- DNS mismatches occur when a forward lookup (A record) and reverse lookup (PTR record) return inconsistent results.
- A non-zero count should trigger a review of DNS records to prevent name resolution issues.
- Pair with the IP Conflicts query for a comprehensive address hygiene assessment.

---



