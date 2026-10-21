# SAM remote PowerShell monitor — everything to set up, and WHERE

Goal: SolarWinds SAM runs a PowerShell script ON a monitored server (the "target") from the polling engine,
the script parses a log for ERROR / CRITICAL lines, and SAM shows the counts and alerts on them.

There are FOUR places where things get configured. Do them in this order. Each step says WHERE, WHAT, HOW, and CHECK.
If a CHECK fails, stop and fix that step before moving on.

---------------------------------------------------------------------------------------------------
## 0. The account  (WHERE: Active Directory — whoever manages accounts)
---------------------------------------------------------------------------------------------------
0.1  WHAT  One domain service account for SolarWinds, e.g. `DOMAIN\svc_solarwinds`.
     HOW   Create it in AD. Password set to not expire, or put it on a rotation plan that also updates Orion.
     CHECK You can log on with it once (or `runas /user:DOMAIN\svc_solarwinds cmd`).

0.2  WHAT  That account must be a LOCAL ADMINISTRATOR on every target server.
     HOW   Either a GPO (Restricted Groups / Group Policy Preferences > Local Users and Groups) that adds it to
           Administrators on the servers, or by hand on each server (see 1.1).
     CHECK On a target: `net localgroup Administrators` lists the account or a domain group it is in.

---------------------------------------------------------------------------------------------------
## 1. On EVERY target server you want to monitor  (WHERE: log on to that server as an admin)
---------------------------------------------------------------------------------------------------
Open PowerShell "Run as administrator" and run these.

1.1  WHAT  Service account is a local admin.
     HOW   `Add-LocalGroupMember -Group Administrators -Member 'DOMAIN\svc_solarwinds'`
     CHECK `Get-LocalGroupMember Administrators`

