<#
.SYNOPSIS
  Make /customdash/... reachable on this SolarWinds web server (fixes the 404 in the the client Dependency Map widget).

.DESCRIPTION
  Run ON THE SOLARWINDS WEB SERVER that serves the console URL, in an ELEVATED PowerShell.
  The page files are already in C:\CustomDash\cne-map; what is missing is the IIS virtual directory that maps
  /customdash on the console site to C:\CustomDash. This script (step 3 of Deploy-Relmap.ps1, same discovery):
    1  checks the page is on disk
    2  writes C:\CustomDash\web.config if absent (every file under the root goes behind the console login)
    3  finds the IIS application that serves \Orion (discovered, never assumed) and adds /customdash -> C:\CustomDash
    4  requests the page anonymously: a 302 to the login means it is served and protected; 404 means still missing
  Nothing else on the server is changed. Undo: Remove-WebVirtualDirectory with the site and name it prints.

.EXAMPLE
  .\Fix-CustomDash-VDir.ps1 -DryRun
.EXAMPLE
  .\Fix-CustomDash-VDir.ps1 -ConsoleHost <console host name>
  If localhost answers 302 but the console name answers 404, a different web server (additional web server or
  load balancer member) serves that name: copy C:\CustomDash there and run this script on it too.
#>
[CmdletBinding()]
param(
  [string] $Root = 'C:\CustomDash',
  [string] $VDir = 'customdash',
  [string] $Name = 'cne-map',
  [string] $ConsoleHost,      # the console's public host name - also checks the page through the console's public name
  [switch] $DryRun
)
$ErrorActionPreference = 'Stop'

function Step ($n, $m) { Write-Host "" ; Write-Host ("[{0}] {1}" -f $n, $m) -ForegroundColor Cyan }
function Good ($m) { Write-Host ("    ok    " + $m) -ForegroundColor Green }
function Warn ($m) { Write-Host ("    note  " + $m) -ForegroundColor Yellow }
function Die  ($m) { Write-Host ("    FAIL  " + $m) -ForegroundColor Red ; exit 1 }

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
          ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
  Die 'run this in an ELEVATED PowerShell. Creating an IIS virtual directory needs Windows administrator.'
}

# ---------------------------------------------------------------- 1. the page is on disk
Step 1 "page files in $Root\$Name"
$page = Join-Path (Join-Path $Root $Name) 'index.html'
if (-not (Test-Path $page)) { Die "$page is not there. Copy the cne-map folder into $Root first." }
if (-not (Test-Path (Join-Path (Join-Path $Root $Name) 'web.config'))) { Die "$Root\$Name\web.config is missing. It carries the page's login rule and script policy; copy it with the page." }
Good 'index.html and web.config present'

# ---------------------------------------------------------------- 2. the root web.config
Step 2 "root $Root\web.config"
$rootCfg = Join-Path $Root 'web.config'
if (Test-Path $rootCfg) { Good 'already there, left alone' }
elseif ($DryRun) { Good 'would write it (login required for every file under the root)' }
else {
  @'
<?xml version="1.0" encoding="utf-8"?>
<!-- Every file under this root goes behind the SolarWinds Platform login. Static files normally skip ASP.NET,
     so they are mapped to the managed System.Web.StaticFileHandler, which runs FormsAuthentication and
     UrlAuthorization. Handlers ARE allowed below application level; runAllManagedModulesForAllRequests is not. -->
<configuration>
  <system.webServer>
    <handlers>
      <remove name="PageRoot-StaticViaAspNet" />
      <add name="PageRoot-StaticViaAspNet" path="*" verb="GET,HEAD" type="System.Web.StaticFileHandler" resourceType="File" preCondition="integratedMode" />
    </handlers>
    <directoryBrowse enabled="false" />
  </system.webServer>
  <system.web>
    <authorization>
      <deny users="?" />
    </authorization>
  </system.web>
</configuration>
'@ | Set-Content -Path $rootCfg -Encoding UTF8
  Good "wrote $rootCfg"
}

