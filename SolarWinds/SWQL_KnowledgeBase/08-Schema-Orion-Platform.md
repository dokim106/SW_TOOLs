# SWQL Orion Platform Entity Schema Reference

---

## Orion.Nodes Entity Schema (SWQL)

Central entity for all monitored devices in Orion (SNMP, WMI, ICMP; ~80 properties, 64 nav props, 3 verbs).

### Properties (Orion.Nodes)

#### Identity and Naming

| Name | Type | Description |
|------|------|-------------|
| NodeID | Int32 | **Primary key.** Unique identifier for the node. Auto-incremented on creation. |
| Caption | String | Display name shown in the Orion web console. Typically set to hostname or FQDN during discovery. |
| IPAddress | String | Primary IP address of the monitored node. |
| IPAddressType | String | Address family indicator (`IPv4` or `IPv6`). |
| DNS | String | DNS hostname resolved for the node's IP address. |
| SysName | String | SNMP sysName value retrieved from the device MIB-II system group. |
| DisplayName | String | Computed display name used in UI rendering. May differ from Caption when aliased. |
| Uri | String | SWIS URI for the node entity instance (e.g., `swis://hostname/Orion/Orion.Nodes/NodeID=42`). |
| DetailsUrl | String | Relative URL path to the node details page in the Orion web console. |

#### Classification and Inventory

| Name | Type | Description |
|------|------|-------------|
| Vendor | String | Hardware vendor name (e.g., `Cisco`, `Windows`, `Linux`). Populated via SNMP sysObjectID mapping. |
| MachineType | String | Device model or platform description derived from SNMP sysDescr or sysObjectID. |
| SysObjectID | String | SNMP sysObjectID OID string identifying the device type (e.g., `1.3.6.1.4.1.9.1.544`). |
| Location | String | SNMP sysLocation value from the device MIB-II system group. |
| Contact | String | SNMP sysContact value from the device MIB-II system group. |
| ObjectSubType | String | Polling method or node sub-type: `SNMP`, `WMI`, `ICMP`, `Agent`, or `External`. |
| Category | Int32 | Numeric category code used internally for node classification. |
| IsServer | Boolean | True if the node is classified as a server (vs. network device). |
| IsOrionServer | Boolean | True if this node is the Orion platform server itself. |

#### Software and Firmware

| Name | Type | Description |
|------|------|-------------|
| IOSImage | String | Firmware or OS image filename (e.g., Cisco IOS image name). |
| IOSVersion | String | Firmware or OS version string reported by the device. |

#### Status and Availability

| Name | Type | Description |
|------|------|-------------|
| Status | Int32 | Numeric status code: 1=Up, 2=Down, 3=Warning, 9=Unmanaged, 12=Unreachable, 14=Critical, etc. |
| StatusDescription | String | Human-readable status label (e.g., `Up`, `Down`, `Warning`, `Critical`). |
| StatusLED | String | Filename or path reference for the status icon displayed in the web console. |
| CustomStatus | Boolean | True if the node status has been manually overridden by an administrator. |

#### Uptime and Response

| Name | Type | Description |
|------|------|-------------|
| LastBoot | DateTime | Timestamp of the last device reboot, derived from SNMP sysUpTime or WMI. |
| SystemUpTime | Double | Current system uptime in seconds since last boot. |
| ResponseTime | Int32 | Most recent ICMP ping response time in milliseconds. |
| PercentLoss | Double | Most recent packet loss percentage (0-100). |
| AvgResponseTime | Int32 | Average response time in milliseconds over the current polling period. |
| MinResponseTime | Int32 | Minimum response time in milliseconds over the current polling period. |
| MaxResponseTime | Int32 | Maximum response time in milliseconds over the current polling period. |

#### CPU and Memory

| Name | Type | Description |
|------|------|-------------|
| CPUCount | Int16 | Number of CPU cores or processors detected on the node. |
| CPULoad | Int32 | Current CPU utilization percentage (0-100). |
| MemoryUsed | Double | Amount of memory currently in use, in bytes. |
| MemoryAvailable | Double | Amount of memory currently available, in bytes. |
| TotalMemory | Single | Total installed physical memory, in bytes. |
| PercentMemoryUsed | Int32 | Memory utilization percentage (0-100). |
| PercentMemoryAvailable | Int32 | Memory availability percentage (0-100). |
| LoadAverage1 | Double | 1-minute load average (Linux/Unix nodes only). |
| LoadAverage5 | Double | 5-minute load average (Linux/Unix nodes only). |
| LoadAverage15 | Double | 15-minute load average (Linux/Unix nodes only). |

#### Polling Configuration

