# SWQL NPM (Network Performance Monitor) Query Cookbook

## SWQL NPM Queries

### Query: Interface Cleanup Candidates

/* Identifies noise interfaces (loopback, null, unrouted, uncontrolled, virtual, POTS). Entities: Orion.NPM.Interfaces */

```sql
SELECT 'Loopback' AS [Interface Type], COUNT(*) AS [Count]
FROM Orion.NPM.Interfaces
WHERE Caption LIKE '%loopback%'

UNION ALL

(SELECT 'Null' AS [Interface Type], COUNT(*) AS [Count]
FROM Orion.NPM.Interfaces
WHERE Caption LIKE '%null%')

UNION ALL

(SELECT 'Unrouted' AS [Interface Type], COUNT(*) AS [Count]
FROM Orion.NPM.Interfaces
WHERE Caption LIKE '%unrouted%')

UNION ALL

(SELECT 'Uncontrolled' AS [Interface Type], COUNT(*) AS [Count]
FROM Orion.NPM.Interfaces
WHERE Caption LIKE '%uncontrolled%')

UNION ALL

(SELECT 'Windows' AS [Interface Type], COUNT(*) AS [Count]
FROM Orion.NPM.Interfaces
WHERE Caption LIKE '%0000%')

UNION ALL

(SELECT 'POTS' AS [Interface Type], COUNT(*) AS [Count]
FROM Orion.NPM.Interfaces
WHERE Caption LIKE '%pots%')
```

### Query: NetPath Services Status

/* Lists NetPath service assignments with probe status (0=Unknown, 1=Up, 2=Warning, 100=Critical, etc) and last probed time offset. */

```sql
SELECT
    sa.ServiceName AS [Service name],
    sa.ProbeName AS [From],
    CASE
        WHEN enabled = 0 THEN 'Disabled'
        WHEN sa.Probe.Status = 0 THEN 'Unknown'
        WHEN sa.Probe.Status = 1 THEN 'Up'
        WHEN sa.Probe.Status = 2 THEN 'Warning'
        WHEN sa.Probe.Status = 100 THEN 'Critical'
        WHEN sa.Probe.Status = 102 THEN 'DNSError'
        WHEN sa.Probe.Status = 103 THEN 'HostUnreachable'
        WHEN sa.Probe.Status = 104 THEN 'PortClosed'
        WHEN sa.Probe.Status = 101 THEN 'ProbeDown'
        WHEN sa.Probe.Status = 106 THEN 'UnsupportedOS'
        WHEN sa.Probe.Status = 107 THEN 'AgentFailed'
        WHEN sa.Probe.Status = 108 THEN 'JobFailure'
        WHEN sa.Probe.Status = 109 THEN 'NotLicensed'
    END AS [Status],
    CASE
        WHEN MONTHDIFF(tolocal(lastprobetime), getdate()) > 1
            THEN CONCAT(MONTHDIFF(tolocal(lastprobetime), getdate()), ' months ago')
        WHEN DAYDIFF(tolocal(lastprobetime), getdate()) > 1
            THEN CONCAT(DAYDIFF(tolocal(lastprobetime), getdate()), ' days ago')
        WHEN HOURDIFF(tolocal(lastprobetime), getdate()) > 1
            THEN CONCAT(HOURDIFF(tolocal(lastprobetime), getdate()), ' hours ago')
        ELSE CONCAT(MINUTEDIFF(tolocal(lastprobetime), getdate()), ' minutes ago')
    END AS [Last Probed]
FROM Orion.NetPath.ServiceAssignments sa
```

**Key points**:
- Status codes 100-109 cover NetPath-specific error conditions beyond the standard node status values.
- Uses `tolocal()` to convert stored UTC timestamps to the user's local time before computing differences.
- Probes that are disabled (`enabled = 0`) are surfaced separately from status-based issues.

---

### Query: Network Insight (CLI) -- Enabled Features

/* Shows nodes with Network Insight features (ASA, Nexus vPC, F5 Big-IP). Entities: Orion.Nodes, Orion.ASA.Node, Orion.Nexus, Orion.F5 */

