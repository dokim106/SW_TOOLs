# SWQL UDT (User Device Tracker) Query Cookbook

## SWQL UDT Queries

### Query: Active Directory Domain Controllers

/* Counts UDT nodes with Active Directory domain controller scanning capability (Capability 8), grouped by polling status (Up vs. Failed). | Entities: `Orion.UDT.NodeCapability` */

```sql
SELECT
  COUNT(NodeID) AS [Total],
  CASE
    WHEN LastScanResult = 1 THEN 'Up'
    ELSE 'Failed'
  END AS [Polling Status]
FROM
  Orion.UDT.NodeCapability
WHERE
  Capability = '8'
GROUP BY
  CASE
    WHEN LastScanResult = 1 THEN 'Up'
    ELSE 'Failed'
  END
```


---

### Query: Check for Rogue Devices

/* Counts rogue device detections across four categories -- Rogue DNS, Rogue Empty DNS, Rogue IP, and Rogue MAC -- using a UNION ALL across their respective alert tables. | Entities: `Orion.UDT.RogueDNSAlert`, `Orion.UDT.RogueEmptyDNSAlert`, `Orion.UDT.RogueIPAlert`, `Orion.UDT.RogueMACAlert` */

```sql
SELECT
  'Rogue DNS' AS Rogue_Type,
  SUM(CASE WHEN rogue = 'True' THEN 1 ELSE 0 END) AS [Total]
FROM
  Orion.UDT.RogueDNSAlert

UNION ALL

(SELECT
  'Rogue Empty DNS' AS Rogue_Type,
  SUM(CASE WHEN rogue = '1' THEN 1 ELSE 0 END) AS [Total]
FROM
  Orion.UDT.RogueEmptyDNSAlert)

UNION ALL

(SELECT
  'Rogue IP' AS Rogue_Type,
  SUM(CASE WHEN rogue = 'True' THEN 1 ELSE 0 END) AS [Total]
FROM
  Orion.UDT.RogueIPAlert)

UNION ALL

(SELECT
  'Rogue MAC' AS Rogue_Type,
  SUM(CASE WHEN rogue = 'True' THEN 1 ELSE 0 END) AS [Total]
FROM
  Orion.UDT.RogueMACAlert)
```


---

### Query: Credentials List

/* Lists all credential sets owned by UDT, showing which named credentials are configured for UDT device polling. | Entities: `Orion.Credential` */

```sql
SELECT
  Name
FROM
  Orion.Credential
WHERE
  credentialowner = 'udt'
```


---

### Query: Data Retention Settings

/* Shows UDT data retention settings including the current and default values, controlling how long endpoint tracking data is preserved. | Entities: `Orion.UDT.Setting` */

```sql
SELECT
  SettingName AS [Name],
  DefaultValue AS [Default Setting],
  SettingValue AS [Current Setting]
FROM
  Orion.UDT.Setting
WHERE
  settingname LIKE '%retention%'
```


---

### Query: Job Status

/* Summarizes UDT polling job results by layer type (Layer 2 / Layer 3), showing counts of successful and failed jobs. | Entities: `Orion.UDT.Job` */

```sql
SELECT
  CONCAT('Layer ', JobType) AS [Job Type],
  SUM(CASE WHEN JobLastResult != 1 THEN 1 ELSE 0 END) AS [Error],
  SUM(CASE WHEN JobLastResult = 1 THEN 1 ELSE 0 END) AS [Success]
FROM
  Orion.UDT.Job
GROUP BY
  JobType
```


---

### Query: Monitored Devices and Ports

/* Counts the number of UDT-monitored devices and their monitored ports, grouped by vendor. | Entities: `Orion.Nodes`, `Orion.UDT.Port` */

```sql
SELECT
  Nodes.Vendor AS [Vendor],
  COUNT(Nodes.Vendor) AS [Total Devices],
  COUNT(Ports.IsMonitored) AS [Total Ports Monitored]
FROM
  Orion.Nodes AS Nodes
  JOIN Orion.UDT.Port AS Ports ON Ports.nodeid = Nodes.nodeid
GROUP BY
  Nodes.Vendor
```