| Name | Type | Description |
|------|------|-------------|
| SNMPVersion | Int16 | SNMP version in use: 0=None, 1=SNMPv1, 2=SNMPv2c, 3=SNMPv3. |
| PollInterval | Int32 | Polling interval for this node in seconds (default 120). |
| EngineID | Int32 | Foreign key to `Orion.Engines`. Identifies which polling engine monitors this node. |
| LastSync | DateTime | Timestamp of the last successful data synchronization for this node. |
| LastSystemUpTimePollUtc | DateTime | UTC timestamp of the last successful sysUpTime poll. |
| NextPoll | DateTime | Scheduled timestamp for the next poll cycle. |

#### Unmanage Window

| Name | Type | Description |
|------|------|-------------|
| UnManaged | Boolean | True if the node is currently in an unmanaged state (polling suspended). |
| UnManageFrom | DateTime | Start of the unmanage window. Null if not scheduled. |
| UnManageUntil | DateTime | End of the unmanage window. Null for indefinite unmanage. |

### Navigation Properties (Orion.Nodes)

| Navigation Property | Target Entity | Cardinality | Description |
|---------------------|---------------|-------------|-------------|
| Interfaces | Orion.NPM.Interfaces | 0..* | Network interfaces monitored on this node. |
| Volumes | Orion.Volumes | 0..* | Disk volumes monitored on this node. |
| CustomProperties | Orion.NodesCustomProperties | 0..1 | Custom property values assigned to this node. |
| Applications | Orion.APM.Application | 0..* | SAM/APM application monitors assigned to this node. |
| Engine | Orion.Engines | 0..1 | The polling engine responsible for this node. |
| Events | Orion.Events | 0..* | Event log entries associated with this node. |
| AlertObjects | Orion.AlertObjects | 0..* | Alert object bindings for this node. |
| ActiveAlerts | Orion.ActiveAlerts | 0..* | Currently active (triggered) alerts on this node. |
| ResponseTimeHistory | Orion.ResponseTime | 0..* | Historical response time data points for this node. |
| CPULoadHistory | Orion.CPULoad | 0..* | Historical CPU utilization data points for this node. |
| Syslogs | Orion.SysLog | 0..* | Syslog messages received from this node. |
| Traps | Orion.Traps | 0..* | SNMP trap messages received from this node. |
| Ports | Orion.UDT.Port | 0..* | UDT switch port records associated with this node. |
| VirtualMachine | Orion.VIM.VirtualMachines | 0..* | Virtual machines hosted on or representing this node. |
| Host | Orion.VIM.Hosts | 0..1 | VMAN host record if this node is a virtualization host. |
| NodeProperties | NCM.NodeProperties | 0..1 | NCM configuration management properties for this node. |
| NetflowSources | Orion.Netflow.Source | 0..* | NTA NetFlow source associations for this node. |
| Router | Orion.Routing.Router | 0..1 | Routing topology record for this node. |

### Verbs (Orion.Nodes)

Verbs are SWIS operations invoked via the Invoke endpoint or `Invoke-SwisVerb` in PowerShell.

| Unmanage | N:NetObjectID, Start:DateTime, End:DateTime, IsRelative:Boolean | Suspends polling for the node during the specified window. |
| Remanage | N:NetObjectID | Resumes polling for a previously unmanaged node. |
| PollNow | N:NetObjectID | Forces an immediate poll cycle for the node. |

### Example Queries (Orion.Nodes)

**List all nodes with status, IP, and machine type:**

```sql
SELECT NodeID, Caption, IPAddress, Status, StatusDescription,
       Vendor, MachineType, ObjectSubType
FROM Orion.Nodes
ORDER BY Caption
```

**Find down nodes with last boot time and response metrics:**

```sql
SELECT Caption, IPAddress, StatusDescription,
       LastBoot, ResponseTime, PercentLoss
FROM Orion.Nodes
WHERE Status = 2
ORDER BY Caption
```

**High CPU or memory utilization nodes (threshold alert review):**

```sql
SELECT Caption, IPAddress, CPULoad, PercentMemoryUsed,
       Vendor, MachineType
FROM Orion.Nodes
WHERE CPULoad > 90 OR PercentMemoryUsed > 95
ORDER BY CPULoad DESC
```

**Nodes with custom properties via navigation traversal:**

```sql
SELECT n.Caption, n.IPAddress, n.Status,
       n.CustomProperties.City,
       n.CustomProperties.Department
FROM Orion.Nodes n
WHERE n.CustomProperties.City IS NOT NULL
ORDER BY n.CustomProperties.City, n.Caption
```

**Currently unmanaged nodes with their unmanage windows:**

```sql
SELECT Caption, IPAddress, UnManageFrom, UnManageUntil
FROM Orion.Nodes
WHERE UnManaged = TRUE
ORDER BY UnManageFrom DESC
```

---

## Orion.Engines Entity Schema (SWQL)

