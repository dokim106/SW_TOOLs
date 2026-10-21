# SWQL Functions Reference

## SWQL General Functions

SWQL provides general-purpose functions for handling NULL values and conditional logic within queries.

### IsNull(a, b)

Returns `a` if it is not NULL; otherwise returns `b`. This is the SWQL equivalent of T-SQL's `ISNULL()` or ANSI SQL's `COALESCE()` for two arguments.

**Signature:** `IsNull(expression, replacement_value)`

- `expression` - The value to test for NULL
- `replacement_value` - The value returned when `expression` is NULL

```sql
SELECT Caption, IsNull(MachineType, 'Unknown') AS [Machine Type]
FROM Orion.Nodes
```

```sql
SELECT Caption,
       IsNull(Contact, 'No Contact Assigned') AS [Contact],
       IsNull(Location, 'Unassigned') AS [Location]
FROM Orion.Nodes
WHERE Status = 2
```

```sql
SELECT ComponentName,
       IsNull(ErrorMessage, 'No errors') AS [Last Error]
FROM Orion.APM.Component
WHERE ApplicationID = 15
```

### SWQL CASE WHEN Expression

The CASE expression provides conditional logic within SWQL queries. It evaluates conditions in order and returns the value associated with the first true condition.

**Simple CASE syntax:**

```sql
CASE expression
  WHEN value1 THEN result1
  WHEN value2 THEN result2
  ELSE default_result
END
```

**Searched CASE syntax:**

```sql
CASE
  WHEN condition1 THEN result1
  WHEN condition2 THEN result2
  ELSE default_result
END
```

```sql
SELECT Caption,
       CASE Status
         WHEN 1 THEN 'Up'
         WHEN 2 THEN 'Down'
         WHEN 3 THEN 'Warning'
         WHEN 9 THEN 'Unmanaged'
         WHEN 12 THEN 'Unreachable'
         ELSE 'Other'
       END AS [Status Text]
FROM Orion.Nodes
```

```sql
SELECT Caption, CPULoad,
       CASE
         WHEN CPULoad >= 95 THEN 'Critical'
         WHEN CPULoad >= 80 THEN 'Warning'
         WHEN CPULoad >= 0 THEN 'Normal'
         ELSE 'Unknown'
       END AS [CPU Status]
FROM Orion.Nodes
WHERE CPULoad IS NOT NULL
ORDER BY CPULoad DESC
```

## SWQL Numeric Functions

SWQL includes standard numeric functions for rounding, absolute values, and mathematical transformations. These functions operate on numeric property values and literal numbers.

### Abs(n) - SWQL Absolute Value

Returns the absolute (non-negative) value of a numeric expression.

**Signature:** `Abs(numeric_expression)`

```sql
SELECT Caption,
       CustomProperties.Latitude,
       CustomProperties.Longitude,
       Abs(CustomProperties.Latitude) AS [Abs Latitude]
FROM Orion.Nodes
WHERE CustomProperties.Latitude IS NOT NULL
```

```sql
SELECT n.Caption,
       Abs(n.CPULoad - 50) AS [Deviation From 50 Percent]
FROM Orion.Nodes n
WHERE n.CPULoad IS NOT NULL
ORDER BY Abs(n.CPULoad - 50) DESC
```

### Ceiling(n) - SWQL Ceiling Function

Returns the smallest integer that is greater than or equal to the specified numeric expression. Rounds up to the nearest whole number.

**Signature:** `Ceiling(numeric_expression)`

```sql
SELECT Caption,
       PercentMemoryUsed,
       Ceiling(PercentMemoryUsed) AS [Memory Percent Rounded Up]
FROM Orion.Nodes
WHERE PercentMemoryUsed IS NOT NULL
```

```sql
SELECT Caption,
       AvgResponseTime,
       Ceiling(AvgResponseTime) AS [Response Time Ceiling MS]
FROM Orion.ResponseTime
WHERE DateTime > AddHour(-1, GetUtcDate())
```

### Floor(n) - SWQL Floor Function

Returns the largest integer that is less than or equal to the specified numeric expression. Rounds down to the nearest whole number.

**Signature:** `Floor(numeric_expression)`

```sql
SELECT Caption,
       CPULoad,
       Floor(CPULoad) AS [CPU Whole Percent]
FROM Orion.Nodes
WHERE CPULoad IS NOT NULL
ORDER BY CPULoad DESC
```

