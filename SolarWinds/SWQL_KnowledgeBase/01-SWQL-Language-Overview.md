# SWQL Language Overview

## What is SWIS (SolarWinds Information Service)

SWIS (SolarWinds Information Service) is the data access layer for all SolarWinds Orion platform products. It provides a hybrid of object-oriented and relational features, abstracting the underlying SQL Server database so that clients never need direct database access.

Key characteristics:

- Uses its own query language called **SWQL** (SolarWinds Query Language)
- Authenticates with Orion web console credentials, not database credentials
- Respects user account limitations, node management rights, and interface-level permissions
- Entity model is rooted in `System.Entity` with full inheritance support
- All entities inherit a `DisplayName` property from the base entity type
- Clients interact through a service layer rather than raw SQL, enabling API stability across product versions

SWIS treats the Orion database as a set of typed entities with properties, navigation relationships, and callable verbs, rather than as raw tables and columns.

## SWIS Connection Methods

SWIS supports multiple transport protocols for connecting to the SolarWinds Information Service:

| Method | Port | Protocol | Notes |
|---|---|---|---|
| net.tcp | 17777 | WCF binary | Legacy, Windows-only, requires .NET WCF client |
| HTTPS | 17778 | REST/JSON | Cross-platform, recommended for new integrations |

**REST endpoint URL:**

```
https://{hostname}:17778/SolarWinds/InformationService/v3/Json/
```

**Authentication options:**

- **Username/Password** - Orion account credentials passed via HTTP Basic auth
- **Windows Integrated (Trusted)** - Uses current Windows identity (NTLM/Kerberos)
- **Certificate** - Client certificate authentication (local connections only)

**PowerShell access:**

The `SwisPowerShell` module provides the `Connect-Swis` cmdlet for establishing connections:

```powershell
# Username/Password
$swis = Connect-Swis -Hostname solarwinds.example.com -Username admin -Password (Read-Host -AsSecureString)

# Windows Integrated
$swis = Connect-Swis -Hostname solarwinds.example.com -Trusted

# Certificate (local only)
$swis = Connect-Swis -Hostname localhost -Certificate
```

## SWIS Data Interfaces

SWIS exposes three distinct interfaces for interacting with data. Each serves a different purpose:

### 1. Query Interface (Read-Only)

Execute SWQL queries to retrieve data. This is the most commonly used interface.

- **PowerShell:** `Get-SwisData`
- **REST:** `POST /Query` with `{ "query": "SELECT ... FROM ..." }`
- Returns tabular result sets, similar to SQL query results

### 2. CRUD Interface (Create, Read, Update, Delete)

Manage individual entity instances using their SWIS URIs.

| Operation | PowerShell Cmdlet | REST Method |
|---|---|---|
| Create | `New-SwisObject` | `POST /Create/{EntityType}` |
| Read | `Get-SwisObject` | `GET /{URI}` |
| Update | `Set-SwisObject` | `POST /Update/{URI}` |
| Delete | `Remove-SwisObject` | `POST /Delete/{URI}` |

### 3. Invoke Interface (Execute Verbs)

Call methods (verbs) defined on entity types to perform actions.

- **PowerShell:** `Invoke-SwisVerb`
- **REST:** `POST /Invoke/{EntityType}/{Verb}`

Common verb examples:

| Verb | Purpose |
|---|---|
| `Orion.AlertActive.Acknowledge` | Acknowledge an active alert |
| `Orion.Nodes.Unmanage` | Set a node to unmanaged state |
| `Orion.Nodes.Remanage` | Return a node to managed state |
| `Orion.Nodes.PollNow` | Trigger an immediate poll |

## SWQL vs SQL Key Differences

SWQL is syntactically similar to T-SQL but has fundamental differences that developers must understand:

### Access Model

| Feature | SWQL | T-SQL |
|---|---|---|
| Read data | SELECT queries | SELECT queries |
| Modify data | Not supported (use CRUD interface) | INSERT, UPDATE, DELETE |
| DDL operations | Not supported | CREATE, ALTER, DROP |
| Stored procedures | Not supported | Fully supported |
| CTEs / Temp tables | Not supported | Fully supported |
| Window functions | Not supported | ROW_NUMBER, RANK, etc. |
| Variables | Parameters only (@param) | DECLARE @var |

### Syntax Differences