---

### Query: Polling Intervals

/* Shows UDT polling interval settings including the current and default values for each interval type. | Entities: `Orion.UDT.Setting` */

```sql
SELECT
  SettingName AS [Name],
  DefaultValue AS [Default Setting],
  SettingValue AS [Current Setting]
FROM
  Orion.UDT.Setting
WHERE
  settingname LIKE '%pollinginterval%'
```


---

### Query: Thresholds

/* Retrieves UDT alert thresholds from Orion global settings, showing current and default values for both critical (high) and warning levels, with a flag when values differ from defaults. | Entities: `Orion.Settings` */

```sql
SELECT
  SUBSTRING(Name, 1, CharIndex(' - ', Name)) AS [Name],

  MAX(CASE
    WHEN Name LIKE '%high%' THEN CONCAT(CurrentValue, Units)
  END) AS [Current Critical Setting],

  MAX(CASE
    WHEN Name LIKE '%high%' AND CurrentValue <> DefaultValue
      THEN CONCAT(ToString(DefaultValue), Units)
    WHEN Name LIKE '%high%' AND CurrentValue = DefaultValue
      THEN 'Same'
  END) AS [Default Critical Setting],

  MAX(CASE
    WHEN Name LIKE '%Warning%' THEN CONCAT(CurrentValue, Units)
  END) AS [Current Warning Setting],

  MAX(CASE
    WHEN Name LIKE '%Warning%' AND CurrentValue <> DefaultValue
      THEN CONCAT(ToString(DefaultValue), Units)
    WHEN Name LIKE '%Warning%' AND CurrentValue = DefaultValue
      THEN 'Same'
  END) AS [Default Warning Setting]
FROM
  Orion.Settings
WHERE
  SettingID LIKE '%udt%'
GROUP BY
  SUBSTRING(Name, 1, CharIndex(' - ', Name))
```


---

### Query: Watch List

/* Summarizes the UDT watch list by item type (MAC Address, IP Address, Hostname, Username), showing total count, number found on the network, and number currently active. | Entities: `Orion.UDT.WatchList`, `Orion.UDT.WatchListAggregated`, `Orion.UDT.WatchListPresent` */

```sql
SELECT
  CASE
    WHEN wl.WatchItemType = 1 THEN 'MAC Address'
    WHEN wl.WatchItemType = 2 THEN 'IP Address'
    WHEN wl.WatchItemType = 3 THEN 'Hostname'
    WHEN wl.WatchItemType = 4 THEN 'Username'
    ELSE 'Unknown'
  END AS Watchlist_Item_Type,
  COUNT(*) AS Count_of_Each_Type,
  SUM(CASE WHEN wla.IsFound = '1' THEN 1 ELSE 0 END) AS Count_of_Found,
  SUM(CASE WHEN wla.IsActive = '1' THEN 1 ELSE 0 END) AS Count_of_Active
FROM
  Orion.UDT.WatchList AS wl
  JOIN Orion.UDT.WatchListAggregated AS wla ON wla.WatchID = wl.WatchID
  JOIN Orion.UDT.WatchListPresent AS wp ON wp.WatchID = wl.WatchID
GROUP BY
  wl.WatchItemType
```


---

### Query: White List (Whitelisted Devices Count)

/* Counts the total number of MAC addresses that are whitelisted (not flagged as rogue) in UDT endpoint tracking. | Entities: `Orion.UDT.Endpoint` */

```sql
SELECT DISTINCT
  COUNT(MACAddress) AS [Devices Whitelisted]
FROM
  Orion.UDT.Endpoint
WHERE
  Rogue = 'False'
```

**Key points**: Whitelisted endpoints have `Rogue = 'False'`, meaning they are recognized as authorized devices. Compare this count against total endpoints to gauge whitelist coverage. Endpoints not whitelisted will trigger rogue device alerts if rogue detection is enabled.



