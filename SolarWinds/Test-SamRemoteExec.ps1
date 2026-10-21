<#
.SYNOPSIS
  Prove a remote Windows endpoint will accept SAM-style remote execution, and say exactly WHAT IS MISSING when it will not.

.DESCRIPTION
  Run this FROM THE POLLING ENGINE (or APE) that owns the node, as the credential assigned to the node in Orion.
  Checks, in order, and for every failure prints Requirement / Missing / Fix (a command to run on the target or the poller):
    Ports        135 RPC+WMI, 445 SMB (C$ read-back, also SAM perf counters), 5985/5986 WinRM
    Name         DNS resolution; warns when an IP is used for WinRM (Kerberos needs a name; NTLM needs TrustedHosts)
    WMI-auth     DCOM CimSession + Win32_OperatingSystem with the credential
    Target-state services Winmgmt / WinRM / RemoteRegistry / LanmanServer, firewall rule groups, admin shares, UAC remote
                 token filter, and whether the account is a member of the target's local Administrators (all read via WMI)
    WMI-exec     Win32_Process.Create runs powershell.exe on the target; output read back over \\target\C$
    WinRM-exec   Test-WSMan + Invoke-Command (the path SAM's Windows PowerShell Monitor uses in Remote Host mode)
    SAM-parse    (with -LogPath) the real log parse on the target: ERROR / CRITICAL|FATAL / WARN counts in SAM
                 Message.* / Statistic.* format, exit 0 Up, 2 Warning, 3 Critical

.PARAMETER ComputerName  The node SAM will poll (its polling IP or FQDN as set in Orion). Use the NAME for WinRM if you can.
.PARAMETER Credential    The node's Orion credential (must be a local admin on the target for WinRM / process creation).
.PARAMETER LogPath       Optional path ON THE TARGET to parse.
.PARAMETER SkipWmiExec   Do not launch a process through WMI.

.EXAMPLE
  $cred = Get-Credential CORP\svc_solarwinds
  .\Test-SamRemoteExec.ps1 -ComputerName srv-app01.corp.local -Credential $cred -LogPath 'C:\ProgramData\SolarWinds\Logs\Orion\Core.BusinessLayer.log'

  Exit code: 0 = all selected checks passed, 1 = something is missing (see the MISSING list at the end).
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)] [string]$ComputerName,
  [Parameter(Mandatory)] [pscredential]$Credential,
  [string]$LogPath,
  [switch]$SkipWmiExec
)
$ErrorActionPreference = 'Stop'
$results  = [ordered]@{}
$findings = New-Object System.Collections.Generic.List[object]
$isIp     = $ComputerName -match '^\d{1,3}(\.\d{1,3}){3}$'
$user     = $Credential.UserName
$userIsLocalAcct = ($user -notmatch '[\\@]') -or ($user -match '^(\.|localhost|' + [regex]::Escape($ComputerName) + ')\\')

