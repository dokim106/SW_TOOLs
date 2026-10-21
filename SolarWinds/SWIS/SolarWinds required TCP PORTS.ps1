# SolarWinds required ports and their descriptions
$portDescriptions = [ordered]@{
    22     = "SSH - Secure Shell (agent install on Linux/Unix)"
    25     = "SMTP - email alert actions"
    80     = "SRM NetApp Filer (direct polling) / HTTP"
    443    = "HTTPS - secure web/API traffic"
    135    = "RPC Endpoint Mapper / HA service mgmt"
    161    = "SNMP (UDP) - device polling"
    162    = "SNMP Traps (UDP) - trap ingestion"
    433    = "Reserved/typo guard (unused)"  # (kept harmless; delete if not needed)
    4369   = "RabbitMQ EPM (Erlang epmd) - clustering"
    1433   = "SQL Server default (DB)"
    25672  = "RabbitMQ inter-node - clustering"
    5392   = "SRM - Nimble"
    5671   = "RabbitMQ TLS / HA encrypted messaging"
    5988   = "SRM - SMI-S"
    5989   = "SRM - SMI-S"
    8088   = "SRM - NetApp DFM 7-mode"
    8488   = "SRM - NetApp DFM 7-mode"
    17732  = "SolarWinds Certificate Management Service (HTTPS/TCP)"
    17733  = "SolarWinds Job Engine v3 (internal only)"
    17774  = "SolarWinds SWIS API (HTTPS)"
    17775  = "SolarWinds Agent files/packages (legacy)"
    17777  = "SolarWinds Orion Module Engine (OME)"
    17778  = "SolarWinds Agent - command/control"
    17779  = "SolarWinds Platform Toolset integration (HTTP/HTTPS)"
    17790  = "SolarWinds Agent - server-initiated comms"
}

function Test-Udp {
    param(
        [Parameter(Mandatory)][string]$ComputerName,
        [Parameter(Mandatory)][int]$Port,
        [int]$TimeoutMs = 1500
    )
    $udp = New-Object System.Net.Sockets.UdpClient
    $remote = [System.Net.IPEndPoint]::new([System.Net.IPAddress]::Any,0)
    try {
        $udp.Client.ReceiveTimeout = $TimeoutMs
        $udp.Connect($ComputerName,$Port)
        [byte[]]$payload = 0..3
        [void]$udp.Send($payload,$payload.Length)
        try {
            [void]$udp.Receive([ref]$remote)   # if anything comes back, assume reachable
            $udp.Close()
            return @{ Open = $true;  Error = $null }
        } catch {
            $udp.Close()
            return @{ Open = $false; Error = "No response (UDP is non-ack)" }
        }
    } catch {
        try { $udp.Close() } catch {}
        return @{ Open = $false; Error = $_.Exception.Message }
    }
}

# Ask for targets (comma-separated)
$ips = Read-Host -Prompt "IP/Host targets to test (comma-separated)"
$ipList = $ips -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }

# Results
$openResults        = New-Object System.Collections.Generic.List[object]
$closedResults      = New-Object System.Collections.Generic.List[object]
$unreachableResults = New-Object System.Collections.Generic.List[object]

foreach ($ip in $ipList) {
    # Quick host reachability (ICMP); if blocked, we still try TCP/UDP
    $reachable = Test-Connection -ComputerName $ip -Count 1 -Quiet -ErrorAction SilentlyContinue

    if (-not $reachable) {
        # Don’t skip; just note it. Some networks block ICMP.
        $unreachableResults.Add("Host not pingable: $ip")
    }

    Write-Host "`n== Testing $ip ==" -ForegroundColor Cyan

    foreach ($port in $portDescriptions.Keys) {
        $desc = $portDescriptions[$port]
        $isUdp = ($port -eq 161 -or $port -eq 162)

        if ($isUdp) {
            $u = Test-Udp -ComputerName $ip -Port [int]$port
            $line = "IP: $ip, Port: $port ($desc)"
            if ($u.Open) {
                $openResults.Add($line + "  UDP: Responded")
                Write-Host $line -NoNewline; Write-Host "  UDP: Responded" -ForegroundColor Yellow
            } else {
                $closedResults.Add($line + "  UDP: No-Resp")
                Write-Host $line -NoNewline; Write-Host "  UDP: No-Resp" -ForegroundColor DarkYellow
                if ($u.Error) { Write-Host ("{0,30}  -> {1}" -f ' ', $u.Error) -ForegroundColor DarkGray }
            }
            continue
        }

        # TCP
        $ok = $false
        $err = $null
        try {
            $ok = Test-NetConnection -ComputerName $ip -Port ([int]$port) -InformationLevel Quiet -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
        } catch {
            $ok = $false
            $err = $_.Exception.Message
        }

        $line = "IP: $ip, Port: $port ($desc)"
        if ($ok) {
            $openResults.Add($line + "  TCP: Open")
            Write-Host $line -NoNewline; Write-Host "  TCP: Open" -ForegroundColor Green
        } else {
            $closedResults.Add($line + "  TCP: Closed")
            Write-Host $line -NoNewline; Write-Host "  TCP: Closed" -ForegroundColor Red
            if ($err) { Write-Host ("{0,30}  -> {1}" -f ' ', $err) -ForegroundColor DarkGray }
        }
    }
}

# Display grouped results
Write-Host "`nOpen Ports:"
$openResults   | ForEach-Object { Write-Host $_ -ForegroundColor Green }

Write-Host "`nClosed/No-Resp Ports:"
$closedResults | ForEach-Object { Write-Host $_ -ForegroundColor Red }

Write-Host "`nUnreachable (ping blocked or down):"
$unreachableResults | ForEach-Object { Write-Host $_ -ForegroundColor DarkYellow }

# Pause
Read-Host -Prompt "Press Enter to exit"