```sql
SELECT Caption,
       TotalMemory,
       Floor(TotalMemory / 1073741824.0) AS [Total RAM GB]
FROM Orion.Nodes
WHERE TotalMemory > 0
```

### Round(n, p) - SWQL Round Function

Returns a numeric expression rounded to the specified number of decimal places.

**Signature:** `Round(numeric_expression, decimal_places)`

- `numeric_expression` - The value to round
- `decimal_places` - The number of decimal places to round to (0 for whole number)

```sql
SELECT Caption,
       PercentMemoryUsed,
       Round(PercentMemoryUsed, 1) AS [Memory Used Pct]
FROM Orion.Nodes
WHERE PercentMemoryUsed IS NOT NULL
ORDER BY PercentMemoryUsed DESC
```

```sql
SELECT n.Caption,
       Round(AVG(rt.AvgResponseTime), 2) AS [Avg Response MS]
FROM Orion.Nodes n
INNER JOIN Orion.ResponseTime rt ON rt.NodeID = n.NodeID
WHERE rt.DateTime > AddDay(-1, GetUtcDate())
GROUP BY n.Caption
ORDER BY AVG(rt.AvgResponseTime) DESC
```

```sql
SELECT Vendor,
       COUNT(*) AS [Node Count],
       Round(AVG(CPULoad), 1) AS [Avg CPU],
       Round(AVG(PercentMemoryUsed), 1) AS [Avg Memory]
FROM Orion.Nodes
WHERE CPULoad IS NOT NULL
GROUP BY Vendor
```

## SWQL String Functions

SWQL provides string manipulation functions for concatenation, searching, extraction, and case conversion. These are essential for formatting output, filtering by partial matches, and transforming entity property values.

### Concat(a, b, c, ...) - SWQL String Concatenation

Concatenates two or more values into a single string. Non-string values are implicitly converted. Accepts a variable number of arguments.

**Signature:** `Concat(value1, value2 [, value3, ...])`

```sql
SELECT Concat(Vendor, ' - ', MachineType) AS [Device Type]
FROM Orion.Nodes
WHERE Vendor IS NOT NULL
```

```sql
SELECT Concat(Caption, ' (', IP_Address, ')') AS [Node Summary]
FROM Orion.Nodes
ORDER BY Caption
```

```sql
SELECT Concat('Node ', Caption, ' has been down for ',
              ToString(DayDiff(LastBoot, GetUtcDate())), ' days') AS [Alert Summary]
FROM Orion.Nodes
WHERE Status = 2
```

### Length(s) - SWQL String Length

Returns the number of characters in a string expression.

**Signature:** `Length(string_expression)`

```sql
SELECT Caption, Length(Caption) AS [Name Length]
FROM Orion.Nodes
ORDER BY Length(Caption) DESC
```

```sql
SELECT Caption, Description
FROM Orion.Nodes
WHERE Length(Description) > 200
```

```sql
SELECT Caption, SysName
FROM Orion.Nodes
WHERE Length(SysName) > 0 AND SysName IS NOT NULL
```

### SubString(s, start, length) - SWQL Substring Extraction

Extracts a portion of a string starting at the specified position for the specified length. Position indexing is 1-based (the first character is position 1).

**Signature:** `SubString(string_expression, start_position, length)`

- `string_expression` - The source string
- `start_position` - The 1-based starting position
- `length` - The number of characters to extract

```sql
SELECT Caption,
       SubString(Caption, 1, 3) AS [Site Code]
FROM Orion.Nodes
WHERE Length(Caption) >= 3
```

```sql
SELECT Caption,
       SubString(IP_Address, 1, CharIndex('.', IP_Address) - 1) AS [First Octet]
FROM Orion.Nodes
WHERE IP_Address IS NOT NULL
```

```sql
SELECT InterfaceName,
       SubString(InterfaceName, 1, 10) AS [Short Name]
FROM Orion.NPM.Interfaces
WHERE Length(InterfaceName) > 10
```

### Replace(expression, pattern, replacement) - SWQL String Replace

Replaces all occurrences of a specified substring with a new substring. Available in Orion Platform 2017.3 and later.

**Signature:** `Replace(string_expression, search_string, replacement_string)`

**Minimum version:** Orion 2017.3+

```sql
SELECT Caption,
       Replace(Caption, '.example.com', '') AS [Short Name]
FROM Orion.Nodes
WHERE Caption LIKE '%.example.com'
```