function Missing($check, $requirement, $missing, $fix) {
  $findings.Add([pscustomobject]@{ Check=$check; Requirement=$requirement; Missing=$missing; Fix=$fix })
}
# Reduce WSMan/COM error blobs to their human sentence, single-spaced.
function ConvertTo-CleanMessage([string]$m) {
  if ($m -match '<f:Message>(.*?)</f:Message>') { $m = $Matches[1] }
  $m = $m -replace '\s+', ' '
  $m = $m -replace ' Use winrm\.cmd to configure TrustedHosts\..*$', ''   # drop Microsoft's boilerplate tail
  return $m.Trim()
}
# Print "label  text" with continuation lines indented under the text column.
function Write-Wrapped([string]$label, [string]$text, [string]$color = 'Gray', [int]$width = 150) {
  $indent = ' ' * $label.Length
  $words = $text -split ' '; $line = ''; $first = $true
  foreach ($w in $words) {
    if (($line.Length + $w.Length + 1) -gt $width -and $line) {
      Write-Host ($(if ($first) { $label } else { $indent }) + $line) -ForegroundColor $color; $line = ''; $first = $false
    }
    $line = if ($line) { "$line $w" } else { $w }
  }
  Write-Host ($(if ($first) { $label } else { $indent }) + $line) -ForegroundColor $color
}
function Step($name, [scriptblock]$body) {
  try { $out = ConvertTo-CleanMessage ("$(& $body)"); $results[$name] = "PASS  $out"; Write-Wrapped ("[PASS] {0,-13} " -f $name) $out Green; return $true }
  catch { $m = ConvertTo-CleanMessage $_.Exception.Message; $results[$name] = "FAIL  $m"; Write-Wrapped ("[FAIL] {0,-13} " -f $name) $m Red; return $false }
}
# Translate the usual WMI / WinRM error texts into what is missing.
function Diagnose($check, $msg) {
  switch -Regex ($msg) {
    '0x80070005|Access is denied|Access denied' {
      Missing $check 'Credential must be a local Administrator on the target (SAM WMI + PowerShell remote need it)' "$user is denied by the target" "On target: Add-LocalGroupMember -Group Administrators -Member '$user'   (or grant DCOM Remote Launch/Activation + WMI root\cimv2 Remote Enable if admin is not allowed)"
      if ($userIsLocalAcct) { Missing $check 'Local (non-domain) admin accounts are filtered by UAC over the network' 'LocalAccountTokenFilterPolicy=1 on the target' 'On target: reg add HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System /v LocalAccountTokenFilterPolicy /t REG_DWORD /d 1 /f' }
    }
    'general error occurred that is not covered' {
      if (-not $portState[135]) { Missing $check 'Target reachable on TCP 135 before WMI can even authenticate' 'WMI got no answer (135 closed / host down / wrong IP)' 'Fix the Ports findings first; confirm the polling IP in Orion and that the host is up' }
      else { Missing $check 'DCOM/WMI accepting the credential' 'WMI answered with a generic failure (often DCOM permissions or a firewall dropping the dynamic RPC port after 135)' 'On target: allow dynamic RPC 49152-65535 ; dcomcnfg > My Computer > COM Security: Remote Launch/Activation for the account ; wmimgmt.msc > Security root\cimv2: Remote Enable' }
    }
    '0x800706BA|RPC server is unavailable' {
      Missing $check 'TCP 135 + dynamic RPC 49152-65535 open, WMI service running' 'RPC/WMI path blocked or Winmgmt stopped' 'On target: netsh advfirewall firewall set rule group="Windows Management Instrumentation (WMI)" new enable=yes ; Set-Service Winmgmt -StartupType Automatic ; Start-Service Winmgmt'
    }
    '0x8007052E|user name or password is incorrect|Logon failure' {
      Missing $check 'Valid credential' "password/user rejected for $user" 'Fix the credential in Orion (Settings > Manage Windows Credentials) and re-test'
    }
    'WinRM cannot complete the operation|cannot connect|connection to the specified remote host was refused|5985' {
      Missing $check 'WinRM service + HTTP listener on 5985 (SAM PowerShell Monitor, Remote Host mode)' 'WinRM not enabled/listening or firewall closed' 'On target: Enable-PSRemoting -Force ; Set-Service WinRM -StartupType Automatic ; netsh advfirewall firewall set rule group="Windows Remote Management" new enable=yes'
    }
    'TrustedHosts|Kerberos|cannot be resolved|server name cannot be resolved' {
      Missing $check 'WinRM auth: Kerberos needs a resolvable NAME; an IP forces NTLM which needs TrustedHosts on the poller' "connecting by $(if ($isIp) {'IP'} else {'unresolvable name'})" "Use the FQDN in Orion, or on THIS poller: Set-Item WSMan:\localhost\Client\TrustedHosts -Value '$ComputerName' -Concatenate -Force   (or use HTTPS 5986 with a cert)"
    }
    'timed out|timeout' {
      Missing $check 'Network path to the target from this poller' 'no answer in time (firewall drop, wrong IP, host asleep)' 'Check the node polling IP in Orion, ping/tracert from this poller, firewall between poller and target'
    }
    'ReturnValue (2|3)' {
      Missing $check 'Win32_Process.Create right (local admin)' "$user cannot create processes via WMI" "On target: Add-LocalGroupMember -Group Administrators -Member '$user'$(if ($userIsLocalAcct) {' ; and set LocalAccountTokenFilterPolicy=1'})"
    }
    'no output file' {
      Missing $check 'powershell.exe allowed to run on the target and \\target\C$ reachable' 'process was created but nothing came back (AppLocker/AV blocked powershell, or C$ admin share off, or SMB 445 closed)' 'On target: check AppLocker/EDR logs for powershell.exe; reg query HKLM\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters /v AutoShareServer (must not be 0); open SMB-In'
    }
  }
}