```sql
SELECT TOP 100
    n.caption,
    n.ipaddress,
    CASE WHEN asa.NodeID IS NOT NULL THEN 'yes' ELSE 'no' END AS [ASA Enabled],
    CASE WHEN nexus.NodeID IS NOT NULL THEN 'yes' ELSE 'no' END AS [Nexus Enabled],
    CASE WHEN f5.NodeID IS NOT NULL THEN 'yes' ELSE 'no' END AS [Big IP Enabled]
FROM Orion.Nodes n
LEFT JOIN Orion.ASA.Node asa ON asa.NodeID = n.NodeID
LEFT JOIN Orion.Nexus.VirtualPortChannel nexus ON nexus.NodeID = n.NodeID
LEFT JOIN Orion.F5.System.Device f5 ON f5.NodeID = n.NodeID
WHERE asa.NodeID IS NOT NULL
   OR nexus.NodeID IS NOT NULL
   OR f5.NodeID IS NOT NULL
```

### Query: Nodes with Out-of-Date Polling

/* Finds nodes with LastSync > 1 day old (stale polling data). Entities: Orion.Nodes */

```sql
SELECT NodeID, Caption, LastSync
FROM Orion.Nodes
WHERE DAYDIFF(LastSync, GETUTCDATE()) > 1
```

**Key points**:
- `DAYDIFF` computes the number of whole days between the two timestamps.
- Adjust the threshold (`> 1`) to match your environment's tolerance for polling lag.
- Useful for health-check dashboards and automated alerting reports.

---

### Query: PerfStack User Projects
### Query: PerfStack User Projects

/* Lists user-created PerfStack projects (excludes _system account). Entities: Orion.PerfStack.Projects */
- The `_system` account owns default/built-in PerfStack projects; filtering it out shows only projects created by real users.
- Helpful for auditing PerfStack adoption across your team.

---

### Query: QoE Probes and Protocols

### Query: QoE Probes and Protocols

/* Reports QoE probe counts (total/enabled) and discovered protocols per probe. Entities: Orion.DPI.Probes, Orion.DPI.Applications */
(SELECT 'Enabled Probes' AS [Metric],
        CONCAT(ISNULL(COUNT(*), 0), '') AS [Value]
 FROM Orion.DPI.Probes
 WHERE enabled = 1)

UNION ALL

(SELECT CONCAT('    ', name) AS [Metric],
        CONCAT((SELECT COUNT(*) FROM Orion.DPI.Applications
                WHERE LastDiscoveryProbeID = p.ProbeID), ' protocols') AS [Value]
 FROM Orion.DPI.Probes p
 WHERE enabled = 1)
```

**Key points**:
- Uses a correlated subquery to count protocols per probe.
- The indented probe names (prefixed with spaces) create a visual hierarchy in results.
- QoE / DPI requires the NPM QoE licence add-on.

---

### Query: Universal Device Pollers (UnDP) Summary

/* Provides a consolidated summary of Universal Device Pollers (UnDP): total count, enabled count, and -- for each enabled poller -- the number of assigned nodes and polling interval. | Entities: `Orion.Nodes`, `Orion.NPM.CustomPollers`, `Orion.NPM.CustomPollerAssignment` */

```sql
SELECT TOP 1 '=== UnDP ===' AS [Metric], '' AS [Value]
FROM Orion.Nodes

UNION ALL

(SELECT 'TOTAL UnDP' AS [Metric],
        CONCAT(ISNULL(COUNT(*), 0), '') AS [Value]
 FROM Orion.NPM.CustomPollers)

UNION ALL

(SELECT 'Enabled UnDP' AS [Metric],
        CONCAT(ISNULL(COUNT(*), 0), '') AS [Value]
 FROM Orion.NPM.CustomPollers
 WHERE enabled = 1)

UNION ALL

(SELECT TOP 1 '=== UnDP: Poller, num of nodes, interval ===' AS [Metric],
        '' AS [Value]
 FROM Orion.Nodes)

UNION ALL

(SELECT
    CONCAT('UnDP: ', cp.GroupName, ' - ', cpa.custompollername) AS [Metric],
    CASE
        WHEN cp.PollInterval != 0
            THEN CONCAT(ISNULL(COUNT(cpa.nodeid), 0), ' nodes  at ', cp.PollInterval, ' mins')
        ELSE CONCAT(ISNULL(COUNT(cpa.nodeid), 0), ' nodes  at ', n.StatCollection, ' mins')
    END AS [Value]
 FROM Orion.NPM.CustomPollerAssignment cpa
 JOIN Orion.NPM.CustomPollers cp ON cp.CustomPollerID = cpa.CustomPollerID
 JOIN Orion.Nodes n ON n.nodeid = cpa.NodeID
 WHERE cpa.status = 1
 GROUP BY cpa.CustomPollerName, cp.GroupName, cp.PollInterval, n.StatCollection)