```sql
SELECT Caption,
       Replace(Replace(Description, CHAR(13), ' '), CHAR(10), ' ') AS [Single Line Description]
FROM Orion.Nodes
WHERE Description IS NOT NULL
```

```sql
SELECT InterfaceName,
       Replace(InterfaceName, 'GigabitEthernet', 'Gi') AS [Short Interface]
FROM Orion.NPM.Interfaces
WHERE InterfaceName LIKE 'GigabitEthernet%'
```

### ToLower(a) - SWQL Lowercase Conversion

Converts all characters in a string expression to lowercase.

**Signature:** `ToLower(string_expression)`

```sql
SELECT Caption,
       ToLower(Caption) AS [Lowercase Name]
FROM Orion.Nodes
```

```sql
SELECT DISTINCT ToLower(Vendor) AS [Vendor]
FROM Orion.Nodes
WHERE Vendor IS NOT NULL
ORDER BY ToLower(Vendor)
```

### ToUpper(a) - SWQL Uppercase Conversion

Converts all characters in a string expression to uppercase.

**Signature:** `ToUpper(string_expression)`

```sql
SELECT Caption,
       ToUpper(Vendor) AS [Vendor]
FROM Orion.Nodes
WHERE Vendor IS NOT NULL
```

```sql
SELECT Caption
FROM Orion.Nodes
WHERE ToUpper(SysName) LIKE '%CORE%'
```

### ToString(a) - SWQL Value to String Conversion

Converts a numeric, datetime, or other typed value to its string representation. Useful for concatenation with `Concat()` or display formatting.

**Signature:** `ToString(expression)`

```sql
SELECT Concat('NodeID: ', ToString(NodeID), ' - ', Caption) AS [Node Info]
FROM Orion.Nodes
```

```sql
SELECT Caption,
       ToString(CPULoad) AS [CPU String],
       Concat(ToString(CPULoad), '%') AS [CPU Display]
FROM Orion.Nodes
WHERE CPULoad IS NOT NULL
```

### CharIndex(toFind, toSearch [, start]) - SWQL Character Position Search

Returns the 1-based position of the first occurrence of a substring within a string. Returns 0 if the substring is not found. An optional third argument specifies the starting position for the search. Available in Orion Platform 2018.2 and later.

**Signature:** `CharIndex(search_string, source_string [, start_position])`

- `search_string` - The substring to find
- `source_string` - The string to search within
- `start_position` (optional) - The 1-based position to start searching from

**Minimum version:** Orion 2018.2+

```sql
SELECT Caption,
       CharIndex('.', Caption) AS [First Dot Position]
FROM Orion.Nodes
WHERE CharIndex('.', Caption) > 0
```

```sql
SELECT Caption,
       SubString(Caption, 1, CharIndex('.', Caption) - 1) AS [Hostname]
FROM Orion.Nodes
WHERE CharIndex('.', Caption) > 0
```

```sql
SELECT InterfaceName,
       CharIndex('/', InterfaceName) AS [Slash Position]
FROM Orion.NPM.Interfaces
WHERE CharIndex('/', InterfaceName) > 0
```

### EscapeSWISUriValue(a) - SWQL URI Value Escaping

Escapes special characters in a value for safe use within SWIS URI strings. This is primarily used for internal or programmatic URI construction.

**Signature:** `EscapeSWISUriValue(string_expression)`

```sql
SELECT Caption,
       EscapeSWISUriValue(Caption) AS [Escaped Caption]
FROM Orion.Nodes
WHERE Caption LIKE '%/%' OR Caption LIKE '% %'
```

### UriEquals(a, b) - SWQL URI Comparison

Returns true if two SWIS URIs refer to the same entity, even if they differ in encoding or formatting. Used for comparing entity references reliably.

**Signature:** `UriEquals(uri_expression1, uri_expression2)`

```sql
SELECT n.Caption, a.Name AS [AlertName]
FROM Orion.AlertActive a
INNER JOIN Orion.Nodes n ON UriEquals(a.EntityUri, n.Uri)
WHERE a.Acknowledged = false
```

## SWQL Date and Time Functions

SWQL provides comprehensive date/time functions for retrieving the current time, converting between time zones, extracting date components, performing date arithmetic, computing differences, and truncating timestamps. All datetime values in SWIS are stored in UTC; the conversion functions translate between UTC and the Orion server's local time zone.

### GetDate() - SWQL Current Local DateTime

Returns the current date and time in the Orion server's local time zone.