# ---------- 1. ports ----------
$portState = @{}
Step 'Ports' {
  $r = foreach ($p in 135, 445, 5985, 5986) {
    $ok = Test-NetConnection -ComputerName $ComputerName -Port $p -WarningAction SilentlyContinue -InformationLevel Quiet
    $portState[$p] = $ok; "{0}={1}" -f $p, $(if ($ok) { 'open' } else { 'closed' })
  }
  if (-not $portState[135]) { Missing 'Ports' 'TCP 135 (RPC endpoint mapper) for WMI' '135 closed' 'On target: netsh advfirewall firewall set rule group="Windows Management Instrumentation (WMI)" new enable=yes ; also allow dynamic RPC 49152-65535 on any firewall in between' }
  if (-not $portState[445]) { Missing 'Ports' 'TCP 445 (SMB) for C$ read-back and SAM RPC performance counters' '445 closed' 'On target: netsh advfirewall firewall set rule group="File and Printer Sharing" new enable=yes' }
  if (-not $portState[5985] -and -not $portState[5986]) { Missing 'Ports' 'TCP 5985 (or 5986) WinRM for SAM PowerShell Monitor Remote Host mode' 'no WinRM listener reachable' 'On target: Enable-PSRemoting -Force ; netsh advfirewall firewall set rule group="Windows Remote Management" new enable=yes' }
  if (-not ($portState[135] -or $portState[5985] -or $portState[5986])) { throw "nothing open: $($r -join ' ')" }
  $r -join ' '
} | Out-Null

# ---------- 2. name resolution ----------
Step 'Name' {
  if ($isIp) {
    $rev = try { (Resolve-DnsName -Name $ComputerName -Type PTR -ErrorAction Stop | Select-Object -First 1).NameHost } catch { $null }
    Missing 'Name' 'WinRM/Kerberos works best with the FQDN' "you passed an IP$(if ($rev) {" (reverse DNS says $rev)"})" "Prefer -ComputerName $(if ($rev) {$rev} else {'<fqdn>'}); otherwise add the IP to TrustedHosts on this poller (see WinRM findings)"
    "IP given$(if ($rev) {", PTR -> $rev"} else {', no PTR record'})"
  } else {
    $a = (Resolve-DnsName -Name $ComputerName -Type A -ErrorAction Stop | Where-Object IPAddress | Select-Object -First 1).IPAddress
    "resolves to $a"
  }
} | Out-Null

# ---------- 3. WMI auth (DCOM) ----------
$script:cim = $null
$wmiOk = Step 'WMI-auth' {
  $opt = New-CimSessionOption -Protocol Dcom
  $script:cim = New-CimSession -ComputerName $ComputerName -Credential $Credential -SessionOption $opt -OperationTimeoutSec 30
  $os = Get-CimInstance -CimSession $script:cim -ClassName Win32_OperatingSystem
  "{0} ({1})" -f $os.CSName, $os.Caption
}
if (-not $wmiOk) { Diagnose 'WMI-auth' $results['WMI-auth'] }