```

**Key points**:
- When a poller's own `PollInterval` is 0, it inherits the node's `StatCollection` interval instead.
- Only active assignments (`status = 1`) are counted.
- The separator rows (`=== ... ===`) are cosmetic headings for report readability.

---

### Query: Wireless Summary (Basic)

/* Provides a quick count of wireless controllers, access points (with per-AP client counts), and rogue APs across the entire environment. | Entities: `Orion.Wireless.Controllers`, `Orion.Wireless.AccessPoints`, `Orion.Wireless.Rogue` */

```sql
SELECT 'Controllers' AS [Metric], ISNULL(COUNT(*), 0) AS [Value]
FROM Orion.Wireless.Controllers

UNION ALL

(SELECT 'Access Points' AS [Metric], ISNULL(COUNT(*), 0) AS [Value]
 FROM Orion.Wireless.AccessPoints)

UNION ALL

(SELECT CONCAT('    ', ap.DisplayName) AS [Metric],
        CONCAT(ap.Clients, ' ') AS [Value]
 FROM Orion.Wireless.AccessPoints ap)

UNION ALL

(SELECT 'Rogue APs' AS [Metric], ISNULL(COUNT(*), 0) AS [Value]
 FROM Orion.Wireless.Rogue)
```

**Key points**:
- Individual access points are listed with indentation under the "Access Points" total.
- Rogue AP detection requires a supported wireless controller.
- This is the lightweight version; see the vendor-grouped variant below for multi-vendor environments.

---

### Query: Wireless Summary by Vendor

/* Extends the wireless summary by grouping controllers, access points, and rogue APs by hardware vendor, which is useful for multi-vendor wireless environments. | Entities: `Orion.Wireless.Controllers`, `Orion.Wireless.AccessPoints`, `Orion.Wireless.Rogue`, `Orion.Nodes` */

```sql
-- Controllers
SELECT 'Controllers' AS [Metric], ISNULL(COUNT(*), 0) AS [Value], n.Vendor
FROM Orion.Wireless.Controllers wc
LEFT JOIN Orion.Nodes n ON wc.NodeID = n.NodeID
GROUP BY n.Vendor

UNION ALL

(SELECT wc.DisplayName AS [Metric], ISNULL(COUNT(*), 0) AS [Value], n.Vendor
 FROM Orion.Wireless.Controllers wc
 LEFT JOIN Orion.Nodes n ON wc.NodeID = n.NodeID
 GROUP BY n.Vendor, wc.DisplayName)

UNION ALL

-- Access Points
(SELECT 'Access Points' AS [Metric], ISNULL(COUNT(*), 0) AS [Value], n.Vendor
 FROM Orion.Wireless.AccessPoints ap
 LEFT JOIN Orion.Nodes n ON ap.NodeID = n.NodeID
 GROUP BY n.Vendor)

UNION ALL

-- Individual Access Points with Clients
(SELECT CONCAT('    ', ap.DisplayName) AS [Metric],
        CONCAT(ap.Clients, ' ') AS [Value], n.Vendor
 FROM Orion.Wireless.AccessPoints ap
 LEFT JOIN Orion.Nodes n ON ap.NodeID = n.NodeID
 GROUP BY ap.DisplayName, ap.Clients, n.Vendor)

UNION ALL

-- Rogue Access Points
(SELECT 'Rogue APs' AS [Metric], ISNULL(COUNT(*), 0) AS [Value], n.Vendor
 FROM Orion.Wireless.Rogue r
 LEFT JOIN Orion.Nodes n ON r.NodeID = n.NodeID
 GROUP BY n.Vendor)
```

**Key points**:
- Joins wireless entities back to `Orion.Nodes` to pull the `Vendor` field.
- Results can be filtered by vendor to produce per-vendor wireless health reports.
- Individual controller and access point names are listed under their respective summary rows.

---