1.2  WHAT  WinRM turned on (this is what SAM's "Remote Host" PowerShell monitor uses).
     HOW   `Enable-PSRemoting -Force`
           (starts the WinRM service, sets it to Automatic, creates the HTTP listener on port 5985, opens the firewall rule)
     CHECK `Test-WSMan localhost`  → prints product/version, no red text
           `winrm enumerate winrm/config/listener`  → shows Transport = HTTP, Port = 5985

1.3  WHAT  Windows Firewall inbound rule groups enabled.
     HOW   `netsh advfirewall firewall set rule group="Windows Remote Management" new enable=yes`
           `netsh advfirewall firewall set rule group="Windows Management Instrumentation (WMI)" new enable=yes`
           `netsh advfirewall firewall set rule group="File and Printer Sharing" new enable=yes`
     CHECK `Get-NetFirewallRule -DisplayGroup 'Windows Remote Management' | Select DisplayName,Enabled,Direction`

1.4  WHAT  Services running and set to Automatic.
     HOW   `Set-Service WinRM -StartupType Automatic; Start-Service WinRM`
           `Set-Service Winmgmt -StartupType Automatic; Start-Service Winmgmt`
           `Set-Service RemoteRegistry -StartupType Automatic; Start-Service RemoteRegistry`   (needed for SAM perf counters / event log monitors)
     CHECK `Get-Service WinRM,Winmgmt,RemoteRegistry,LanmanServer`  → all Running

1.5  WHAT  Execution policy allows scripts.
     HOW   `Set-ExecutionPolicy RemoteSigned -Scope LocalMachine -Force`
     CHECK `Get-ExecutionPolicy -List`  → LocalMachine = RemoteSigned, and MachinePolicy / UserPolicy = Undefined.
           If MachinePolicy or UserPolicy is NOT Undefined, a Group Policy owns it — talk to the GPO admin, you cannot change it here.

1.6  WHAT  (ONLY if the service account is a LOCAL account, not a domain account) turn off the UAC remote filter.
     HOW   `reg add HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System /v LocalAccountTokenFilterPolicy /t REG_DWORD /d 1 /f`
     CHECK Domain account → skip this step entirely.

1.7  WHAT  The log file the script reads.
     HOW   Know the exact full path, e.g. `C:\ProgramData\SolarWinds\Logs\Orion\Core.BusinessLayer.log`.
           The service account needs READ on that file (right-click > Properties > Security).
     CHECK `Get-Content '<path>' -Tail 3` works when run as the service account.

1.8  WHAT  PowerShell version 3.0 or newer.
     CHECK `$PSVersionTable.PSVersion`  (Windows 2012 R2 and newer ship 4.0+/5.1 — fine)

1.9  WHAT  (Optional, older Windows 2008 R2 / 2012 only) raise WinRM shell memory so scripts do not die at 150 MB.
     HOW   `winrm set winrm/config/winrs '@{MaxMemoryPerShellMB="1024"}'`

Network firewalls BETWEEN the poller and the target (WHERE: the network/firewall team):
     Allow from the polling engine IP to the target: TCP 135, TCP 445, TCP 5985 (5986 if HTTPS), and TCP 49152-65535 (dynamic RPC for WMI).

---------------------------------------------------------------------------------------------------
## 2. On the POLLING ENGINE that owns the node  (WHERE: log on to the Orion main poller, or the Additional Polling Engine assigned to that node)
---------------------------------------------------------------------------------------------------
2.1  WHAT  The target name resolves.
     CHECK `nslookup <target FQDN>`  → returns the right IP.  Use the FQDN in Orion, not the IP (Kerberos needs a name).

2.2  WHAT  (ONLY if you must use an IP address, or the target is not domain-joined) trust the target for WinRM.
     HOW   `Set-Item WSMan:\localhost\Client\TrustedHosts -Value '<target IP or name>' -Concatenate -Force`
     CHECK `Get-Item WSMan:\localhost\Client\TrustedHosts`

2.3  WHAT  Prove the whole path works BEFORE touching Orion.
     HOW   Copy `Test-SamRemoteExec.ps1` to the poller and run, as the service account credential:
           `$cred = Get-Credential DOMAIN\svc_solarwinds`
           `.\Test-SamRemoteExec.ps1 -ComputerName <target FQDN> -Credential $cred -LogPath '<log path on target>'`
     CHECK Every line says PASS and the last line says "Nothing missing". If not, it prints a numbered MISSING list
           with the exact command to run and WHERE (On target / On this poller). Fix, re-run, repeat until clean.

---------------------------------------------------------------------------------------------------
## 3. In the ORION WEB CONSOLE  (WHERE: browser, logged in as an Orion admin)
---------------------------------------------------------------------------------------------------
3.1  WHAT  Store the credential.
     HOW   Settings > All Settings > Manage Windows Credentials > Add New Credential
           Name: SolarWinds Service Account, User: DOMAIN\svc_solarwinds, Password.
     CHECK It appears in the list.

3.2  WHAT  The target node exists with that credential.
     HOW   Settings > Manage Nodes > Add Node (or Edit Node)
           Polling method: Windows Servers: WMI (or Agent if you deploy agents). Hostname: the FQDN. Credential: the one from 3.1.
           Click TEST next to the credential.
     CHECK Test says "succeeded". Node polls (status Up, CPU/memory populate).

3.3  WHAT  The application template with the PowerShell component.
     HOW   Settings > All Settings > SAM Settings > Manage Templates > Create New Template (or edit yours)
           Add Component Monitor > Windows PowerShell Monitor. Set:
             Execution Mode           = Remote Host          (runs the script ON the target over WinRM)
             Credential for Monitoring= Inherit from node    (or pick 3.1)
             Script Body              = paste the parse script (the block from Test-SamRemoteExec.ps1 "SAM-parse", or your own)
             Script Arguments         = the log path on the target
             Timeout                  = longer than the script takes (60 s is plenty for a tail of 5000 lines)
             Statistic thresholds     = Warning when Statistic.Errors > 0, Critical when Statistic.Critical > 0
     RULE  The script MUST print lines exactly like `Message.Errors: text` and `Statistic.Errors: 5` (up to 10 pairs)
           and exit with 0 = Up, 1 = Down, 2 = Warning, 3 = Critical. Anything else and SAM shows Unknown.
     CHECK In the template editor click "Test" against the node → component shows Up/Warning/Critical with your Message text, not Unknown.

3.4  WHAT  Assign the template to the node.
     HOW   SAM Settings > Manage Assignments > Assign Application Monitors > pick template + node + credential.
     CHECK Node details page shows the application; after one poll cycle the component has data.

3.5  WHAT  An alert so someone actually hears about it.
     HOW   Alerts & Activity > Alerts > Manage Alerts > Add New Alert
           Trigger: Component status is Critical (or Warning) for that template. Message: include ${N=SwisEntity;M=StatusDescription} and the component Message text.
     CHECK Force a Critical (e.g. temporarily point the argument at a file with CRITICAL in it) and confirm the alert fires.

---------------------------------------------------------------------------------------------------
## 4. Order of operations (the short version)
---------------------------------------------------------------------------------------------------
account exists → account is local admin on target → Enable-PSRemoting + firewall + services on target → execution policy RemoteSigned →
run Test-SamRemoteExec.ps1 from the poller until "Nothing missing" → credential in Orion → node credential Test passes →
template component Test passes → assign → alert.

If something worked yesterday and not today: re-run Test-SamRemoteExec.ps1 first. It tells you which layer broke.