**Signature:** `GetDate()`

```sql
SELECT GetDate() AS [Server Local Time]
```

```sql
SELECT Caption, LastSystemUpTimePollUtc
FROM Orion.Nodes
WHERE LastSystemUpTimePollUtc > AddHour(-1, GetDate())
```

### GetUtcDate() - SWQL Current UTC DateTime

Returns the current date and time in Coordinated Universal Time (UTC). This is the preferred function for time comparisons since SWIS stores datetimes in UTC.

**Signature:** `GetUtcDate()`

```sql
SELECT GetUtcDate() AS [Current UTC Time]
```

```sql
SELECT Caption, LastBoot
FROM Orion.Nodes
WHERE LastBoot > AddDay(-1, GetUtcDate())
ORDER BY LastBoot DESC
```

### ToLocal(d) - SWQL Convert to Local Time

Converts a UTC datetime value to the Orion server's local time zone. Use this when displaying stored UTC timestamps in a human-readable local format.

**Signature:** `ToLocal(datetime_expression)`

```sql
SELECT Caption,
       LastBoot AS [Last Boot UTC],
       ToLocal(LastBoot) AS [Last Boot Local]
FROM Orion.Nodes
WHERE LastBoot IS NOT NULL
ORDER BY LastBoot DESC
```

```sql
SELECT ToLocal(DateTime) AS [Local Time],
       AvgResponseTime
FROM Orion.ResponseTime
WHERE NodeID = 42
  AND DateTime > AddHour(-24, GetUtcDate())
ORDER BY DateTime DESC
```

### ToUtc(d) - SWQL Convert to UTC Time

Converts a local datetime value to UTC. Useful when a value has been input or displayed in local time and needs to be compared against UTC-stored data.

**Signature:** `ToUtc(datetime_expression)`

```sql
SELECT Caption, LastBoot
FROM Orion.Nodes
WHERE LastBoot > ToUtc(GetDate())
```

### SWQL DateTime Part Extraction Functions

These functions extract individual components from a datetime value. All accept a single datetime argument and return an integer.

| Function | Returns | Value Range |
|---|---|---|
| `Year(d)` | Four-digit year | e.g. 2026 |
| `Month(d)` | Month number | 1-12 |
| `Day(d)` | Day of month | 1-31 |
| `Hour(d)` | Hour | 0-23 |
| `Minute(d)` | Minute | 0-59 |
| `Second(d)` | Second | 0-59 |
| `Millisecond(d)` | Millisecond | 0-999 |
| `DayOfYear(d)` | Day number in year (Jan 1 = 1) | 1-366 |
| `WeekDay(d)` | Day of week (Sunday=0 through Saturday=6). **Orion 2016.1+** | 0-6 |
| `Week(d)` | ISO week number in year | 1-53 |
| `QuarterOfYear(d)` | Quarter of year | 1-4 |

```sql
SELECT Caption,
       ToLocal(LastBoot) AS [Last Boot],
       Year(LastBoot) AS [Boot Year],
       Month(LastBoot) AS [Boot Month],
       Day(LastBoot) AS [Boot Day]
FROM Orion.Nodes
WHERE LastBoot IS NOT NULL
```

```sql
SELECT Hour(DateTime) AS [Hour of Day],
       COUNT(*) AS [Event Count]
FROM Orion.Events
WHERE DateTime > AddDay(-7, GetUtcDate())
GROUP BY Hour(DateTime)
ORDER BY Hour(DateTime)
```

```sql
SELECT Caption, ToLocal(LastBoot) AS [Last Boot]
FROM Orion.Nodes
WHERE WeekDay(LastBoot) = 0
  AND LastBoot > AddMonth(-1, GetUtcDate())
ORDER BY LastBoot DESC
```

```sql
SELECT QuarterOfYear(DateTime) AS [Quarter],
       COUNT(*) AS [Alert Count]
FROM Orion.AlertHistory
WHERE DateTime > AddYear(-1, GetUtcDate())
GROUP BY QuarterOfYear(DateTime)
ORDER BY QuarterOfYear(DateTime)
```

```sql
SELECT DayOfYear(GetUtcDate()) AS [Current Day of Year],
       Week(GetUtcDate()) AS [Current Week Number]
```

### SWQL DateTime Arithmetic Functions (Add)

These functions add a specified number of time units to a datetime value and return a new datetime. The first argument `n` is the number of units to add (negative values subtract), and `d` is the source datetime.

