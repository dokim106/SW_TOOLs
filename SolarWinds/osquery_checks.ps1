<#
  osquery_checks.ps1 — Windows threat-hunting wrapper for osquery
  - Ensures osquery is installed (WinGet or GitHub MSI)
  - Runs a broad sweep via osquery and writes JSON results to a timestamped folder
  - Builds a Scheduled Tasks triage CSV highlighting items to eyeball first

  Usage (Admin):
    powershell -ExecutionPolicy Bypass -File .\osquery_checks.ps1
    # Quick mode:
    powershell -ExecutionPolicy Bypass -File .\osquery_checks.ps1 -Quick
#>

[CmdletBinding()]
param(
  [string]$OutDir = (Join-Path $env:USERPROFILE ("Downloads\\osquery_hunt_{0:yyyyMMdd_HHmmss}" -f (Get-Date))),
  [switch]$Quick
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# Warn if not elevated
$IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $IsAdmin) { Write-Warning "Run as Administrator for full visibility (services/registry/etc.)." }

# =====================[ BOOTSTRAP: Ensure osquery exists ]====================
function Ensure-Osquery {
  [CmdletBinding()]
  param()

  $candidates = @(
    'C:\\Program Files\\osquery\\osqueryi.exe',
    'C:\\Program Files (x86)\\osquery\\osqueryi.exe',
    (Get-Command osqueryi.exe -ErrorAction SilentlyContinue).Path
  ) | Where-Object { $_ -and (Test-Path $_) }

  if ($candidates) { return ($candidates | Select-Object -First 1) }

  Write-Host "[*] osquery not found; attempting install…"

  $winget = (Get-Command winget.exe -ErrorAction SilentlyContinue).Path
  if ($winget) {
    $args = @('install','-e','--id','osquery.osquery','--accept-source-agreements','--accept-package-agreements')
    Start-Process -FilePath $winget -ArgumentList $args -NoNewWindow -Wait
  } else {
    try {
      [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
      $hdr = @{ 'User-Agent' = 'PowerShell-osquery-bootstrap' }
      $rel = Invoke-RestMethod -Uri 'https://api.github.com/repos/osquery/osquery/releases/latest' -Headers $hdr -ErrorAction Stop
      $asset = $rel.assets | Where-Object { $_.name -match '\\.msi$' } | Select-Object -First 1
      if (-not $asset) { throw "No MSI asset in latest release." }

      $msiPath = Join-Path $env:TEMP $asset.name
      Write-Host "[*] Downloading $($asset.name)…"
      Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $msiPath -UseBasicParsing
      Write-Host "[*] Installing MSI (quiet)…"
      Start-Process msiexec.exe -ArgumentList @('/i',"`"$msiPath`"","/qn","/norestart") -Wait -NoNewWindow
    } catch {
      throw "Failed to download/install osquery automatically: $($_.Exception.Message)"
    }
  }

  $candidates = @(
    'C:\\Program Files\\osquery\\osqueryi.exe',
    'C:\\Program Files (x86)\\osquery\\osqueryi.exe',
    (Get-Command osqueryi.exe -ErrorAction SilentlyContinue).Path
  ) | Where-Object { $_ -and (Test-Path $_) }

  if (-not $candidates) { throw "osquery installation appears to have failed." }
  $exe = $candidates | Select-Object -First 1
  Write-Host "[+] osquery installed: $exe"
  return $exe
}

# Helper: feed SQL via STDIN, capture JSON + STDERR
function Invoke-OsqJson {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$Sql,
    [Parameter(Mandatory)][string]$OutFile,
    [Parameter()][string]$OsqPath
  )
  if (-not $OsqPath) { throw "Invoke-OsqJson requires -OsqPath" }
  $tmp = New-Item -ItemType File -Path ([System.IO.Path]::GetTempFileName()) -Force
  Set-Content -Path $tmp -Value $Sql -Encoding UTF8

  $err = "$OutFile.err"
  Start-Process -FilePath $OsqPath -ArgumentList '--json' -NoNewWindow -Wait `
    -RedirectStandardInput $tmp -RedirectStandardOutput $OutFile -RedirectStandardError $err
  Remove-Item $tmp -Force

  if (-not (Test-Path $OutFile) -or (Get-Item $OutFile).Length -eq 0) {
    if ((Test-Path $err) -and ((Get-Item $err).Length -gt 0)) {
      Write-Warning "No data in $(Split-Path $OutFile -Leaf). See $(Split-Path $err -Leaf)."
    } else { '[]' | Set-Content -Path $OutFile -Encoding UTF8 }
  }
}
# ============================================================================

# Ensure osquery & output folder
$OSQ = Ensure-Osquery
try { & $OSQ --version | Out-Host } catch {}
New-Item -ItemType Directory -Path $OutDir -Force | Out-Null

# Query bag
$Q = [ordered]@{}
$Q.Ping = "SELECT 'alive' AS ping;"

$Q.Listeners = @"
WITH lp AS (SELECT pid,address,port FROM listening_ports WHERE address NOT IN ('127.0.0.1','::1')),
jx AS (SELECT lp.address,lp.port,p.pid,p.name,p.path,p.cmdline FROM lp JOIN processes p ON p.pid=lp.pid WHERE p.path LIKE 'C:\\%'),
res AS (SELECT jx.address,jx.port,jx.pid,jx.name,jx.path,jx.cmdline,a.result AS sig_result,a.subject_name FROM jx LEFT JOIN authenticode a ON a.path=jx.path)
SELECT address,port,pid,name,path,cmdline,sig_result,subject_name,
  CASE
    WHEN path LIKE 'C:\\Users\\%\\AppData\\%' OR path LIKE 'C:\\ProgramData\\%' OR path LIKE '%\\Temp\\%' THEN 'User/Temp path listener'
    WHEN (sig_result NOT IN ('trusted','Signed') OR sig_result IS NULL) THEN 'Unsigned/Unknown signature'
    WHEN port NOT IN (135,139,445,3389,5357,5985,5986)
         AND path NOT LIKE 'C:\\Windows\\System32\\svchost.exe'
         AND path NOT LIKE 'C:\\Windows\\System32\\dllhost.exe'
         AND path NOT LIKE 'C:\\Windows\\System32\\spoolsv.exe' THEN 'Non-standard port'
    ELSE 'Review'
  END AS reason
FROM res
WHERE reason <> 'Review'
ORDER BY port;
"@

$Q.Conns = @"
WITH pos AS (SELECT pid,local_address,local_port,remote_address,remote_port,state FROM process_open_sockets WHERE state='ESTABLISHED'),
pub AS (SELECT * FROM pos WHERE remote_address NOT LIKE '127.%' AND remote_address NOT LIKE '10.%' AND remote_address NOT LIKE '192.168.%' AND remote_address NOT LIKE '169.254.%' AND remote_address NOT LIKE '172.%' AND remote_address NOT LIKE 'fe80:%' AND remote_address<>'' ),
jx AS (SELECT pub.local_address,pub.local_port,pub.remote_address,pub.remote_port,p.pid,p.name,p.path,p.cmdline FROM pub JOIN processes p ON p.pid=pub.pid WHERE p.path LIKE 'C:\\%'),
res AS (SELECT jx.local_address,jx.local_port,jx.remote_address,jx.remote_port,jx.pid,jx.name,jx.path,jx.cmdline,a.result AS sig_result,a.subject_name FROM jx LEFT JOIN authenticode a ON a.path=jx.path)
SELECT local_address,local_port,remote_address,remote_port,pid,name,path,cmdline,sig_result,subject_name,
  CASE
    WHEN path LIKE 'C:\\Users\\%\\AppData\\%' OR path LIKE 'C:\\ProgramData\\%' OR path LIKE '%\\Temp\\%' THEN 'User/Temp binary to Internet'
    WHEN (sig_result NOT IN ('trusted','Signed') OR sig_result IS NULL) THEN 'Unsigned binary to Internet'
    ELSE 'Review'
  END AS reason
FROM res
WHERE reason <> 'Review';
"@

$Q.Services = @"
WITH base AS (SELECT name,start_type,user_account,path AS raw_path FROM services WHERE start_type='AUTO_START'),
s1 AS (SELECT name,user_account,raw_path,
  CASE WHEN lower(raw_path) LIKE '\\systemroot\\%' THEN replace(raw_path,'\\SystemRoot\\','C:\\Windows\\')
       WHEN lower(raw_path) LIKE 'system32\\%'     THEN 'C:\\Windows\\' || raw_path
       WHEN lower(raw_path) LIKE '\\??\\%'         THEN replace(raw_path,'\\??\\','')
       ELSE raw_path END AS p1 FROM base),
s2 AS (SELECT name,user_account,raw_path, CASE WHEN substr(p1,1,1)='"' THEN substr(p1,2) ELSE p1 END AS p2 FROM s1),
s3 AS (SELECT name,user_account,raw_path, replace(CASE WHEN instr(lower(p2),'.exe')>0 THEN substr(p2,1,instr(lower(p2),'.exe')+3) ELSE p2 END,'""','') AS bin FROM s2)
SELECT s.name,s.user_account,s.raw_path,s.bin,a.result AS sig_result,a.subject_name,
  CASE
    WHEN s.bin LIKE 'C:\\Users\\%\\AppData\\%' OR s.bin LIKE 'C:\\ProgramData\\%' OR s.bin LIKE '%\\Temp\\%' THEN 'User/Temp service'
    WHEN (a.result NOT IN ('trusted','Signed') OR a.result IS NULL) AND s.bin LIKE 'C:\\%' THEN 'Unsigned service'
    ELSE 'Review'
  END AS reason
FROM s3 s LEFT JOIN authenticode a ON a.path=s.bin
WHERE s.bin LIKE 'C:\\%' AND reason <> 'Review';
"@

$Q.Tasks = @"
WITH st AS (SELECT name,path AS raw_path,action AS raw_action,enabled,hidden FROM scheduled_tasks WHERE enabled=1),
norm AS (SELECT name,enabled,hidden,raw_action, replace(CASE WHEN instr(lower(raw_action),'.exe')>0 THEN substr(raw_action,1,instr(lower(raw_action),'.exe')+3) ELSE raw_action END,'""','') AS bin FROM st)
SELECT n.name,n.hidden,n.raw_action,n.bin,a.result AS sig_result,a.subject_name,
  CASE
    WHEN n.bin LIKE 'C:\\Users\\%\\AppData\\%' OR n.bin LIKE 'C:\\ProgramData\\%' OR n.bin LIKE '%\\Temp\\%' THEN 'User/Temp task'
    WHEN (a.result NOT IN ('trusted','Signed') OR a.result IS NULL) AND n.bin LIKE 'C:\\%' THEN 'Unsigned task'
    WHEN n.hidden=1 THEN 'Hidden task'
    ELSE 'Review'
  END AS reason
FROM norm n LEFT JOIN authenticode a ON a.path=n.bin
WHERE reason <> 'Review';
"@

$Q.StartupItems = @"
WITH si AS (SELECT username,name,path AS raw_path,args,status,source FROM startup_items WHERE status='enabled'),
norm AS (SELECT username,name,source,raw_path, replace(CASE WHEN instr(lower(raw_path),'.exe')>0 THEN substr(raw_path,1,instr(lower(raw_path),'.exe')+3) ELSE raw_path END,'""','') AS bin FROM si)
SELECT n.username,n.name,n.source,n.raw_path,n.bin,a.result AS sig_result,a.subject_name,
  CASE
    WHEN n.bin LIKE 'C:\\Users\\%\\AppData\\%' OR n.bin LIKE 'C:\\ProgramData\\%' OR n.bin LIKE '%\\Temp\\%' THEN 'User/Temp startup'
    WHEN (a.result NOT IN ('trusted','Signed') OR a.result IS NULL) AND n.bin LIKE 'C:\\%' THEN 'Unsigned startup'
    ELSE 'Review'
  END AS reason
FROM norm n LEFT JOIN authenticode a ON a.path=n.bin
WHERE reason <> 'Review';
"@

$Q.Drivers = @"
WITH drv AS (
  SELECT device_name, image AS raw_image,
    CASE WHEN lower(image) LIKE '\\systemroot\\%' THEN replace(image,'\\SystemRoot\\','C:\\Windows\\')
         WHEN lower(image) LIKE 'system32\\%'     THEN 'C:\\Windows\\' || image
         WHEN lower(image) LIKE '\\??\\%'         THEN replace(image,'\\??\\','')
         ELSE image END AS bin
  FROM drivers WHERE image!='' AND image IS NOT NULL
)
SELECT d.device_name,d.raw_image,d.bin,a.result AS sig_result,a.subject_name
FROM drv d LEFT JOIN authenticode a ON a.path=d.bin
WHERE d.bin LIKE 'C:\\%' AND (a.result NOT IN ('trusted','Signed') OR a.result IS NULL);
"@

$Q.RunHKLMHKCU = @"
WITH r AS (SELECT key,name,data AS raw FROM registry
  WHERE key LIKE 'HKEY_LOCAL_MACHINE\\Software\\Microsoft\\Windows\\CurrentVersion\\Run%'
     OR key LIKE 'HKEY_CURRENT_USER\\Software\\Microsoft\\Windows\\CurrentVersion\\Run%'),
sel AS (SELECT key,name,raw, replace(CASE WHEN instr(lower(raw),'.exe')>0 THEN substr(raw,1,instr(lower(raw),'.exe')+3) ELSE raw END,'""','') AS bin FROM r)
SELECT key,name,raw AS raw_value,bin,a.result AS sig_result,a.subject_name
FROM sel LEFT JOIN authenticode a ON a.path=bin
WHERE (bin LIKE 'C:\\Users\\%\\AppData\\%' OR bin LIKE 'C:\\ProgramData\\%' OR bin LIKE '%\\Temp\\%')
   OR ((a.result NOT IN ('trusted','Signed') OR a.result IS NULL) AND bin LIKE 'C:\\%');
"@

$Q.RunAllUsers = @"
WITH r AS (SELECT key,name,data AS raw FROM registry WHERE key LIKE 'HKEY_USERS\\%\\Software\\Microsoft\\Windows\\CurrentVersion\\Run%'),
sel AS (SELECT key,name,raw, replace(CASE WHEN instr(lower(raw),'.exe')>0 THEN substr(raw,1,instr(lower(raw),'.exe')+3) ELSE raw END,'""','') AS bin FROM r)
SELECT key,name,raw AS raw_value,bin,a.result AS sig_result,a.subject_name
FROM sel LEFT JOIN authenticode a ON a.path=bin
WHERE (bin LIKE 'C:\\Users\\%\\AppData\\%' OR bin LIKE 'C:\\ProgramData\\%' OR bin LIKE '%\\Temp\\%')
   OR ((a.result NOT IN ('trusted','Signed') OR a.result IS NULL) AND bin LIKE 'C:\\%');
"@

$Q.IFEO = "SELECT key,name,data AS value FROM registry WHERE (key LIKE 'HKEY_LOCAL_MACHINE\\SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion\\Image File Execution Options\\%' AND name='Debugger') OR (key LIKE 'HKEY_LOCAL_MACHINE\\SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion\\SilentProcessExit\\%' AND name IN ('MonitorProcess','ReportingMode'));"
$Q.Winlogon = "WITH w AS (SELECT name,data AS value FROM registry WHERE key='HKEY_LOCAL_MACHINE\\SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion\\Winlogon' AND name IN ('Shell','Userinit')) SELECT name,value, CASE WHEN name='Shell' AND lower(value) NOT LIKE '%explorer.exe%' THEN 'Shell hijack?' WHEN name='Userinit' AND lower(value) NOT LIKE '%\\system32\\userinit.exe%' THEN 'Userinit should be in "C:\Windows\System32\userinit.exe"' ELSE 'OK' END AS assessment FROM w WHERE assessment <> 'OK';"
$Q.AppInit = "WITH w AS (SELECT name,data AS value FROM registry WHERE key='HKEY_LOCAL_MACHINE\\SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion\\Windows' AND name IN ('AppInit_DLLs','LoadAppInit_DLLs')) SELECT * FROM w WHERE (name='LoadAppInit_DLLs' AND value NOT IN ('0','0x0','FALSE')) OR (name='AppInit_DLLs' AND value <> '');"
$Q.LSA = "SELECT name,data AS value FROM registry WHERE key='HKEY_LOCAL_MACHINE\\SYSTEM\\CurrentControlSet\\Control\\Lsa' AND name IN ('Security Packages','Authentication Packages','Notification Packages') AND (value LIKE '%:%' OR value LIKE '%\\%');"
$Q.BootExecute = "SELECT name,data AS value FROM registry WHERE key='HKEY_LOCAL_MACHINE\\SYSTEM\\CurrentControlSet\\Control\\Session Manager' AND name='BootExecute' AND lower(value) NOT LIKE '%autocheck autochk *%';"
$Q.WMI = "WITH b AS (SELECT filter,consumer FROM wmi_filter_consumer_binding), f AS (SELECT name AS filter_name,query FROM wmi_event_filters), s AS (SELECT name AS consumer_name,script_file_name,script_text FROM wmi_script_event_consumers) SELECT b.filter,f.query,b.consumer,s.script_file_name,s.script_text FROM b LEFT JOIN f ON f.filter_name=b.filter LEFT JOIN s ON s.consumer_name=b.consumer;"
$Q.COM = @"
WITH raw AS (
  SELECT key,name,data AS raw FROM registry
  WHERE (key LIKE 'HKEY_LOCAL_MACHINE\\Software\\Classes\\CLSID\\%\\InprocServer32'
     OR  key LIKE 'HKEY_CURRENT_USER\\Software\\Classes\\CLSID\\%\\InprocServer32')
    AND (name='' OR name='(Default)') AND data<>''
),
norm AS (
  SELECT key, replace(replace(replace(CASE
    WHEN lower(raw) LIKE '\\systemroot\\%' THEN replace(raw,'\\SystemRoot\\','C:\\Windows\\')
    WHEN lower(raw) LIKE '%systemroot%\\%' THEN replace(raw,'%SystemRoot%','C:\\Windows')
    WHEN lower(raw) LIKE '%windir%\\%'     THEN replace(raw,'%WinDir%','C:\\Windows')
    WHEN lower(raw) LIKE 'system32\\%'     THEN 'C:\\Windows\\' || raw
    WHEN lower(raw) LIKE '\\??\\%'         THEN replace(raw,'\\??\\','')
    ELSE raw END,'""',''),'\\System32\\','\\Windows\\System32\\'),'%SystemRoot%','C:\\Windows') AS dll
  FROM raw
)
SELECT n.key,n.dll,a.result AS sig_result,a.subject_name,
  CASE
    WHEN n.dll LIKE 'C:\\Users\\%\\AppData\\%' OR n.dll LIKE 'C:\\ProgramData\\%' OR n.dll LIKE '%\\Temp\\%' THEN 'User/Temp COM DLL'
    WHEN (a.result NOT IN ('trusted','Signed') OR a.result IS NULL) AND n.dll LIKE 'C:\\%' THEN 'Unsigned COM DLL'
    ELSE 'Review'
  END AS reason
FROM norm n LEFT JOIN authenticode a ON a.path=n.dll
WHERE reason <> 'Review';
"@

$Q.OnDisk0 = "SELECT pid,name,path,cmdline FROM processes WHERE on_disk=0 AND path LIKE '%:\\%' AND name NOT IN ('Registry','Memory Compression','vmmem','vmmemWSL','vmmemWSA','vmmemCm','vmmemCmZygote');"

# Decide run set
$jobs = @(
  @{Name='ping'        ; Sql=$Q.Ping        ; File='ping.json'},
  @{Name='listeners'   ; Sql=$Q.Listeners   ; File='suspicious_listeners.json'},
  @{Name='connections' ; Sql=$Q.Conns       ; File='suspicious_connections.json'},
  @{Name='services'    ; Sql=$Q.Services    ; File='suspicious_services.json'},
  @{Name='tasks'       ; Sql=$Q.Tasks       ; File='suspicious_tasks.json'},
  @{Name='startups'    ; Sql=$Q.StartupItems; File='suspicious_startup_items.json'},
  @{Name='autoruns'    ; Sql=$Q.RunHKLMHKCU ; File='suspicious_registry_run.json'},
  @{Name='autoruns_all'; Sql=$Q.RunAllUsers ; File='suspicious_registry_run_all_users.json'},
  @{Name='drivers'     ; Sql=$Q.Drivers     ; File='suspicious_drivers.json'},
  @{Name='ondisk0'     ; Sql=$Q.OnDisk0     ; File='suspicious_ondisk0.json'},
  @{Name='ifeo'        ; Sql=$Q.IFEO        ; File='suspicious_registry_ifeo.json'},
  @{Name='winlogon'    ; Sql=$Q.Winlogon    ; File='suspicious_registry_winlogon.json'},
  @{Name='appinit'     ; Sql=$Q.AppInit     ; File='suspicious_registry_appinit.json'},
  @{Name='lsa'         ; Sql=$Q.LSA         ; File='suspicious_registry_lsa.json'},
  @{Name='bootexecute' ; Sql=$Q.BootExecute ; File='suspicious_registry_bootexecute.json'},
  @{Name='wmi'         ; Sql=$Q.WMI         ; File='suspicious_wmi_bindings.json'},
  @{Name='com'         ; Sql=$Q.COM         ; File='suspicious_com_hijacks.json'}
)
if ($Quick) { $jobs = $jobs | Where-Object { $_.Name -in 'ping','listeners','connections','services','tasks','startups','autoruns','autoruns_all','ondisk0' } }

Write-Host "Using osquery: $OSQ"
Write-Host "Output: $OutDir"
foreach ($j in $jobs) {
  $out = Join-Path $OutDir $j.File
  Write-Host ("{0,-12} -> {1}" -f $j.Name, $j.File)
  Invoke-OsqJson -Sql $j.Sql -OutFile $out -OsqPath $OSQ
}

Write-Host "`nSummary:"
$summary = @()
foreach ($f in Get-ChildItem -Path $OutDir -Filter *.json) {
  try { $data = Get-Content $f.FullName -Raw | ConvertFrom-Json; $count = @($data).Count } catch { $count = 0 }
  $summary += [pscustomobject]@{ File=$f.Name; Count=$count; SizeBytes=$f.Length }
}
$summary | Sort-Object Count -Descending | Format-Table -AutoSize

# === Scheduled Tasks → triage CSV ============================================
try {
  $tasksJson = Join-Path $OutDir 'suspicious_tasks.json'
  if (Test-Path $tasksJson) {
    $tasks = Get-Content $tasksJson -Raw | ConvertFrom-Json
    if ($tasks) {
      function Clean-PathText([string]$s) {
        if ([string]::IsNullOrWhiteSpace($s)) { return "" }
        $t = $s.Trim().Trim('"', "'")
        return ($t -replace '\\s+', ' ')
      }
      $stdEnv = @('%windir%','%systemroot%','%systemdrive%','%localappdata%','%appdata%','%programfiles%','%programfiles(x86)%','%system32%','%programdata%')
      function Has-UnknownEnvVar([string]$s) {
        if ([string]::IsNullOrWhiteSpace($s)) { return $false }
        $matches = [regex]::Matches($s.ToLower(), '%[^%]+%') | ForEach-Object { $_.Value }
        foreach ($m in $matches) { if ($stdEnv -notcontains $m) { return $true } }
        return $false
      }
      function Get-Category([string]$bin) {
        $b = $bin.ToLower()
        if ([string]::IsNullOrWhiteSpace($b)) { return 'NoExeInAction/COM-or-script' }
        if ($b.StartsWith('c:\\windows\\system32') -or $b.StartsWith('c:\\windows\\systemroot') -or $b.StartsWith('%windir%') -or $b.StartsWith('%systemroot%')) { return 'Windows built-in' }
        if ($b -like '*\\users\\*\\appdata\\*') { return 'User AppData' }
        if ($b -like '*\\program files*') { return 'Program Files vendor' }
        if ($b -like '*windowsapps*') { return 'WindowsApps (Store alias)' }
        if ($b.StartsWith('%')) { return 'Env-var path' }
        'Other'
      }
      function Get-AttentionReasons($row, [string]$binClean, [string]$rawClean) {
        $reasons = New-Object System.Collections.Generic.List[string]
        $b = $binClean.ToLower()
        if (-not $binClean) { return $reasons }
        if ($b -like '*windowsapps*' -and $b -notlike '*\\windowsapps\\*') { $reasons.Add('Malformed WindowsApps path') }
        if (Has-UnknownEnvVar $binClean) { $reasons.Add('Unknown env var in path') }
        if ($b -like 'c:\\users\\*\\*' -and $rawClean -notmatch '(?i)googleupdate\.exe|onedrivestandaloneupdater\.exe') { $reasons.Add('Binary under user profile') }
        if ($b -like '*\\rundll32.exe*' -and $b -notlike '*\\system32\\*') { $reasons.Add('rundll32 outside System32') }
        if ($b -like '*\\cmd.exe*' -and $b -notlike '*\\system32\\*') { $reasons.Add('cmd outside System32') }
        $name = [string]$row.name
        if ($name -match 'GameTurbo') { $reasons.Add('Unknown GameTurbo task') }
        if ($name -match 'Apple Diagnostics') { $reasons.Add('Apple Diagnostics via WindowsApps') }
        if ($name -match 'NVIDIA App SelfUpdate' -and $rawClean -match '(?i)\\cef\\nvidia app\.exe') { $reasons.Add('Nested quoted path') }
        return $reasons
      }
      $rows = foreach ($t in $tasks) {
        $binClean = Clean-PathText $t.bin
        $rawClean = Clean-PathText $t.raw_action
        $cat      = Get-Category $binClean
        $reasons  = Get-AttentionReasons $t $binClean $rawClean
        [pscustomobject]@{
          name               = $t.name
          bin_clean          = $binClean
          raw_clean          = $rawClean
          category           = $cat
          needs_manual_check = ($reasons.Count -gt 0)
          attention_reasons  = ($reasons -join '; ')
        }
      }
      $triageCsv = Join-Path $OutDir 'scheduled_tasks_triage.csv'
      $rows | Export-Csv -NoTypeInformation -Encoding UTF8 $triageCsv
      Write-Host "Scheduled Tasks triage written -> $triageCsv"
    }
  }
} catch { Write-Warning "Triage CSV not created: $($_.Exception.Message)" }
# ============================================================================

Write-Host "`nTip:"
Write-Host "  Get-Content `"$OutDir<file>.json`" | ConvertFrom-Json | Format-Table -AutoSize"
Write-Host "Done."
