# SWQL WPM (Web Performance Monitor) Query Cookbook

> Consolidated SWQL queries for SolarWinds Web Performance Monitor (WPM).
> Covers player/agent locations, service accounts, transaction definitions, and WPM settings.

---

## Locations (Player Agents)

### Query: WPM Player Agent Inventory

/* List all WPM player agents with their status, version, load percentage, and transaction counts. | Entities: `Orion.SEUM.Agents` */

```sql
SELECT
    Name,
    Hostname,
    IP,
    StatusDescription AS [Status],
    AgentVersion,
    CONCAT(LoadPercentage, ' %') AS [Load],
    Unmanaged,
    NumAllTransactions AS [Total Trans],
    NumManagedTransactions AS [Man Trans]
FROM
    Orion.SEUM.Agents;
```

**Key points**:
- WPM players (agents) are machines that execute synthetic web transactions from various locations.
- `LoadPercentage` indicates how heavily utilized the player is; high values suggest the need for additional players.
- `NumAllTransactions` vs `NumManagedTransactions` shows total assigned transactions versus actively managed ones.
- `Unmanaged` flag indicates whether the agent has been placed in an unmanaged state.
- `StatusDescription` provides human-readable agent health status.

---

## Player Service Account

### Query: Player Service Account Configuration

/* Placeholder for retrieving WPM player service account configuration. | Entities: *To be determined* */

```sql
-- TODO: Query requires further investigation to determine
-- applicable entities and fields for WPM player service account details.
```

**Key points**:
- This query needs further investigation to identify the correct SWQL entity for player service account information.
- Potential areas to explore: `Orion.SEUM.Agents` properties, `Orion.SEUM.Settings`, or credential-related entities.

---

## Transactions

### Query: WPM Transaction Definitions

/* List all WPM transactions with their frequency, last execution time, management state, enabled status, and health. | Entities: `Orion.SEUM.Transactions` */

```sql
SELECT
    Name,
    Frequency,
    LastPlayedUtc,
    UnManaged,
    IsEnabled,
    StatusDescription
FROM
    Orion.SEUM.Transactions;
```

**Key points**:
- Transactions are the core of WPM -- each represents a recorded web workflow that is replayed on a schedule.
- `Frequency` defines how often (in seconds or minutes) the transaction is executed.
- `LastPlayedUtc` shows the most recent execution timestamp in UTC.
- `IsEnabled` and `UnManaged` together determine if the transaction is actively running.
- `StatusDescription` provides the current health/status of the transaction (e.g., Up, Down, Warning).

---

## WPM Settings

### Query: WPM Global Settings

/* Retrieve all WPM global configuration settings as name-value pairs. | Entities: `Orion.SEUM.Settings` */

```sql
SELECT
    Name,
    Value
FROM
    Orion.SEUM.Settings;
```

**Key points**:
- Returns the global WPM configuration stored as key-value pairs.
- Settings may include default timeout values, retry policies, screenshot capture options, and other global parameters.
- Useful for auditing and documenting WPM configuration during health checks.

---