| Function | Unit Added |
|---|---|
| `AddMillisecond(n, d)` | Milliseconds |
| `AddSecond(n, d)` | Seconds |
| `AddMinute(n, d)` | Minutes |
| `AddHour(n, d)` | Hours |
| `AddDay(n, d)` | Days |
| `AddWeek(n, d)` | Weeks |
| `AddMonth(n, d)` | Months |
| `AddYear(n, d)` | Years |

**Signature for all:** `AddUnit(integer_count, datetime_expression)`

The generic form `AddDate(unit, n, d)` accepts the unit as a string and is functionally identical:

**Signature:** `AddDate(unit_string, integer_count, datetime_expression)`

Valid `unit_string` values: `'millisecond'`, `'second'`, `'minute'`, `'hour'`, `'day'`, `'week'`, `'month'`, `'year'`

```sql
SELECT Caption, LastBoot
FROM Orion.Nodes
WHERE LastBoot > AddDay(-7, GetUtcDate())
ORDER BY LastBoot DESC
```

```sql
SELECT Caption, IP_Address
FROM Orion.Nodes
WHERE LastSystemUpTimePollUtc < AddHour(-2, GetUtcDate())
  AND Status = 1
```

```sql
SELECT DateTime, AvgResponseTime
FROM Orion.ResponseTime
WHERE NodeID = 42
  AND DateTime > AddMinute(-30, GetUtcDate())
ORDER BY DateTime DESC
```

```sql
SELECT Caption, LastBoot
FROM Orion.Nodes
WHERE LastBoot < AddMonth(-6, GetUtcDate())
  AND Status = 1
ORDER BY LastBoot ASC
```

```sql
-- Using the generic AddDate form
SELECT Caption, LastBoot
FROM Orion.Nodes
WHERE LastBoot > AddDate('week', -2, GetUtcDate())
ORDER BY LastBoot DESC
```

```sql
SELECT Caption
FROM Orion.Nodes
WHERE NextPoll < AddMinute(5, GetUtcDate())
  AND NextPoll > AddMinute(-5, GetUtcDate())
```

### SWQL DateTime Difference Functions

These functions compute the difference between two datetime values in the specified time unit. The result is the number of units that `b` is later than `a`, rounded to the nearest integer. A positive result means `b` is later; a negative result means `b` is earlier.

| Function | Unit Measured |
|---|---|
| `MillisecondDiff(a, b)` | Milliseconds |
| `SecondDiff(a, b)` | Seconds |
| `MinuteDiff(a, b)` | Minutes |
| `HourDiff(a, b)` | Hours |
| `DayDiff(a, b)` | Days |
| `WeekDiff(a, b)` | Weeks |
| `MonthDiff(a, b)` | Months |
| `YearDiff(a, b)` | Years |

**Signature for all:** `UnitDiff(datetime_a, datetime_b)`

```sql
SELECT Caption,
       DayDiff(LastBoot, GetUtcDate()) AS [Days Since Reboot]
FROM Orion.Nodes
WHERE LastBoot IS NOT NULL
ORDER BY DayDiff(LastBoot, GetUtcDate()) DESC
```

```sql
SELECT Caption,
       HourDiff(LastSystemUpTimePollUtc, GetUtcDate()) AS [Hours Since Last Poll]
FROM Orion.Nodes
WHERE HourDiff(LastSystemUpTimePollUtc, GetUtcDate()) > 4
```

```sql
SELECT Caption,
       MinuteDiff(LastBoot, GetUtcDate()) AS [Uptime Minutes],
       DayDiff(LastBoot, GetUtcDate()) AS [Uptime Days]
FROM Orion.Nodes
WHERE Status = 1
ORDER BY DayDiff(LastBoot, GetUtcDate()) DESC
```

```sql
SELECT n.Caption,
       MonthDiff(n.LastBoot, GetUtcDate()) AS [Months Since Boot]
FROM Orion.Nodes n
WHERE MonthDiff(n.LastBoot, GetUtcDate()) > 6
ORDER BY n.LastBoot ASC
```

```sql
SELECT Caption,
       SecondDiff(LastSystemUpTimePollUtc, GetUtcDate()) AS [Seconds Since Poll]
FROM Orion.Nodes
WHERE SecondDiff(LastSystemUpTimePollUtc, GetUtcDate()) > 600
```

### DateTrunc('datepart', d) - SWQL DateTime Truncation

