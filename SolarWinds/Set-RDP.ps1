<#
  Set-RDP.ps1 — enable RDP on the VM and verify it's reachable.
  Run as Administrator on the target box (the target server).
  Idempotent: safe to re-run.
#>
[CmdletBinding()]
param(
    [int]$Port = 3389
)

$ErrorActionPreference = 'Stop'

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-Admin)) {
    Write-Error "Run this as Administrator."
    exit 1
}

Write-Host "=== RDP setup on $env:COMPUTERNAME ===" -ForegroundColor Cyan

# 1. Enable RDP
$rdpKey = 'HKLM:\System\CurrentControlSet\Control\Terminal Server'
Set-ItemProperty -Path $rdpKey -Name 'fDenyTSConnections' -Value 0 -Type DWord
Write-Host "[1/5] RDP enabled (fDenyTSConnections=0)"

# 2. Allow UAC over RDP (full admin session)
Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' `
    -Name 'LocalAccountTokenFilterPolicy' -Value 1 -Type DWord -Force
Write-Host "[2/5] UAC over RDP enabled (LocalAccountTokenFilterPolicy=1)"

# 3. Firewall rules
$fwRules = @(
    @{ Name = "RDP-Port";  Display = "Remote Desktop ($Port)";  Port = $Port },
    @{ Name = "RDP-Port2"; Display = "Remote Desktop (RDP)";    Port = $Port }
)
foreach ($r in $fwRules) {
    $existing = Get-NetFirewallRule -DisplayName $r.Display -ErrorAction SilentlyContinue
    if ($existing) {
        Write-Host "[3/5] Firewall rule '$($r.Display)' already present"
    } else {
        New-NetFirewallRule -Name $r.Name -DisplayName $r.Display -Profile Any `
            -Direction Inbound -Protocol TCP -LocalPort $r.Port -Action Allow | Out-Null
        Write-Host "[3/5] Firewall rule '$($r.Display)' created (TCP $Port inbound)"
    }
}

# 4. Confirm the RDP service is running
$svc = Get-Service TermService -ErrorAction SilentlyContinue
if ($svc) {
    if ($svc.Status -ne 'Running') {
        Set-Service -Name TermService -StartupType Automatic -Force
        Start-Service TermService
    }
    Write-Host "[4/5] TermService is $($svc.Status)"
} else {
    Write-Host "[4/5] TermService not found (unexpected on Server)" -ForegroundColor Yellow
}

# 5. Verify the port is listening
$listen = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
if ($listen) {
    Write-Host "[5/5] Port $Port is LISTENING" -ForegroundColor Green
} else {
    Write-Host "[5/5] Port $Port not listening yet - retrying after 5s..." -ForegroundColor Yellow
    Start-Sleep -Seconds 5
    $listen = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
    if ($listen) {
        Write-Host "[5/5] Port $Port is LISTENING (after retry)" -ForegroundColor Green
    } else {
        Write-Host "[5/5] Port $Port STILL not listening - check Windows Firewall profile" -ForegroundColor Red
    }
}

# Report the IP
$ip = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -notlike '169.254*' -and $_.IPAddress -ne '127.0.0.1' } | Select-Object -First 1).IPAddress
Write-Host ""
Write-Host "=== DONE ===" -ForegroundColor Cyan
Write-Host "RDP target: ${ip}:$Port"
Write-Host "User: Administrator"
exit 0