The `Orion.Engines` entity represents all polling engines in the SolarWinds Orion infrastructure, including the main polling engine and any Additional Polling Engines (APEs). Each engine is responsible for polling a subset of monitored nodes, interfaces, and volumes.

### Properties (Orion.Engines)

Polling engines (main + Additional Polling Engines); responsible for node/interface/volume polling assignment
|------|------|-------------|
| EngineID | Int32 | **Primary key.** Unique identifier for the polling engine. Engine 1 is typically the main server. |
| ServerName | String | Hostname of the server running the polling engine. |
| IP | String | IP address of the polling engine server. |
| ServerType | String | Engine role: `Master` (main polling engine) or `Additional` (APE). |
| EngineVersion | String | Software version of the polling engine. |
| Elements | Int32 | Total number of monitored elements assigned to this engine. |
| Nodes | Int32 | Count of nodes assigned to this engine. |
| Interfaces | Int32 | Count of interfaces monitored by this engine. |
| Volumes | Int32 | Count of volumes monitored by this engine. |
| Pollers | Int32 | Total number of poller instances running on this engine. |
| PollingCompletion | Double | Percentage of polls completing within the configured interval (0-100). |
| MaxPollers | Int32 | Maximum poller capacity configured for this engine. |
| DisplayName | String | Computed display name for the engine. |
| Uri | String | SWIS URI for this engine instance. |

### Navigation Properties (Orion.Engines)

| Navigation Property | Target Entity | Cardinality | Description |
|---------------------|---------------|-------------|-------------|
| Nodes | Orion.Nodes | 0..* | All nodes assigned to this polling engine. |

### Example Queries (Orion.Engines)

**Polling engine summary with element counts:**

```sql
SELECT EngineID, ServerName, IP, ServerType,
       Elements, Nodes, Interfaces, Volumes,
       PollingCompletion
FROM Orion.Engines
ORDER BY ServerType, ServerName
```

**Nodes per engine with polling completion health:**

```sql
SELECT e.ServerName, e.ServerType, e.PollingCompletion,
       COUNT(n.NodeID) AS NodeCount
FROM Orion.Engines e
LEFT JOIN Orion.Nodes n ON n.EngineID = e.EngineID
GROUP BY e.ServerName, e.ServerType, e.PollingCompletion
ORDER BY NodeCount DESC
```

**Identify overloaded engines (completion below threshold):**

```sql
SELECT ServerName, IP, ServerType,
       Elements, Pollers, MaxPollers, PollingCompletion
FROM Orion.Engines
WHERE PollingCompletion < 98
ORDER BY PollingCompletion ASC
```

---

## Orion.Volumes Entity Schema (SWQL)

The `Orion.Volumes` entity represents monitored disk volumes (drives, mount points, partitions) on Orion-managed nodes. Volumes are polled for capacity and utilization metrics and commonly used in disk space alerting and capacity planning.

### Properties (Orion.Volumes)