Truncates a datetime value to the specified granularity by zeroing out all less-significant components. This is essential for grouping time-series data into uniform time buckets.

**Signature:** `DateTrunc(datepart_string, datetime_expression)`

Valid `datepart_string` values:

| Datepart | Truncates to |
|---|---|
| `'minute'` | Start of the minute (seconds and below zeroed) |
| `'hour'` | Start of the hour (minutes and below zeroed) |
| `'day'` | Start of the day (midnight) |
| `'week'` | Start of the week (Monday) |
| `'month'` | First day of the month |
| `'quarter'` | First day of the quarter |
| `'year'` | January 1st of the year |

```sql
SELECT DateTrunc('hour', DateTime) AS [Hour],
       AVG(AvgResponseTime) AS [Avg Response MS]
FROM Orion.ResponseTime
WHERE NodeID = 42
  AND DateTime > AddDay(-1, GetUtcDate())
GROUP BY DateTrunc('hour', DateTime)
ORDER BY DateTrunc('hour', DateTime)
```

```sql
SELECT DateTrunc('day', DateTime) AS [Date],
       COUNT(*) AS [Event Count]
FROM Orion.Events
WHERE DateTime > AddDay(-30, GetUtcDate())
GROUP BY DateTrunc('day', DateTime)
ORDER BY DateTrunc('day', DateTime)
```

```sql
SELECT DateTrunc('month', DateTime) AS [Month],
       AVG(AvgLoad) AS [Avg CPU]
FROM Orion.CPULoad
WHERE DateTime > AddYear(-1, GetUtcDate())
GROUP BY DateTrunc('month', DateTime)
ORDER BY DateTrunc('month', DateTime)
```

```sql
SELECT DateTrunc('week', DateTime) AS [Week Start],
       MIN(AvgResponseTime) AS [Min Response],
       MAX(AvgResponseTime) AS [Max Response],
       AVG(AvgResponseTime) AS [Avg Response]
FROM Orion.ResponseTime
WHERE NodeID = 42
  AND DateTime > AddMonth(-3, GetUtcDate())
GROUP BY DateTrunc('week', DateTime)
ORDER BY DateTrunc('week', DateTime)
```

### Downsample(d, p) - SWQL Timestamp Downsampling

Rounds a datetime value to a defined sampling period. This is useful for aligning timestamps to consistent intervals when charting or aggregating time-series data. Available in Orion Platform 2018.3 and later.

**Signature:** `Downsample(datetime_expression, period_minutes)`

**Minimum version:** Orion 2018.3+

```sql
SELECT Downsample(DateTime, 5) AS [Five Min Bucket],
       AVG(AvgResponseTime) AS [Avg Response MS]
FROM Orion.ResponseTime
WHERE NodeID = 42
  AND DateTime > AddHour(-6, GetUtcDate())
GROUP BY Downsample(DateTime, 5)
ORDER BY Downsample(DateTime, 5)
```

```sql
SELECT Downsample(DateTime, 15) AS [Quarter Hour],
       AVG(AvgLoad) AS [Avg CPU],
       MAX(AvgLoad) AS [Peak CPU]
FROM Orion.CPULoad
WHERE NodeID = 42
  AND DateTime > AddDay(-1, GetUtcDate())
GROUP BY Downsample(DateTime, 15)
ORDER BY Downsample(DateTime, 15)
```

## SWQL Aggregate Functions

SWQL supports standard SQL aggregate functions for summarizing data. When used with a `GROUP BY` clause, aggregates are computed per group. Without `GROUP BY`, they operate across all rows in the result set.

**Important:** All aggregate functions except `COUNT(*)` ignore NULL values. `COUNT(*)` counts all rows regardless of NULL.

### COUNT(n) - SWQL Row and Value Counting

Counts the number of rows or non-NULL values.

**Signatures:**

- `COUNT(*)` - Counts all rows including those with NULL values
- `COUNT(expression)` - Counts rows where `expression` is not NULL

```sql
SELECT COUNT(*) AS [Total Nodes]
FROM Orion.Nodes
```

```sql
SELECT Status, COUNT(*) AS [Node Count]
FROM Orion.Nodes
GROUP BY Status
```

```sql
SELECT Vendor, COUNT(*) AS [Total Nodes]
FROM Orion.Nodes
WHERE Vendor IS NOT NULL
GROUP BY Vendor
ORDER BY COUNT(*) DESC
```