# ---------- 4. target state (only possible once WMI answers) ----------
if ($wmiOk) {
  Step 'Target-state' {
    $notes = @()
    # services SAM depends on
    $svc = Get-CimInstance -CimSession $script:cim -ClassName Win32_Service -Filter "Name='Winmgmt' OR Name='WinRM' OR Name='RemoteRegistry' OR Name='LanmanServer'"
    foreach ($s in $svc) {
      $notes += "$($s.Name)=$($s.State)/$($s.StartMode)"
      switch ($s.Name) {
        'WinRM'          { if ($s.State -ne 'Running')  { Missing 'Target-state' 'WinRM service running + Automatic (SAM PowerShell Monitor)' "WinRM is $($s.State)/$($s.StartMode)" 'On target: Set-Service WinRM -StartupType Automatic ; Start-Service WinRM ; Enable-PSRemoting -Force' } }
        'RemoteRegistry' { if ($s.State -ne 'Running')  { Missing 'Target-state' 'Remote Registry running (SAM RPC performance counters, Windows Event Log monitors)' "RemoteRegistry is $($s.State)/$($s.StartMode)" 'On target: Set-Service RemoteRegistry -StartupType Automatic ; Start-Service RemoteRegistry' } }
        'LanmanServer'   { if ($s.State -ne 'Running')  { Missing 'Target-state' 'Server service running (C$ admin share, SMB)' "LanmanServer is $($s.State)" 'On target: Start-Service LanmanServer' } }
      }
    }
    # firewall rule groups (root\StandardCimv2 exists on 2012+/Win8+)
    try {
      $fw = Get-CimInstance -CimSession $script:cim -Namespace root/StandardCimv2 -ClassName MSFT_NetFirewallRule -ErrorAction Stop |
            Where-Object { $_.DisplayGroup -match 'Windows Management Instrumentation \(WMI\)|Windows Remote Management|File and Printer Sharing' -and $_.Direction -eq 1 }
      foreach ($g in ($fw | Group-Object DisplayGroup)) {
        $enabled = @($g.Group | Where-Object { $_.Enabled -eq 1 }).Count
        $notes += "fw[$($g.Name)]=$enabled/$($g.Count) enabled"
        if ($enabled -eq 0) { Missing 'Target-state' "Firewall inbound rule group '$($g.Name)' enabled" 'all rules in the group disabled' "On target: netsh advfirewall firewall set rule group=`"$($g.Name)`" new enable=yes" }
      }
    } catch { $notes += 'fw=unreadable' }
    # admin shares + UAC remote filter via registry over WMI
    try {
      $reg = Get-CimInstance -CimSession $script:cim -Namespace root/default -ClassName StdRegProv -ErrorAction Stop
      $hklm = [uint32]2147483650
      $ass = Invoke-CimMethod -InputObject $reg -MethodName GetDWORDValue -Arguments @{ hDefKey=$hklm; sSubKeyName='SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters'; sValueName='AutoShareServer' }
      if ($ass.ReturnValue -eq 0 -and $ass.uValue -eq 0) { Missing 'Target-state' 'Admin shares (C$) enabled for WMI-launched script read-back' 'AutoShareServer=0' 'On target: reg delete HKLM\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters /v AutoShareServer /f ; Restart-Service LanmanServer' ; $notes += 'C$=disabled' } else { $notes += 'C$=on' }
      $latfp = Invoke-CimMethod -InputObject $reg -MethodName GetDWORDValue -Arguments @{ hDefKey=$hklm; sSubKeyName='SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'; sValueName='LocalAccountTokenFilterPolicy' }
      $latfpOn = ($latfp.ReturnValue -eq 0 -and $latfp.uValue -eq 1); $notes += "LocalAccountTokenFilterPolicy=$(if ($latfpOn) {1} else {'0/unset'})"
      if ($userIsLocalAcct -and -not $latfpOn) { Missing 'Target-state' 'UAC remote token filter off for local admin accounts' "$user is a local account and LocalAccountTokenFilterPolicy is not 1" 'On target: reg add HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System /v LocalAccountTokenFilterPolicy /t REG_DWORD /d 1 /f   (or use a domain account)' }
    } catch { $notes += 'registry=unreadable' }
    # is the credential a local admin on the target?
    try {
      $u = $user.Split('\')[-1].Split('@')[0]
      $admins = Get-CimInstance -CimSession $script:cim -ClassName Win32_GroupUser -Filter "GroupComponent=`"Win32_Group.Domain='$((Get-CimInstance -CimSession $script:cim -ClassName Win32_ComputerSystem).Name)',Name='Administrators'`""
      $members = $admins | ForEach-Object { $_.PartComponent.Name }
      $isAdmin = $members -contains $u
      $notes += "localadmin=$(if ($isAdmin) {'yes'} else {'NOT DIRECT (' + ($members -join ',') + ')'})"
      if (-not $isAdmin) { Missing 'Target-state' 'Credential is a member of the target local Administrators group (direct membership, or via a domain group listed above)' "$u not a direct member; members are: $($members -join ', ')" "On target: Add-LocalGroupMember -Group Administrators -Member '$user'   (ignore if $u is admin through one of the listed domain groups)" }
    } catch { $notes += 'admins=unreadable' }
    $notes -join ' '
  } | Out-Null
}

# ---------- 5. WMI execute ----------
if (-not $SkipWmiExec -and $wmiOk) {
  $ok = Step 'WMI-exec' {
    $stamp  = Get-Date -Format 'yyyyMMddHHmmss'
    $remote = "C:\Windows\Temp\sam-wmi-test-$stamp.txt"
    $inner  = "`$env:COMPUTERNAME + ' ' + [Environment]::UserName + ' ' + (Get-Date -Format s) | Out-File -FilePath '$remote' -Encoding ascii"
    $enc    = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($inner))
    $cmd    = "powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand $enc"
    $ret    = Invoke-CimMethod -CimSession $script:cim -ClassName Win32_Process -MethodName Create -Arguments @{ CommandLine = $cmd }
    if ($ret.ReturnValue -ne 0) { throw "Win32_Process.Create ReturnValue $($ret.ReturnValue) (2=access denied, 3=insufficient privilege, 8=unknown failure, 9=path not found, 21=invalid parameter)" }
    $null = New-PSDrive -Name SamTest -PSProvider FileSystem -Root "\\$ComputerName\C$" -Credential $Credential -ErrorAction Stop
    try {
      $deadline = (Get-Date).AddSeconds(30); $content = $null
      while ((Get-Date) -lt $deadline) { if (Test-Path "SamTest:\Windows\Temp\sam-wmi-test-$stamp.txt") { Start-Sleep 1; $content = Get-Content "SamTest:\Windows\Temp\sam-wmi-test-$stamp.txt" -Raw; break }; Start-Sleep 1 }
      if (-not $content) { throw "process created (PID $($ret.ProcessId)) but no output file within 30s at \\$ComputerName\C$\Windows\Temp - script did not run or could not write" }
      Remove-Item "SamTest:\Windows\Temp\sam-wmi-test-$stamp.txt" -ErrorAction SilentlyContinue
      "PID $($ret.ProcessId) ran as: " + $content.Trim()
    } finally { Remove-PSDrive SamTest -ErrorAction SilentlyContinue }
  }
  if (-not $ok) { Diagnose 'WMI-exec' $results['WMI-exec'] }
}

# ---------- 6. WinRM execute ----------
$winrmOk = Step 'WinRM-exec' {
  $null = Test-WSMan -ComputerName $ComputerName -Credential $Credential -Authentication Default -ErrorAction Stop
  $out = Invoke-Command -ComputerName $ComputerName -Credential $Credential -ErrorAction Stop -ScriptBlock { "$env:COMPUTERNAME as $([Environment]::UserName), PS $($PSVersionTable.PSVersion), ExecutionPolicy $(Get-ExecutionPolicy)" }
  if ($out -match 'ExecutionPolicy (Restricted|AllSigned)') { Missing 'WinRM-exec' 'Execution policy allows scripts (SAM passes its script inline; Restricted/AllSigned can still block .ps1 files)' ($out -replace '.*ExecutionPolicy ','ExecutionPolicy ') 'On target: Set-ExecutionPolicy RemoteSigned -Scope LocalMachine -Force' }
  $out
}
if (-not $winrmOk) {
  Diagnose 'WinRM-exec' $results['WinRM-exec']
  if ($isIp) {
    $th = try { (Get-Item WSMan:\localhost\Client\TrustedHosts -ErrorAction Stop).Value } catch { '' }
    if ($th -notmatch [regex]::Escape($ComputerName) -and $th -ne '*') { Missing 'WinRM-exec' 'IP-based WinRM (NTLM) needs the target in TrustedHosts on THIS poller' "TrustedHosts here = '$th'" "On this poller: Set-Item WSMan:\localhost\Client\TrustedHosts -Value '$ComputerName' -Concatenate -Force   (better: use the FQDN)" }
  }
}

# ---------- 7. the SAM parse itself ----------
if ($LogPath -and $winrmOk) {
  Step 'SAM-parse' {
    $parse = {
      param($Path)
      if (-not (Test-Path -LiteralPath $Path)) { "Message.Status: file not found $Path"; "Statistic.Status: 1"; exit 3 }
      $lines = Get-Content -LiteralPath $Path -Tail 5000
      $crit  = @($lines | Where-Object { $_ -match '\b(CRITICAL|FATAL)\b' })
      $err   = @($lines | Where-Object { $_ -match '\bERROR\b' })
      $warn  = @($lines | Where-Object { $_ -match '\bWARN(ING)?\b' })
      "Message.Errors: $($err.Count) ERROR line(s) in last 5000 of $(Split-Path $Path -Leaf); last: $($err | Select-Object -Last 1)"
      "Statistic.Errors: $($err.Count)"
      "Message.Critical: $($crit.Count) CRITICAL/FATAL line(s); last: $($crit | Select-Object -Last 1)"
      "Statistic.Critical: $($crit.Count)"
      "Message.Warnings: $($warn.Count) WARN line(s)"
      "Statistic.Warnings: $($warn.Count)"
      if ($crit.Count -gt 0) { exit 3 } elseif ($err.Count -gt 0) { exit 2 } else { exit 0 }
    }
    $o = Invoke-Command -ComputerName $ComputerName -Credential $Credential -ScriptBlock $parse -ArgumentList $LogPath
    if ($o -match 'file not found') { Missing 'SAM-parse' "Log file exists on the target and $user can read it" "$LogPath not found or unreadable" 'Fix the path (it is a path ON THE TARGET) or grant the account read access' }
    ($o -join ' | ')
  } | Out-Null
} elseif ($LogPath) { Missing 'SAM-parse' 'WinRM must work first' 'skipped because WinRM-exec failed' 'Fix the WinRM findings above, then re-run' }

if ($script:cim) { Remove-CimSession $script:cim -ErrorAction SilentlyContinue }

# ---------- report ----------
Write-Host "`n=== RESULTS for $ComputerName as $user ==="
$results.GetEnumerator() | ForEach-Object { Write-Wrapped ("{0,-13} " -f $_.Key) $_.Value $(if ($_.Value -like 'PASS*') { 'Green' } else { 'Red' }) }
if ($findings.Count -eq 0) {
  Write-Host "`nNothing missing: this target meets every requirement SAM needs for WMI polling and remote PowerShell." -ForegroundColor Green
  exit 0
}
Write-Host "`n=== MISSING ($($findings.Count)) - what to fix, in order ===" -ForegroundColor Yellow
$i = 0
foreach ($f in $findings) {
  $i++
  Write-Wrapped ("{0,2}. [{1}] " -f $i, $f.Check) $f.Requirement Yellow
  Write-Wrapped '     missing : ' $f.Missing Gray
  Write-Wrapped '     fix     : ' $f.Fix Cyan
}
exit 1