| Name | Type | Description |
|------|------|-------------|
| VolumeID | Int32 | **Primary key.** Unique identifier for the volume. |
| NodeID | Int32 | Foreign key to `Orion.Nodes`. The parent node hosting this volume. |
| Caption | String | Display name of the volume (e.g., `C:\` or `/dev/sda1`). |
| VolumeIndex | Int32 | Index position of the volume on the node (SNMP hrStorageIndex). |
| VolumeType | String | Type classification: `Fixed Disk`, `RAM`, `Virtual Memory`, `Network Disk`, `Compact Disc`, `Removable Disk`, `Mount Point`. |
| VolumeDescription | String | Descriptive text for the volume, often the file system label. |
| VolumeSize | Double | Total volume capacity in bytes. |
| VolumeSpaceUsed | Double | Disk space currently used in bytes. |
| VolumeSpaceAvailable | Double | Disk space currently free in bytes. |
| VolumePercentUsed | Double | Disk utilization percentage (0-100). |
| VolumePercentAvailable | Double | Disk availability percentage (0-100). |
| Status | Int32 | Volume status code (mirrors the Orion status value scheme). |
| StatusDescription | String | Human-readable status label for the volume. |
| VolumeTypeIcon | String | Icon filename reference for the volume type. |
| PollInterval | Int32 | Polling interval in seconds for this volume. |
| Uri | String | SWIS URI for this volume instance. |
| DetailsUrl | String | Relative URL to the volume details page. |
| DisplayName | String | Computed display name for the volume. |

### Navigation Properties (Orion.Volumes)

| Navigation Property | Target Entity | Cardinality | Description |
|---------------------|---------------|-------------|-------------|
| Node | Orion.Nodes | 0..1 | Parent node this volume belongs to. |
| CustomProperties | Orion.VolumesCustomProperties | 0..1 | Custom property values assigned to this volume. |

### Example Queries (Orion.Volumes)

**Low disk space report (volumes above 90% used):**

```sql
SELECT v.Node.Caption AS NodeName, v.Caption AS Volume,
       v.VolumeType, v.VolumePercentUsed,
       v.VolumeSpaceAvailable / 1073741824 AS FreeGB,
       v.VolumeSize / 1073741824 AS TotalGB
FROM Orion.Volumes v
WHERE v.VolumePercentUsed > 90
  AND v.VolumeType = 'Fixed Disk'
ORDER BY v.VolumePercentUsed DESC
```

**Volume utilization summary per node:**

```sql
SELECT v.Node.Caption AS NodeName,
       COUNT(v.VolumeID) AS VolumeCount,
       AVG(v.VolumePercentUsed) AS AvgPercentUsed,
       MAX(v.VolumePercentUsed) AS MaxPercentUsed
FROM Orion.Volumes v
WHERE v.VolumeType = 'Fixed Disk'
GROUP BY v.Node.Caption
ORDER BY MaxPercentUsed DESC
```

**All volumes on a specific node with free space in GB:**

```sql
SELECT Caption, VolumeType,
       VolumeSize / 1073741824 AS TotalGB,
       VolumeSpaceAvailable / 1073741824 AS FreeGB,
       VolumePercentUsed
FROM Orion.Volumes
WHERE NodeID = 42
ORDER BY Caption
```

---

## Orion.Events Entity Schema (SWQL)

The `Orion.Events` entity stores event log entries generated by the Orion platform. Events capture node state changes (up, down, warning), alert triggers, configuration changes, and informational messages. This entity is write-heavy and can grow large in active environments.

### Properties (Orion.Events)

| Name | Type | Description |
|------|------|-------------|
| EventID | Int64 | **Primary key.** Unique identifier for the event record. |
| EventTime | DateTime | Timestamp when the event occurred. |
| Message | String | Full event message text describing what happened. |
| EventType | Int32 | Numeric event type code (e.g., 0=Info, 1=NodeDown, 5=NodeUp, 14=NodeWarning). |
| NetworkNode | Int32 | NodeID of the node associated with this event. Foreign key to `Orion.Nodes`. |
| NetObjectID | Int32 | ID of the specific monitored object (node, interface, volume) related to the event. |
| NetObjectType | String | Type of the monitored object (`N`=Node, `I`=Interface, `V`=Volume). |
| Acknowledged | Boolean | True if the event has been acknowledged by an operator. |
| TimeStamp | DateTime | Secondary timestamp field; in most cases same as EventTime. |
| Uri | String | SWIS URI for this event instance. |
| DisplayName | String | Computed display name for the event. |

### Navigation Properties (Orion.Events)

| Navigation Property | Target Entity | Cardinality | Description |
|---------------------|---------------|-------------|-------------|
| Node | Orion.Nodes | 0..1 | The node associated with this event. |

### Example Queries (Orion.Events)

**Recent events in the last 24 hours:**

```sql
SELECT EventID, EventTime, EventType, Message,
       NetworkNode
FROM Orion.Events
WHERE EventTime >= ADDDAY(-1, GETUTCDATE())
ORDER BY EventTime DESC
```

**Node down and up events with node name:**

```sql
SELECT e.EventTime, e.EventType, e.Message,
       e.Node.Caption AS NodeName, e.Node.IPAddress
FROM Orion.Events e
WHERE e.EventType IN (1, 5)
  AND e.EventTime >= ADDDAY(-7, GETUTCDATE())
ORDER BY e.EventTime DESC
```

**Event count by type over the last 30 days:**

```sql
SELECT EventType, COUNT(EventID) AS EventCount
FROM Orion.Events
WHERE EventTime >= ADDDAY(-30, GETUTCDATE())
GROUP BY EventType
ORDER BY EventCount DESC
```

---

## Orion.AlertConfigurations Entity Schema (SWQL)

The `Orion.AlertConfigurations` entity stores the definitions of all configured alerts in Orion. Each row represents a single alert rule including its trigger conditions, severity, and enabled state. This entity defines the alert logic; active triggers are tracked in `Orion.AlertActive`.

### Properties (Orion.AlertConfigurations)

| Name | Type | Description |
|------|------|-------------|
| AlertID | Int32 | **Primary key.** Unique identifier for the alert configuration. |
| Name | String | Display name of the alert (e.g., `Node Down Alert`). |
| Description | String | Detailed description of what the alert monitors and when it triggers. |
| Enabled | Boolean | True if the alert is actively being evaluated. |
| Severity | Int32 | Severity level: 0=Informational, 1=Warning, 2=Critical, 3=Serious. |
| ObjectType | String | The SWIS entity type the alert applies to (e.g., `Orion.Nodes`, `Orion.NPM.Interfaces`). |
| Frequency | Int32 | Evaluation frequency in seconds. How often Orion checks the trigger condition. |
| CreatedBy | String | Username of the account that created the alert. |
| CreatedDateTime | DateTime | Timestamp when the alert was created. |
| LastEdit | DateTime | Timestamp of the last modification to the alert configuration. |
| Category | String | Organizational category assigned to the alert. |
| ResponsibleTeam | String | Team or group responsible for this alert. |
| Uri | String | SWIS URI for this alert configuration instance. |
| DisplayName | String | Computed display name for the alert. |

### Navigation Properties (Orion.AlertConfigurations)

| Navigation Property | Target Entity | Cardinality | Description |
|---------------------|---------------|-------------|-------------|
| AlertObjects | Orion.AlertObjects | 0..* | Objects (nodes, interfaces, etc.) this alert is bound to. |
| ActiveAlerts | Orion.AlertActive | 0..* | Currently triggered instances of this alert. |
| AlertHistory | Orion.AlertHistory | 0..* | Historical trigger/reset records for this alert. |

### Example Queries (Orion.AlertConfigurations)

**List all enabled alert configurations:**

```sql
SELECT AlertID, Name, Description, Severity,
       ObjectType, Frequency, Enabled
FROM Orion.AlertConfigurations
WHERE Enabled = TRUE
ORDER BY Severity DESC, Name
```

**Alert configuration audit -- who created or last modified:**

```sql
SELECT Name, Severity, Enabled,
       CreatedBy, CreatedDateTime, LastEdit
FROM Orion.AlertConfigurations
ORDER BY LastEdit DESC
```

**Count of alerts by object type and severity:**

```sql
SELECT ObjectType, Severity,
       COUNT(AlertID) AS AlertCount
FROM Orion.AlertConfigurations
WHERE Enabled = TRUE
GROUP BY ObjectType, Severity
ORDER BY ObjectType, Severity
```

---

## Orion.AlertActive Entity Schema (SWQL)

The `Orion.AlertActive` entity tracks all currently triggered (active) alerts in the Orion platform. Each row represents a single alert instance that has fired and has not yet been reset or cleared. This is the primary entity for building active alert dashboards and operational views.

### Properties (Orion.AlertActive)

| Name | Type | Description |
|------|------|-------------|
| AlertActiveID | Int64 | **Primary key.** Unique identifier for this active alert instance. |
| AlertObjectID | Int32 | Foreign key linking to the alert-object binding in `Orion.AlertObjects`. |
| TriggeredDateTime | DateTime | Timestamp when the alert was triggered. |
| TriggeredMessage | String | The rendered alert message at the time of triggering, with macro values resolved. |
| AcknowledgedBy | String | Username of the operator who acknowledged the alert. Null if unacknowledged. |
| AcknowledgedDateTime | DateTime | Timestamp when the alert was acknowledged. Null if unacknowledged. |
| AcknowledgedNote | String | Optional note entered by the operator during acknowledgement. |
| EntityCaption | String | Display name of the entity (node, interface, etc.) that triggered the alert. |
| EntityDetailsUrl | String | Relative URL to the details page of the triggering entity. |
| EntityUri | String | SWIS URI of the triggering entity. |
| Severity | Int32 | Severity level inherited from the alert configuration. |
| AlertConfiguration | Orion.AlertConfigurations | Reference | The alert definition that generated this active instance. |
| Uri | String | SWIS URI for this active alert instance. |
| DisplayName | String | Computed display name for the active alert. |

### Navigation Properties (Orion.AlertActive)

| Navigation Property | Target Entity | Cardinality | Description |
|---------------------|---------------|-------------|-------------|
| AlertConfiguration | Orion.AlertConfigurations | 0..1 | The parent alert definition for this triggered instance. |
| AlertObject | Orion.AlertObjects | 0..1 | The alert-object binding that generated this trigger. |

### Verbs (Orion.AlertActive)

| Verb | Parameters | Description |
|------|------------|-------------|
| Acknowledge | AlertObjectID:Int32[], Note:String | Acknowledges one or more active alerts with an optional note. |
| ClearAlert | AlertObjectID:Int32[] | Clears (resets) one or more active alerts, removing them from the active list. |

### Example Queries (Orion.AlertActive)

**All active alerts with severity and trigger time:**

```sql
SELECT AlertActiveID, EntityCaption, TriggeredDateTime,
       TriggeredMessage, Severity, AcknowledgedBy
FROM Orion.AlertActive
ORDER BY Severity DESC, TriggeredDateTime DESC
```

**Unacknowledged critical alerts:**

```sql
SELECT a.EntityCaption, a.TriggeredDateTime,
       a.TriggeredMessage, a.Severity
FROM Orion.AlertActive a
WHERE a.AcknowledgedBy IS NULL
  AND a.Severity >= 2
ORDER BY a.TriggeredDateTime ASC
```

**Active alert count by severity:**

```sql
SELECT Severity,
       COUNT(AlertActiveID) AS ActiveCount
FROM Orion.AlertActive
GROUP BY Severity
ORDER BY Severity DESC
```

---

## Orion.Container Entity Schema (SWQL - Groups)

The `Orion.Container` entity represents Groups in the Orion web console. Groups are logical collections of monitored objects used for organizing nodes, interfaces, and volumes into meaningful operational sets (e.g., by site, function, or department). Group status is computed from member status using a configurable status calculator.

### Properties (Orion.Container)

| Name | Type | Description |
|------|------|-------------|
| ContainerID | Int32 | **Primary key.** Unique identifier for the group/container. |
| Name | String | Display name of the group. |
| Description | String | Optional description of the group's purpose. |
| Owner | String | Username of the account that created or owns the group. |
| StatusCalculator | Int32 | Status rollup algorithm: 0=ShowBestStatus, 1=ShowWorstStatus, 2=MixedStatusShowsWarning. |
| PollingEnabled | Boolean | True if the group status is actively polled/computed. |
| Frequency | Int32 | Status refresh frequency in seconds. |
| Status | Int32 | Computed group status based on member statuses and the StatusCalculator algorithm. |
| StatusDescription | String | Human-readable computed status label. |
| Uri | String | SWIS URI for this container instance. |
| DisplayName | String | Computed display name for the group. |
| DetailsUrl | String | Relative URL to the group details page. |

### Related Entities

| Entity | Description |
|--------|-------------|
| Orion.ContainerMemberDefinition | Defines the membership rules (dynamic queries or static member lists) for each group. Key properties: ContainerID, Name, Entity, Definition. |
| Orion.ContainerMembers | Resolved current members of each group. Key properties: ContainerID, MemberUri, MemberEntityType, Name. |

### Verbs (Orion.Container)

| Verb | Parameters | Description |
|------|------------|-------------|
| CreateContainer | Name:String, Owner:String, Frequency:Int32, StatusCalculator:Int32 | Creates a new group with the specified configuration. |
| AddDefinitions | ContainerID:Int32, Definitions:Array | Adds member definitions (dynamic or static) to an existing group. |
| DeleteContainer | ContainerID:Int32 | Removes a group and its member definitions. |

### Example Queries (Orion.Container)

**List all groups with status and member count:**

```sql
SELECT c.ContainerID, c.Name, c.StatusDescription,
       c.Owner, c.StatusCalculator,
       COUNT(m.MemberUri) AS MemberCount
FROM Orion.Container c
LEFT JOIN Orion.ContainerMembers m
  ON m.ContainerID = c.ContainerID
GROUP BY c.ContainerID, c.Name, c.StatusDescription,
         c.Owner, c.StatusCalculator
ORDER BY c.Name
```

**Group membership definitions (what rules define each group):**

```sql
SELECT c.Name AS GroupName, d.Name AS DefinitionName,
       d.Entity, d.Definition
FROM Orion.ContainerMemberDefinition d
INNER JOIN Orion.Container c
  ON c.ContainerID = d.ContainerID
ORDER BY c.Name, d.Name
```

**Groups in warning or critical status:**

```sql
SELECT Name, StatusDescription, Owner
FROM Orion.Container
WHERE Status IN (3, 14)
ORDER BY Status DESC, Name
```

---

## Orion.CustomProperty Entity Schema (SWQL)

The `Orion.CustomProperty` entity stores the metadata definitions for all custom properties configured in the Orion platform. Custom properties are user-defined fields added to nodes, interfaces, volumes, or other entities for organizational tagging, reporting, and alert filtering. The actual property values are stored in entity-specific tables such as `Orion.NodesCustomProperties`.

### Properties (Orion.CustomProperty)

| Name | Type | Description |
|------|------|-------------|
| Field | String | Name of the custom property field (e.g., `City`, `Environment`, `SupportTier`). |
| DataType | String | Data type of the field: `String`, `Integer`, `DateTime`, `Boolean`, etc. |
| Description | String | Administrator-provided description of the custom property's purpose. |
| TargetEntity | String | The entity type this property applies to (e.g., `Orion.NodesCustomProperties`). |
| MaxLength | Int32 | Maximum character length for String-type custom properties. |
| IsRequired | Boolean | True if the property must be populated for each entity instance. |
| DefaultValue | String | Default value assigned to new entity instances if not explicitly set. |
| Uri | String | SWIS URI for this custom property definition. |
| DisplayName | String | Computed display name for the custom property. |

### Related Entities

| Entity | Description |
|--------|-------------|
| Orion.NodesCustomProperties | Stores custom property values for nodes. Accessed via `Orion.Nodes.CustomProperties` navigation. |
| Orion.CustomPropertyUsage | Tracks where each custom property is referenced in alerts, reports, and views. |
| Orion.NPM.InterfacesCustomProperties | Stores custom property values for interfaces. |
| Orion.VolumesCustomProperties | Stores custom property values for volumes. |

### Example Queries (Orion.CustomProperty)

**List all defined custom properties with metadata:**

```sql
SELECT Field, DataType, Description,
       TargetEntity, MaxLength, IsRequired
FROM Orion.CustomProperty
ORDER BY TargetEntity, Field
```

**Node custom properties -- all values for a specific field:**

```sql
SELECT n.Caption, n.IPAddress,
       n.CustomProperties.City AS City,
       n.CustomProperties.Environment AS Environment
FROM Orion.Nodes n
WHERE n.CustomProperties.City IS NOT NULL
ORDER BY n.CustomProperties.City
```

**Custom properties that apply to nodes only:**

```sql
SELECT Field, DataType, MaxLength, Description
FROM Orion.CustomProperty
WHERE TargetEntity = 'Orion.NodesCustomProperties'
ORDER BY Field
```

---

## Orion.Views Entity Schema (SWQL - Dashboards)

The `Orion.Views` entity stores the definitions of dashboards and views within the Orion web console. Each view is a page layout containing widgets (resources) that display monitoring data. Views are organized into view groups and can be scoped to specific object types.

### Properties (Orion.Views)

| Name | Type | Description |
|------|------|-------------|
| ViewID | Int32 | **Primary key.** Unique identifier for the view/dashboard. |
| ViewTitle | String | Display title of the view shown in the navigation menu. |
| ViewType | String | Type classification: `Summary`, `Detail`, `Custom`, `NOC`. |
| ViewGroupName | String | Organizational group the view belongs to (e.g., `Network`, `Servers`, `Custom`). |
| ViewGroup | Int32 | Numeric group identifier. |
| ViewIcon | String | Icon filename or reference for the view in navigation. |
| Columns | Int32 | Number of columns in the view layout. |
| Column1Width | String | Width specification for the first column. |
| Column2Width | String | Width specification for the second column. |
| System | Boolean | True if the view is a built-in system view (not user-created). |
| Customizable | Boolean | True if the view layout can be modified by users. |
| NOCView | Boolean | True if the view is designed for NOC/wallboard display. |
| Uri | String | SWIS URI for this view instance. |
| DisplayName | String | Computed display name for the view. |

### Example Queries (Orion.Views)

**List all views grouped by type:**

```sql
SELECT ViewID, ViewTitle, ViewType, ViewGroupName
FROM Orion.Views
ORDER BY ViewType, ViewGroupName, ViewTitle
```

**Custom (user-created) views only:**

```sql
SELECT ViewID, ViewTitle, ViewGroupName
FROM Orion.Views
WHERE System = FALSE
ORDER BY ViewGroupName, ViewTitle
```

---

## Orion.Reports Entity Schema (SWQL)

The `Orion.Reports` entity stores definitions for all reports configured in the Orion platform. Reports generate on-demand or scheduled output for capacity planning, compliance, and operational review.

### Properties (Orion.Reports)

| Name | Type | Description |
|------|------|-------------|
| ReportID | Int32 | **Primary key.** Unique identifier for the report. |
| Name | String | Display name of the report. |
| Description | String | Description of the report contents and purpose. |
| Owner | String | Username of the account that created or owns the report. |
| Category | String | Organizational category for the report (e.g., `Network`, `Capacity`, `Availability`). |
| ReportType | String | Report format or rendering type. |
| ModuleTitle | String | Module that provides this report (e.g., `NPM`, `SAM`, `Orion Core`). |
| Uri | String | SWIS URI for this report instance. |
| DisplayName | String | Computed display name for the report. |

### Example Queries (Orion.Reports)

**List all reports by category:**

```sql
SELECT ReportID, Name, Description, Owner, Category
FROM Orion.Reports
ORDER BY Category, Name
```

**Reports owned by a specific user:**

```sql
SELECT ReportID, Name, Description, Category
FROM Orion.Reports
WHERE Owner = 'admin'
ORDER BY Name
```

---

## Orion.Pollers Entity Schema (SWQL)

The `Orion.Pollers` entity stores poller assignments that define what data is collected from each monitored object. Each poller instance maps a specific poller type (e.g., SNMP status, ICMP response time, CPU/memory) to a network object. Pollers are the mechanism through which Orion collects monitoring data.

### Properties (Orion.Pollers)

| Name | Type | Description |
|------|------|-------------|
| PollerID | Int32 | **Primary key.** Unique identifier for the poller assignment. |
| PollerType | String | The type of data collected (e.g., `N.Status.ICMP.Native`, `N.ResponseTime.ICMP.Native`, `N.Details.SNMP.Generic`, `N.Cpu.SNMP.HrProcessorLoad`). |
| NetObject | String | Composite identifier for the monitored object (e.g., `N:42` for NodeID 42, `I:105` for InterfaceID 105). |
| NetObjectType | String | Type prefix: `N` (Node), `I` (Interface), `V` (Volume). |
| NetObjectID | Int32 | Numeric ID of the monitored object within its type. |
| Enabled | Boolean | True if this poller assignment is actively collecting data. |
| Uri | String | SWIS URI for this poller instance. |
| DisplayName | String | Computed display name for the poller. |

### Navigation Properties (Orion.Pollers)

| Navigation Property | Target Entity | Cardinality | Description |
|---------------------|---------------|-------------|-------------|
| Node | Orion.Nodes | 0..1 | The node associated with this poller (for node-level pollers). |

### Example Queries (Orion.Pollers)

**List all poller types assigned to a specific node:**

```sql
SELECT PollerID, PollerType, NetObject, Enabled
FROM Orion.Pollers
WHERE NetObject = 'N:42'
ORDER BY PollerType
```

**Count of poller assignments by type across all nodes:**

```sql
SELECT PollerType, COUNT(PollerID) AS AssignmentCount
FROM Orion.Pollers
WHERE NetObjectType = 'N'
GROUP BY PollerType
ORDER BY AssignmentCount DESC
```

**Disabled pollers (potential monitoring gaps):**

```sql
SELECT p.NetObject, p.PollerType, p.NetObjectType
FROM Orion.Pollers p
WHERE p.Enabled = FALSE
ORDER BY p.NetObjectType, p.NetObject
```

---

## Orion.Accounts Entity Schema (SWQL)

The `Orion.Accounts` entity stores user account definitions for the Orion web console. Accounts control authentication, authorization, and access to views, nodes, and features. This entity covers both local Orion accounts and externally authenticated accounts (Active Directory, LDAP).

### Properties (Orion.Accounts)

| Name | Type | Description |
|------|------|-------------|
| AccountID | Int32 | **Primary key.** Unique numeric identifier for the account. |
| AccountSID | String | Security identifier string for the account. For AD accounts, this is the Windows SID. |
| Enabled | Boolean | True if the account is active and can log in. |
| AccountType | Int32 | Account type code: 0=Admin, 1=User, 2=Guest. Determines default permission level. |
| AllowAdmin | Boolean | True if the account has full administrative privileges. |
| CanClearEvents | Boolean | True if the account can clear events from the event log. |
| Expires | DateTime | Account expiration date. Null for non-expiring accounts. |
| LastLogin | DateTime | Timestamp of the last successful login. |
| GroupInfo | String | Group or role membership information for the account. |
| Uri | String | SWIS URI for this account instance. |
| DisplayName | String | Computed display name for the account. |

### Example Queries (Orion.Accounts)

**List all enabled accounts with type and last login:**

```sql
SELECT AccountID, AccountSID, AccountType,
       AllowAdmin, Enabled, LastLogin
FROM Orion.Accounts
WHERE Enabled = TRUE
ORDER BY AccountSID
```

**Admin accounts audit:**

```sql
SELECT AccountSID, AccountType, LastLogin, Expires
FROM Orion.Accounts
WHERE AllowAdmin = TRUE
ORDER BY LastLogin DESC
```

**Accounts that have never logged in or are expired:**

```sql
SELECT AccountSID, AccountType, Enabled, Expires
FROM Orion.Accounts
WHERE LastLogin IS NULL
   OR Expires < GETUTCDATE()
ORDER BY AccountSID
```

---

## Orion.InstalledModule Entity Schema (SWQL)

The `Orion.InstalledModule` entity lists all SolarWinds modules installed and licensed on the Orion platform server. This entity is useful for inventory auditing, verifying module availability before writing SWQL queries against module-specific entities, and tracking software versions across upgrades.

### Properties (Orion.InstalledModule)

| Name | Type | Description |
|------|------|-------------|
| Name | String | Short module name or identifier (e.g., `NPM`, `SAM`, `NCM`, `NTA`). |
| Description | String | Full descriptive name of the module (e.g., `Network Performance Monitor`). |
| Version | String | Installed version string (e.g., `2024.2.0`). |
| DisplayName | String | Computed display name for the module. |
| Uri | String | SWIS URI for this module instance. |

### Example Queries (Orion.InstalledModule)

**List all installed modules and versions:**

```sql
SELECT Name, Description, Version
FROM Orion.InstalledModule
ORDER BY Name
```

**Check if a specific module is installed (useful before querying module entities):**

```sql
SELECT Name, Version
FROM Orion.InstalledModule
WHERE Name LIKE '%NPM%' OR Name LIKE '%SAM%'
ORDER BY Name
```