- **Entity names** use `Namespace.Entity` format: `Orion.Nodes`, not `dbo.Nodes`
- **Navigation properties** allow dot-notation traversal: `node.Interfaces.InterfaceName`
- **Wildcard** in LIKE is `%`, not `*`
- **Date functions** use pascal-case canonical forms: `GetDate()`, `GetUtcDate()` (though `GETDATE()` and `GETUTCDATE()` also work)
- **Boolean comparisons** may require string values: `WHERE Unmanaged = 'True'`

### Inheritance Behavior

SWQL supports entity inheritance. Querying a parent entity type automatically returns rows from all descendant types. For example, querying `System.Entity` returns every entity in SWIS.

### Entity Identification

Entities are identified by SWIS URIs rather than simple primary keys:

```
swis://hostname/Orion/Orion.Nodes/NodeID=1
```

## SWQL Studio

SWQL Studio is a free, interactive query and schema exploration tool for SolarWinds Information Service. It is the primary development and debugging tool for SWQL.

**Capabilities:**

- Connect to any SolarWinds Orion server using any supported authentication method
- Browse the full entity schema: entities, properties, verbs, and navigation properties
- Execute SWQL queries and view tabular results
- Maintain query history across sessions
- Support multiple simultaneous connections to different servers
- Export query results for further analysis

**Installation:**

SWQL Studio is bundled with the OrionSDK. Download from:

```
https://github.com/solarwinds/OrionSDK
```

The tool is located in the `Swql.Studio` folder after extracting or building the SDK. It runs as a standalone Windows application with no installation required on the Orion server itself.

## SolarWinds Module Name Mappings

SolarWinds product marketing names differ from the internal module names stored in SWIS. This mapping is essential when querying `Orion.InstalledModule` or filtering by module.

| Marketing Name | Internal Name | Primary Namespace |
|---|---|---|
| NPM (Network Performance Monitor) | NPM | `Orion.Nodes`, `Orion.NPM.*` |
| SAM (Server & Application Monitor) | APM | `Orion.APM.*` |
| NCM (Network Configuration Manager) | NCM | `Cirrus.*`, `NCM.*` |
| IPAM (IP Address Manager) | IPAM | `IPAM.*` |
| UDT (User Device Tracker) | UDT | `Orion.UDT.*` |
| VNQM (VoIP & Network Quality Manager) | VoIP | `Orion.VoIP.*` |
| WPM (Web Performance Monitor) | SEUM | `Orion.SEUM.*` |
| NTA (NetFlow Traffic Analyzer) | NTA | `Orion.Netflow.*` |
| VMAN (Virtualization Manager) | VIM | `Orion.VIM.*` |
| LA (Log Analyzer) | OLM | `Orion.OLM.*` |
| SCM (Server Configuration Monitor) | SCM | `Orion.SCM.*` |
| SRM (Storage Resource Monitor) | SRM | `Orion.SRM.*` |

**Note:** SAM's internal name is `APM` (not `SAM`), and WPM's internal name is `SEUM`. These are the most commonly confused mappings.

**Query to check installed modules:**

```sql
SELECT Name, Description, Version
FROM Orion.InstalledModule
```

This returns all licensed and installed modules on the Orion server, using their internal names (e.g., `APM` for SAM).

## SWIS URI Structure

SWIS URIs uniquely identify entity instances within the SolarWinds Information Service. They are used by the CRUD and Invoke interfaces to target specific objects.

**Format:**

```
swis://{hostname}/Orion/{EntityType}/{KeyProperty}={Value}
```

**Examples:**

| URI | Description |
|---|---|
| `swis://localhost/Orion/Orion.Nodes/NodeID=42` | Node with NodeID 42 |
| `swis://localhost/Orion/Orion.Nodes/NodeID=42/CustomProperties` | Custom properties for node 42 |
| `swis://localhost/Orion/Orion.NPM.Interfaces/InterfaceID=7` | Interface with InterfaceID 7 |

**Key facts:**

- The `Uri` property is available on all queryable entities and can be retrieved via SWQL:
  ```sql
  SELECT Uri, Caption FROM Orion.Nodes WHERE NodeID = 42
  ```
- URIs are used by `Get-SwisObject`, `Set-SwisObject`, and `Remove-SwisObject` to target entities
- Child/related entities are accessed by appending the navigation property name to the parent URI
- The hostname in the URI corresponds to the Orion server the entity resides on
