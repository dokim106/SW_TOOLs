# SWQL Entity Namespace Map

## SWQL Orion Core Namespace (Orion.*)

The primary SWIS namespace for the SolarWinds Orion platform. Contains all core monitoring entities used in SWQL queries across node management, alerting, events, credentials, and platform configuration.

### Core Node and Infrastructure Entities (SWQL)

| Entity | Description | Key Properties |
|--------|-------------|----------------|
| Orion.Nodes | Monitored network devices and servers | NodeID, Caption, IPAddress, Status, Vendor, MachineType, ObjectSubType, EngineID, SysName |
| Orion.Engines | Polling engines | EngineID, ServerName, IP, ServerType |
| Orion.Volumes | Disk volumes on monitored nodes | VolumeID, NodeID, Caption, VolumeType, VolumeSize, VolumeSpaceAvailable, VolumePercentUsed |
| Orion.Pollers | Poller assignments | PollerID, PollerType, NetObject, NetObjectType |
| Orion.ResponseTime | Response time statistics | NodeID, DateTime, AvgResponseTime, MinResponseTime, MaxResponseTime, PercentLoss |
| Orion.CPULoad | CPU utilization history | NodeID, DateTime, AvgLoad, MinLoad, MaxLoad |
| Orion.Credentials | Credential sets | ID, Name, CredentialType, Description |

### Alerting Entities (SWQL)

| Entity | Description | Key Properties |
|--------|-------------|----------------|
| Orion.AlertConfigurations | Alert definitions | AlertID, Name, Description, Enabled, Severity, ObjectType |
| Orion.AlertActive | Currently triggered alerts | AlertActiveID, AlertObjectID, TriggeredDateTime, TriggeredMessage, AcknowledgedBy |
| Orion.AlertHistory | Historical alert records | AlertHistoryID, AlertActiveID, EventType, TimeStamp, Message |
| Orion.Actions | Alert action definitions | ActionID, ActionTypeID, Enabled |

### Events, Groups, and Configuration Entities (SWQL)

| Entity | Description | Key Properties |
|--------|-------------|----------------|
| Orion.Events | Event log entries | EventID, EventTime, Message, EventType, NetworkNode, NetObjectID |
| Orion.Container | Groups/containers | ContainerID, Name, Description, Owner, StatusCalculator |
| Orion.ContainerMemberDefinition | Group membership rules | ContainerID, Name, Definition |
| Orion.CustomProperty | Custom property definitions | Field, DataType, Description, TargetEntity, MaxLength |
| Orion.Settings | Platform settings | SettingID, Name, Value |

### Platform Administration Entities (SWQL)

| Entity | Description | Key Properties |
|--------|-------------|----------------|
| Orion.Accounts | User accounts | AccountID, AccountSID, Enabled, AccountType |
| Orion.InstalledModule | Licensed/installed modules | Name, Description, Version |
| Orion.Views | Dashboard/view definitions | ViewID, ViewTitle, ViewType, ViewGroupName |
| Orion.Reports | Report definitions | ReportID, Name, Description, Owner |

### Common SWQL Navigation Properties on Orion.Nodes

These navigation properties allow SWQL JOINs to be expressed as property traversals:

- **Interfaces** navigates to Orion.NPM.Interfaces (collection)
- **Volumes** navigates to Orion.Volumes (collection)
- **CustomProperties** navigates to Orion.NodesCustomProperties (single)
- **Applications** navigates to Orion.APM.Application (collection)
- **Pollers** navigates to Orion.Pollers (collection)

---

## SWQL NPM Namespace (Orion.NPM.*)

Network Performance Monitor entities for SWQL interface monitoring. This SWIS namespace covers interface status, traffic utilization, and error tracking.

### Interface Entities (SWQL)