```sql
SELECT n.Caption,
       COUNT(i.InterfaceID) AS [Interface Count]
FROM Orion.Nodes n
LEFT JOIN Orion.NPM.Interfaces i ON i.NodeID = n.NodeID
GROUP BY n.Caption
ORDER BY COUNT(i.InterfaceID) DESC
```

### SUM(n) - SWQL Arithmetic Sum

Returns the arithmetic sum of all non-NULL values in the specified expression.

**Signature:** `SUM(numeric_expression)`

```sql
SELECT SUM(TotalMemory) / 1073741824.0 AS [Total RAM Across All Nodes GB]
FROM Orion.Nodes
WHERE TotalMemory > 0
```

```sql
SELECT Vendor,
       SUM(TotalMemory) / 1073741824.0 AS [Total RAM GB]
FROM Orion.Nodes
WHERE TotalMemory > 0
GROUP BY Vendor
ORDER BY SUM(TotalMemory) DESC
```

```sql
SELECT n.Caption,
       SUM(i.InBps) AS [Total Inbound bps],
       SUM(i.OutBps) AS [Total Outbound bps]
FROM Orion.Nodes n
INNER JOIN Orion.NPM.Interfaces i ON i.NodeID = n.NodeID
GROUP BY n.Caption
ORDER BY SUM(i.InBps) DESC
```

### AVG(n) - SWQL Arithmetic Mean

Returns the arithmetic mean (average) of all non-NULL values in the specified expression.

**Signature:** `AVG(numeric_expression)`

```sql
SELECT AVG(CPULoad) AS [Average CPU Across All Nodes]
FROM Orion.Nodes
WHERE CPULoad IS NOT NULL
```

```sql
SELECT Vendor,
       COUNT(*) AS [Total],
       AVG(CPULoad) AS [Avg CPU],
       AVG(PercentMemoryUsed) AS [Avg Memory]
FROM Orion.Nodes
WHERE CPULoad IS NOT NULL
GROUP BY Vendor
ORDER BY AVG(CPULoad) DESC
```

```sql
SELECT n.Caption,
       AVG(rt.AvgResponseTime) AS [Avg Response MS]
FROM Orion.Nodes n
INNER JOIN Orion.ResponseTime rt ON rt.NodeID = n.NodeID
WHERE rt.DateTime > AddDay(-7, GetUtcDate())
GROUP BY n.Caption
HAVING AVG(rt.AvgResponseTime) > 100
ORDER BY AVG(rt.AvgResponseTime) DESC
```

### MIN(n) - SWQL Minimum Value

Returns the minimum (smallest) non-NULL value in the specified expression. Works with numeric, string, and datetime types.

**Signature:** `MIN(expression)`

```sql
SELECT MIN(CPULoad) AS [Lowest CPU Load]
FROM Orion.Nodes
WHERE CPULoad IS NOT NULL AND CPULoad > 0
```

```sql
SELECT Vendor,
       MIN(CPULoad) AS [Min CPU],
       MAX(CPULoad) AS [Max CPU]
FROM Orion.Nodes
WHERE CPULoad IS NOT NULL
GROUP BY Vendor
```

```sql
SELECT n.Caption,
       MIN(rt.AvgResponseTime) AS [Best Response MS],
       MAX(rt.AvgResponseTime) AS [Worst Response MS]
FROM Orion.Nodes n
INNER JOIN Orion.ResponseTime rt ON rt.NodeID = n.NodeID
WHERE rt.DateTime > AddDay(-1, GetUtcDate())
GROUP BY n.Caption
ORDER BY MAX(rt.AvgResponseTime) DESC
```

### MAX(n) - SWQL Maximum Value

Returns the maximum (largest) non-NULL value in the specified expression. Works with numeric, string, and datetime types.

**Signature:** `MAX(expression)`

```sql
SELECT MAX(CPULoad) AS [Highest CPU Load],
       MAX(PercentMemoryUsed) AS [Highest Memory Usage]
FROM Orion.Nodes
```

```sql
SELECT n.Caption,
       MAX(rt.AvgResponseTime) AS [Peak Response MS]
FROM Orion.Nodes n
INNER JOIN Orion.ResponseTime rt ON rt.NodeID = n.NodeID
WHERE rt.DateTime > AddHour(-6, GetUtcDate())
GROUP BY n.Caption
HAVING MAX(rt.AvgResponseTime) > 500
ORDER BY MAX(rt.AvgResponseTime) DESC
```

