# SWQL SCM (Server Configuration Monitor) Query Cookbook

> Consolidated SWQL queries for SolarWinds Server Configuration Monitor (SCM).
> Covers baselines, profile types, data retention, FIM exclusions, monitored nodes, polling settings, and change-tracking configuration.

---

## Baselines

### Query: Count SCM Baselines

/* Count the total number of distinct baselines configured in SCM. | Entities: `Orion.SCM.Baseline` */

```sql
SELECT
    COUNT(DISTINCT BaselineID) AS [Number of Baselines]
FROM
    Orion.SCM.Baseline;
```

**Key points**:
- Uses `COUNT(DISTINCT BaselineID)` to ensure each baseline is counted only once.
- Baselines represent known-good configuration snapshots that SCM compares against during policy evaluations.
- A zero count indicates SCM has not yet captured any baseline snapshots.

---

## Profile Types

### Query: Count Custom vs Out-of-the-Box Profiles

/* Categorize SCM profiles as "Custom" or "Out of the Box" and count each type, excluding externally managed profiles. | Entities: `Orion.SCM.Profiles` */

```sql
SELECT
    CASE
        WHEN BuiltIn = 'True' THEN 'Out of the Box'
        ELSE 'Custom'
    END AS [Profile Type],
    COUNT(*) AS [Count of Profiles]
FROM
    Orion.SCM.Profiles
WHERE
    ManagedExternally != 'True'
GROUP BY
    CASE
        WHEN BuiltIn = 'True' THEN 'Out of the Box'
        ELSE 'Custom'
    END;
```

**Key points**:
- The `BuiltIn` field distinguishes factory-shipped profiles from user-created ones.
- `ManagedExternally != 'True'` filters out profiles pushed by external management tools (e.g., SolarWinds Hybrid Cloud Observability content packs).
- The `CASE` expression must be repeated in both `SELECT` and `GROUP BY` since SWQL does not support column alias references in `GROUP BY`.
- Useful for auditing how much customization has been applied to the SCM configuration.

---

## Data Retention

### Query: SCM and Policy Engine Data Retention Settings

/* Display SCM and Policy Engine data retention settings, showing current values versus defaults. | Entities: `Orion.Settings` */

```sql
SELECT
    Replace(SettingID, '-', ' ') AS [Setting ID],
    Name,
    CONCAT(ToString(CurrentValue), ' ', [Units]) AS [Current Value],
    CASE
        WHEN CurrentValue = DefaultValue THEN 'Yes'
        ELSE CONCAT(TOSTRING(DefaultValue), ' ', [Units])
    END AS [Default Value]
FROM
    Orion.Settings
WHERE
    (settingid LIKE '%scm%' OR settingid LIKE '%policyengine%')
    AND (
        settingid = 'PolicyEngine-Retain Daily'
        OR settingid = 'SCM-Retain Daily'
        OR settingid = 'SCM-Retain Detail'
        OR settingid = 'SCM-Retain Hourly'
    );
```

**Key points**:
- Targets four specific retention settings: `PolicyEngine-Retain Daily`, `SCM-Retain Daily`, `SCM-Retain Detail`, and `SCM-Retain Hourly`.
- The `Default Value` column shows "Yes" when the current value matches the default, otherwise it displays the default for comparison.
- `Replace(SettingID, '-', ' ')` makes the setting identifiers more human-readable.
- Adjusting these retention values impacts database size; shorter retention reduces storage while longer retention preserves historical change data.

---

## FIM Excluded Nodes

### Query: Count FIM-Disabled Nodes

/* Count the number of nodes where File Integrity Monitoring (FIM) has been explicitly disabled. | Entities: `Orion.SCM.FimDisabledNodes` */

```sql
SELECT
    Count(NodeID) AS [FIM Disabled Count]
FROM
    Orion.SCM.FimDisabledNodes;
```

**Key points**:
- FIM (File Integrity Monitoring) tracks file-system changes on monitored servers.
- Nodes in this table have been explicitly excluded from FIM, even though they may still be monitored by other SCM profiles.
- A high count may indicate intentional exclusions (e.g., high-churn servers) or misconfiguration worth reviewing.

---

## Monitored Nodes

### Query: Count SCM-Monitored Nodes

/* Count the total number of enabled nodes being monitored by SCM. | Entities: `Orion.SCM.ServerConfiguration` */

```sql
SELECT
    Count(NodeID) AS [Monitored Node Count]
FROM
    Orion.SCM.ServerConfiguration
WHERE
    Enabled = 'True';
```

**Key points**:
- The `Enabled = 'True'` filter ensures only actively monitored nodes are counted; disabled entries are excluded.
- `Orion.SCM.ServerConfiguration` stores the per-node SCM monitoring configuration.
- Compare this count against your total node count to determine SCM coverage across the environment.

---

## Polling Settings

### Query: "Who Made The Change" Detection Setting

/* Check whether the SCM "Who Made The Change" detection feature (FIM driver-based watching) is enabled. | Entities: `Orion.Setting` */

```sql
SELECT
    CASE
        WHEN Name = 'SCM.FimDriverWatchingEnabled' THEN '"Who Made The Change Detection"'
    END AS [Server Configuration Monitor Settings],
    CASE
        WHEN DefaultValue = 'False' THEN 'Not Enabled'
        ELSE 'Enabled'
    END AS [Setting],
    Description AS [Description]
FROM
    Orion.Setting
WHERE
    Name = 'SCM.FimDriverWatchingEnabled';
```

**Key points**:
- The `SCM.FimDriverWatchingEnabled` setting controls the FIM kernel-mode driver that intercepts file-system changes in real time to capture the user or process responsible.
- Note this queries `Orion.Setting` (singular), not `Orion.Settings` (plural) -- these are different entities in the SWQL schema.
- When enabled, SCM can attribute configuration changes to specific user accounts rather than only detecting that a change occurred.
- Enabling this feature requires the SolarWinds agent and may increase resource usage on monitored servers.

---

## Who Made Changes

### Query: Who Made Changes Detection Status (Alternate)

/* Verify the "Who Made Changes" detection feature status using the `Orion.Setting` entity. | Entities: `Orion.Setting` */

```sql
SELECT
    CASE
        WHEN Name = 'SCM.FimDriverWatchingEnabled' THEN '"Who Made Changes'
    END AS [Server Configuration Monitor Settings],
    CASE
        WHEN DefaultValue = 'False' THEN 'Not Enabled'
        ELSE 'Enabled'
    END AS [Setting],
    Description AS [Description]
FROM
    Orion.Setting
WHERE
    Name = 'SCM.FimDriverWatchingEnabled';
```

**Key points**:
- This is a variant of the Polling Settings query above, sourced from a different file; functionally equivalent.
- Both queries check the same `SCM.FimDriverWatchingEnabled` setting to determine if change-attribution is active.
- The "Who Made Changes" feature is a premium SCM capability that requires the FIM driver to be deployed on target nodes.

---