# ---------------------------------------------------------------- 3. the virtual directory, discovered
Step 3 "virtual directory /$VDir"
Import-Module WebAdministration -ErrorAction Stop
# The URL is /customdash/..., so the mapping belongs at the ROOT of the site that serves the console - the site
# whose folder holds \Orion (discovered, never assumed: the site name has differed between versions).
$site = Get-Website | Where-Object {
  $_.PhysicalPath -and (Test-Path (Join-Path ([Environment]::ExpandEnvironmentVariables($_.PhysicalPath)) 'Orion'))
} | Select-Object -First 1
if (-not $site) { Die 'no IIS site here serves an \Orion folder. Run this on the SolarWinds WEB server.' }
Good "console site: $($site.Name)"
$existing = Get-WebVirtualDirectory -Site $site.Name -Name $VDir -ErrorAction SilentlyContinue
if ($existing) {
  if ($existing.PhysicalPath -ne $Root) { Die "/$VDir already exists but points at $($existing.PhysicalPath), not $Root. Move the page there, or fix the mapping by hand." }
  Good "/$VDir already maps to $Root"
} elseif ($DryRun) {
  Good "would add /$VDir -> $Root"
} else {
  New-WebVirtualDirectory -Site $site.Name -Name $VDir -PhysicalPath $Root | Out-Null
  Good "added /$VDir -> $Root   (undo: Remove-WebVirtualDirectory -Site '$($site.Name)' -Name '$VDir')"
}

# ---------------------------------------------------------------- 4. is it served, and behind the login?
Step 4 "requesting /$VDir/$Name/index.html anonymously"
[Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
# HttpWebRequest with redirects off: on Windows PowerShell 5.1, Invoke-WebRequest -MaximumRedirection 0 throws on
# the 302 and drops the response, so the login redirect would read as "no answer". Adding a virtual directory
# makes IIS reload the console site, and its first answer can take a minute - hence the retries.
function Get-Status ($url) {
  for ($try = 1; $try -le 3; $try++) {
    Write-Host ("    ...   {0} (try {1}/3, up to 20s; Ctrl+C is safe - the fix is already in)" -f $url, $try)
    $req = [Net.HttpWebRequest]::Create($url)
    $req.AllowAutoRedirect = $false
    $req.Timeout = 20000
    $req.ReadWriteTimeout = 20000
    try {
      $resp = $req.GetResponse() ; $c = [int]$resp.StatusCode ; $resp.Close() ; return $c
    } catch {
      $ex = $_.Exception
      while ($ex -and -not ($ex -is [Net.WebException])) { $ex = $ex.InnerException }
      if ($ex -and $ex.Response) { $c = [int]$ex.Response.StatusCode ; $ex.Response.Close() ; return $c }
    }
    Start-Sleep -Seconds 5
  }
  return 0
}
function Report ($label, $code) {
  if ($code -ge 300 -and $code -lt 400) { Good "$label -> $code to the login page: served and protected" }
  elseif ($code -eq 200) { Warn "$label -> 200 WITHOUT SIGNING IN: readable anonymously. Check both web.config files carry <deny users=`"?`"/>." }
  elseif ($code -eq 404) { Warn "$label -> 404: nothing maps /$VDir there" }
  else { Warn "$label -> no answer ($code)" }
}
$path = "/$VDir/$Name/index.html"
$code = Get-Status "https://localhost$path"
if (-not $code) { $code = Get-Status "http://localhost$path" }
Report 'localhost' $code
if ($ConsoleHost) { Report $ConsoleHost (Get-Status "https://$ConsoleHost$path") }
if ($code -ge 300 -and $code -lt 400) { Good 'Reload the dashboard.' }
elseif ($code -eq 404 -and -not $DryRun) { Die '404 still on this server.' }