| Entity | Description | Key Properties |
|--------|-------------|----------------|
| Orion.NPM.Interfaces | Monitored network interfaces | InterfaceID, NodeID, Caption, Status, InBandwidth, OutBandwidth, InPercentUtil, OutPercentUtil, OperStatus, AdminStatus, InterfaceType, Speed |
| Orion.NPM.InterfaceTraffic | Interface traffic statistics | InterfaceID, DateTime, InAverageBps, OutAverageBps, InTotalBytes, OutTotalBytes |
| Orion.NPM.InterfaceErrors | Interface error statistics | InterfaceID, DateTime, InErrors, OutErrors, InDiscards, OutDiscards |

### SWQL Navigation Properties on Interfaces

- **Node** navigates to Orion.Nodes (reference) -- use to reach node-level properties from an interface
- **CustomProperties** navigates to Orion.NPM.InterfacesCustomProperties (single)

---

## SWQL SAM/APM Namespace (Orion.APM.*)

Server & Application Monitor entities for SWQL application monitoring. The SWIS APM namespace covers application definitions, component-level monitors, templates, and current statistics.

### Application Monitoring Entities (SWQL)

| Entity | Description | Key Properties |
|--------|-------------|----------------|
| Orion.APM.Application | Monitored applications | ApplicationID, NodeID, Name, Status, ApplicationTemplateID |
| Orion.APM.Component | Application components/monitors | ComponentID, ApplicationID, Name, ComponentType, Status |
| Orion.APM.ApplicationTemplate | Application templates | ApplicationTemplateID, Name, Description |
| Orion.APM.CurrentStatistics | Current application stats | ApplicationID, ComponentID, StatisticData |

### SWQL Navigation Properties (APM)

- **Application.Node** navigates to Orion.Nodes
- **Application.Template** navigates to Orion.APM.ApplicationTemplate
- **Application.Components** navigates to Orion.APM.Component (collection)

---

## SWQL NCM Namespace (Cirrus.* and NCM.*)

Network Configuration Manager entities in SWIS. The NCM namespace is split between the legacy `Cirrus.*` prefix (config archives, snippets, policies) and the `NCM.*` prefix (EOL/EOS tracking, firmware, jobs).

### Configuration Management Entities (SWQL)

| Entity | Description | Key Properties |
|--------|-------------|----------------|
| Cirrus.Nodes | NCM-managed nodes | NodeID, NodeCaption, AgentIP, ConnectionProfile |
| Cirrus.ConfigArchive | Configuration backups | ConfigArchiveID, NodeID, ConfigType, DownloadTime, ConfigData |
| Cirrus.ConfigSnippets | Configuration snippets | SnippetID, Name, Content, Category |
| Cirrus.Policies | Compliance policies | PolicyID, Name, Description, Enabled |

### Lifecycle and Job Entities (SWQL)

| Entity | Description | Key Properties |
|--------|-------------|----------------|
| NCM.NodeProperties | Extended NCM node properties | NodeID, IsEOL, EOLDate, IsEOS, EOSDate |
| NCM.Eos | End-of-Support definitions | ID, HardwareModel, EndOfSupportDate |
| NCM.FirmwareDefinitions | Firmware tracking | ID, FirmwareVersion, HardwareModel |
| NCM.Jobs | NCM job definitions | JobID, NCMJobName, NCMJobType, Enabled, Status |

---

## SWQL IPAM Namespace (IPAM.*)

IP Address Manager entities in SWIS. This SWQL namespace covers subnet management, IP address tracking, DHCP scopes, DNS zones, and hierarchical IP grouping.

### IPAM Entities (SWQL)

| Entity | Description | Key Properties |
|--------|-------------|----------------|
| IPAM.Subnet | Managed subnets | SubnetId, Address, CIDR, FriendlyName, PercentUsed, GroupID |
| IPAM.IPNode | Individual IP addresses | IPNodeId, SubnetId, IPAddress, Status, DnsBackward, MACAddress |
| IPAM.DhcpServer | DHCP servers | DhcpServerId, NodeId, DisplayName |
| IPAM.DhcpScope | DHCP scopes | DhcpScopeId, NodeId, DisplayName, SubnetAddress |
| IPAM.DnsServer | DNS servers | DnsServerId, NodeId, DisplayName |
| IPAM.DnsZone | DNS zones | DnsZoneId, DnsServerId, Name, ZoneType |
| IPAM.GroupNode | IP group hierarchy | GroupId, Name, ParentId |