```sql
SELECT Caption,
       MAX(LastBoot) AS [Most Recent Boot]
FROM Orion.Nodes
WHERE LastBoot IS NOT NULL
GROUP BY Caption
```

### SWQL Aggregate Functions with GROUP BY Pattern

A combined example showing multiple aggregates with GROUP BY and HAVING:

```sql
SELECT Vendor,
       COUNT(*) AS [Total Nodes],
       SUM(CASE WHEN Status = 1 THEN 1 ELSE 0 END) AS [Up],
       SUM(CASE WHEN Status = 2 THEN 1 ELSE 0 END) AS [Down],
       AVG(CPULoad) AS [Avg CPU],
       MIN(CPULoad) AS [Min CPU],
       MAX(CPULoad) AS [Max CPU],
       AVG(PercentMemoryUsed) AS [Avg Memory]
FROM Orion.Nodes
GROUP BY Vendor
HAVING COUNT(*) > 5
ORDER BY COUNT(*) DESC
```

## SWQL Array Functions

SWQL includes functions for working with array-typed properties. Some SolarWinds entity properties return arrays (such as custom property multi-value fields or tag lists). These functions allow querying, inspecting, and decomposing those arrays within SWQL.

### ArrayContains(a, v) - SWQL Array Membership Test

Returns true if the array `a` contains the value `v`. Used to filter entities based on whether an array property includes a specific element.

**Signature:** `ArrayContains(array_expression, value)`

```sql
SELECT Caption
FROM Orion.Nodes
WHERE ArrayContains(CustomProperties.Tags, 'Production')
```

```sql
SELECT Caption, IP_Address
FROM Orion.Nodes
WHERE ArrayContains(CustomProperties.SupportTeams, 'NetworkOps')
  AND Status = 2
```

```sql
SELECT n.Caption
FROM Orion.Nodes n
WHERE ArrayContains(n.CustomProperties.Environments, 'DR')
  AND n.Status = 1
```

### ArrayLength(a) - SWQL Array Element Count

Returns the number of elements in the array `a`. Returns 0 for empty arrays and NULL for NULL arrays.

**Signature:** `ArrayLength(array_expression)`

```sql
SELECT Caption,
       ArrayLength(CustomProperties.Tags) AS [Tag Count]
FROM Orion.Nodes
WHERE ArrayLength(CustomProperties.Tags) > 0
ORDER BY ArrayLength(CustomProperties.Tags) DESC
```

```sql
SELECT Caption
FROM Orion.Nodes
WHERE ArrayLength(CustomProperties.SupportTeams) > 2
```

### ArrayValueAt(a, i) - SWQL Array Element Access

Returns the element at position `i` in array `a`. Array indexing is 0-based (the first element is at position 0).

**Signature:** `ArrayValueAt(array_expression, index)`

- `array_expression` - The array to access
- `index` - The 0-based position of the element

```sql
SELECT Caption,
       ArrayValueAt(CustomProperties.Tags, 0) AS [Primary Tag]
FROM Orion.Nodes
WHERE ArrayLength(CustomProperties.Tags) > 0
```

```sql
SELECT Caption,
       ArrayValueAt(CustomProperties.SupportTeams, 0) AS [Primary Team],
       ArrayValueAt(CustomProperties.SupportTeams, 1) AS [Secondary Team]
FROM Orion.Nodes
WHERE ArrayLength(CustomProperties.SupportTeams) >= 2
```

### SplitStringToArray(s) - SWQL String to Array Conversion

Splits a comma-delimited string into an array. This enables array operations on string properties that store multiple values as a single comma-separated string.

**Signature:** `SplitStringToArray(string_expression)`

```sql
SELECT Caption,
       ArrayLength(SplitStringToArray(CustomProperties.ServiceList)) AS [Service Count]
FROM Orion.Nodes
WHERE CustomProperties.ServiceList IS NOT NULL
```

```sql
SELECT Caption
FROM Orion.Nodes
WHERE ArrayContains(SplitStringToArray(CustomProperties.VLANs), '100')
```

```sql
SELECT Caption,
       ArrayValueAt(SplitStringToArray(CustomProperties.LocationPath), 0) AS [Region],
       ArrayValueAt(SplitStringToArray(CustomProperties.LocationPath), 1) AS [Site]
FROM Orion.Nodes
WHERE CustomProperties.LocationPath IS NOT NULL
  AND ArrayLength(SplitStringToArray(CustomProperties.LocationPath)) >= 2
```