---

## SWQL NTA Namespace (Orion.Netflow.*)

NetFlow Traffic Analyzer entities in SWIS. This SWQL namespace covers flow data collection, application classification, and QoS policy monitoring.

### NetFlow Entities (SWQL)

| Entity | Description | Key Properties |
|--------|-------------|----------------|
| Orion.Netflow.NodeSources | NetFlow source nodes | NodeID, Enabled |
| Orion.Netflow.Flows | Flow records | FlowID, TimeStamp, SourceIP, DestIP, Protocol, Bytes |
| Orion.Netflow.Applications | NetFlow application definitions | ApplicationID, Name, Port |
| Orion.Netflow.NBAR2Applications | NBAR2 application classification | ApplicationID, Name |
| Orion.Netflow.CBQoS | Class-based QoS policies | PolicyName, ClassName, Direction |

---

## SWQL UDT Namespace (Orion.UDT.*)

User Device Tracker entities in SWIS. This SWQL namespace covers switch port monitoring, IP-to-MAC resolution, and user-device association tracking.

### UDT Entities (SWQL)

| Entity | Description | Key Properties |
|--------|-------------|----------------|
| Orion.UDT.Port | Tracked switch ports | PortID, NodeID, PortName, IsMonitored |
| Orion.UDT.IPAddress | Tracked IP addresses | IPAddressID, IPAddress, MACAddress |
| Orion.UDT.MACAddress | Tracked MAC addresses | MACAddressID, MACAddress, Vendor |
| Orion.UDT.UserName | Tracked user-device associations | UserNameID, UserName, DomainName |

---

## SWQL VMAN Namespace (Orion.VIM.*)

Virtualization Manager entities in SWIS. This SWQL namespace covers virtual machines, hypervisor hosts, datastores, clusters, and virtual disk files.

### Virtualization Entities (SWQL)

| Entity | Description | Key Properties |
|--------|-------------|----------------|
| Orion.VIM.VirtualMachines | Virtual machines | VirtualMachineID, NodeID, Name, CPUCount, MemoryMB, Status, PowerState |
| Orion.VIM.Hosts | Hypervisor hosts | HostID, NodeID, Name, CPUCount, MemoryGB, VMCount |
| Orion.VIM.Datastores | Storage datastores | DatastoreID, Name, Capacity, FreeSpace, Type |
| Orion.VIM.Clusters | VM clusters | ClusterID, Name, TotalCPU, TotalMemory |
| Orion.VIM.DiskFiles | VM disk files (VMDKs) | DiskFileID, FileName, FileSize, DatastoreID |

---

## SWQL VNQM Namespace (Orion.VoIP.*)

VoIP & Network Quality Manager entities in SWIS. This SWQL namespace covers IP SLA operations, call manager monitoring, and VoIP phone tracking.

### VNQM Entities (SWQL)

| Entity | Description | Key Properties |
|--------|-------------|----------------|
| Orion.VoIP.Operations | IP SLA/VoIP operations | OperationID, OperationType, SourceNodeID, TargetNodeID |
| Orion.VoIP.CallManagers | Call managers | CallManagerID, NodeID, Name, Status |
| Orion.VoIP.Phones | VoIP phones | PhoneID, PhoneNumber, Model |

---

## SWQL WPM Namespace (Orion.SEUM.*)

Web Performance Monitor entities in SWIS. This SWQL namespace covers synthetic web transaction monitoring, player agents, and geographic locations.

### WPM Entities (SWQL)

| Entity | Description | Key Properties |
|--------|-------------|----------------|
| Orion.SEUM.Transactions | Web transactions | TransactionID, Name, Status, AvgResponseTime |
| Orion.SEUM.Players | Transaction players/agents | PlayerID, Name, Hostname, Status |
| Orion.SEUM.Locations | Player locations | LocationID, Name, Description |

---

## SWQL Log Analyzer Namespace (Orion.OLM.*)

Log Analyzer entities in SWIS. This SWQL namespace covers log source configuration, processing rules, and log event records.

### Log Analyzer Entities (SWQL)

| Entity | Description | Key Properties |
|--------|-------------|----------------|
| Orion.OLM.LogSources | Log sources | LogSourceID, Name, NodeID, LogSourceType |
| Orion.OLM.Rules | Log processing rules | RuleID, Name, Enabled, Priority |
| Orion.OLM.LogEvents | Log event records | EventID, DateTime, Message, Severity |

---

## SWQL SCM Namespace (Orion.SCM.*)

Server Configuration Monitor entities in SWIS. This SWQL namespace covers configuration baselines, server profiles, and file integrity monitoring policies.

### SCM Entities (SWQL)

| Entity | Description | Key Properties |
|--------|-------------|----------------|
| Orion.SCM.Baselines | Configuration baselines | BaselineID, Name, Description |
| Orion.SCM.Profiles | SCM profiles | ProfileID, Name, TargetType |
| Orion.SCM.FIMPolicies | File integrity monitoring | PolicyID, Name, Path, NodeID |

---

## SWQL SRM Namespace (Orion.SRM.*)

Storage Resource Monitor entities in SWIS. This SWQL namespace covers storage array discovery, provider configuration, and storage volume monitoring.

### SRM Entities (SWQL)

| Entity | Description | Key Properties |
|--------|-------------|----------------|
| Orion.SRM.StorageArrays | Storage arrays | ArrayID, Name, Vendor, Model |
| Orion.SRM.Providers | Storage providers | ProviderID, Name, Type |
| Orion.SRM.Volumes | Storage volumes | VolumeID, Name, Capacity, UsedSpace |

---

## SWQL System Namespace (System.*)

Core SWIS system entities inherited by all other SWQL entity types. These base types define the root of the entity hierarchy and provide universal properties such as display name, URI, status, and management state.

### System Base Entities (SWQL)

| Entity | Description | Key Properties |
|--------|-------------|----------------|
| System.Entity | Root of all entity inheritance | DisplayName, Uri, InstanceType |
| System.ManagedEntity | Extends Entity with monitoring state | Status, StatusDescription, UnManaged, UnManageFrom, UnManageUntil |

All Orion entities ultimately inherit from System.Entity. Entities that represent monitored objects (nodes, interfaces, applications) inherit from System.ManagedEntity and therefore expose Status and UnManaged properties automatically.

---

## SWQL Entity Discovery Queries via SWIS

These SWQL queries allow programmatic exploration of the SWIS schema. Use them to discover available entities, properties, navigation relationships, and verbs at runtime.

### List All SWQL Entity Types in a Namespace

```sql
SELECT EntityName, FullName
FROM Metadata.Entity
WHERE FullName LIKE 'Orion.%'
ORDER BY EntityName
```

### List All SWQL Properties of an Entity

```sql
SELECT Name, Type, IsNavigable, IsKey
FROM Metadata.Property
WHERE EntityName = 'Orion.Nodes'
```

### List SWQL Navigation Properties Only

```sql
SELECT Name, Type
FROM Metadata.Property
WHERE EntityName = 'Orion.Nodes' AND IsNavigable = 'true'
```

### List Available SWIS Verbs for an Entity

```sql
SELECT EntityName, Name
FROM Metadata.Verb
WHERE EntityName = 'Orion.Nodes'
```

### List All SWQL Namespaces

```sql
SELECT DISTINCT Namespace
FROM Metadata.Entity
ORDER BY Namespace
```

### Search SWQL Entities by Keyword

```sql
SELECT FullName, EntityName
FROM Metadata.Entity
WHERE FullName LIKE '%Interface%'
ORDER BY FullName
```

These Metadata queries are the definitive way to discover what is available in any given SolarWinds installation, since installed modules determine which SWIS entities are present.
