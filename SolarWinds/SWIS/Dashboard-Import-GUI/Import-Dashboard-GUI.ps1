<#
.SYNOPSIS
  Import a SolarWinds Modern Dashboard from an exported JSON file, from a small window.

.DESCRIPTION
  Windows PowerShell 5.1. Pick the exported dashboard JSON with the file browser and the window shows:
    - the dashboard as ONE LINE of JSON (Copy / Save) - what SWQL Studio's Import verb takes
    - where everything goes: the dashboard into SolarWinds, and for an embedded page widget
      (/customdash/<name>/...) the folder its page files must be in on the SolarWinds web server
  Then enter the server, username and password and press Import. The import calls the SWIS REST API
  (port 17774, verb Orion.Dashboards.Instances.Import). The password is only held in the window while it
  is open; nothing is written to disk except the 1-line JSON when you press Save.

  "Check page" asks the web server for the widget's page without signing in: 302 (sent to the login page)
  means the page is there and protected; 404 means the page files or the /customdash mapping are missing
  (Fix-CustomDash-VDir.ps1 in this folder adds the mapping).

.PARAMETER SelfTest
  Path of a dashboard JSON: run every step without showing the window and print the results (for testing).

.PARAMETER SelfTestServer
  Server to use with -SelfTest.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\Import-Dashboard-GUI.ps1
#>
[CmdletBinding()]
param(
  [string] $SelfTest,
  [string] $SelfTestServer = 'localhost'
)
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Web.Extensions

$SwisPort = 17774
$PageRoot = 'C:\CustomDash'
$PageVDir = 'customdash'

# Strips whitespace OUTSIDE strings only, so every value stays exactly as exported. Compiled once: a
# PowerShell character loop takes minutes on the 20+ MB dashboards some exports produce.
Add-Type -TypeDefinition @'
public static class DashboardJson {
  public static string OneLine(string s) {
    var sb = new System.Text.StringBuilder(s.Length);
    bool inString = false, escaped = false;
    foreach (char c in s) {
      if (inString) {
        sb.Append(c);
        if (escaped) escaped = false;
        else if (c == '\\') escaped = true;
        else if (c == '"') inString = false;
      }
      else if (c == '"') { inString = true; sb.Append(c); }
      else if (c != ' ' && c != '\t' && c != '\r' && c != '\n' && c != '\uFEFF') sb.Append(c);
    }
    return sb.ToString();
  }
}
'@

function New-Serializer {
  # ConvertFrom-Json in 5.1 stops at 2 MB of text; this one is told not to
  $s = New-Object System.Web.Script.Serialization.JavaScriptSerializer
  $s.MaxJsonLength = [int]::MaxValue
  $s.RecursionLimit = 1000
  return $s
}

function Read-Dashboard {
  param([string] $Path)

  $text = [IO.File]::ReadAllText($Path)
  $oneLine = [DashboardJson]::OneLine($text)
  $ser = New-Serializer
  $doc = $ser.DeserializeObject($oneLine)
  if (-not ($doc -is [Collections.IDictionary]) -or -not $doc.ContainsKey('dashboards') -or -not $doc.ContainsKey('widgets')) {
    throw 'this is not a Modern Dashboard export (no "dashboards" / "widgets" at the top)'
  }
  # proof the 1-line text is the same document as the file
  if ($ser.Serialize($ser.DeserializeObject($text)) -ne $ser.Serialize($doc)) { throw '1-line JSON differs from the file' }

  $dashboards = @($doc['dashboards'] | ForEach-Object { [pscustomobject]@{ Name = $_['name']; Key = $_['unique_key'] } })
  $pages = @()
  foreach ($w in @($doc['widgets'])) {
    if ($w['type'] -ne 'embedded-content') { continue }
    $url = ''
    try { $url = [string]$w['configuration']['mainContent']['properties']['customEmbeddedContent'] } catch { }
    if (-not $url) { continue }
    $folder = ''
    if ($url -match ('^/' + [regex]::Escape($PageVDir) + '/(.+)/[^/]*$')) {
      $folder = Join-Path $PageRoot ($Matches[1] -replace '/', '\')
    }
    $pages += [pscustomobject]@{ Widget = $w['name']; Url = $url; Folder = $folder }
  }

  return [pscustomobject]@{
    Path = $Path; OneLine = $oneLine; Bytes = $oneLine.Length
    Dashboards = $dashboards; WidgetCount = @($doc['widgets']).Count; Pages = $pages
  }
}

function Format-Destinations {
  param($D, [string] $Server)

  $host_ = if ($Server) { $Server } else { '<server>' }
  $out = New-Object System.Collections.Generic.List[string]
  foreach ($b in $D.Dashboards) {
    $out.Add(("DASHBOARD  '{0}'   (key {1})" -f $b.Name, $b.Key))
    $out.Add('  -> goes INTO SolarWinds: SWIS verb Orion.Dashboards.Instances.Import (Import button, or paste the')
    $out.Add('     1-line JSON into SWQL Studio: Orion.Dashboards.Instances > Import > Invoke)')
    $out.Add(("  -> then open it in the console: My Dashboards > {0}" -f $b.Name))
    $out.Add('  -> same key already there: updated in place; if it was edited in the console the import fails,')
    $out.Add('     so delete it in the console first')
  }
  $out.Add(("{0} widget(s)" -f $D.WidgetCount))
  foreach ($p in $D.Pages) {
    $out.Add('')
    $out.Add(("PAGE WIDGET  '{0}'  shows  {1}" -f $p.Widget, $p.Url))
    if ($p.Folder) {
      $out.Add(("  -> page files go on the SolarWinds WEB server in   {0}\" -f $p.Folder))
      $out.Add(("  -> IIS on that server must map /{0} -> {1}   (Fix-CustomDash-VDir.ps1 adds it)" -f $PageVDir, $PageRoot))
      $out.Add(("  -> served at   https://{0}{1}" -f $host_, $p.Url))
    } else {
      $out.Add('  -> not under /customdash: the page must already be served at that address')
    }
  }
  return ($out -join "`r`n")
}

function Set-Tls {
  param([bool] $TrustCert)
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
  if ($TrustCert) { [Net.ServicePointManager]::ServerCertificateValidationCallback = { $true } }
  else { [Net.ServicePointManager]::ServerCertificateValidationCallback = $null }
}

function Get-HttpResult {
  # HttpWebRequest: Invoke-WebRequest in 5.1 throws on a 302 or 4xx and drops the status and body
  param([Net.HttpWebRequest] $Req, [byte[]] $Body)
  try {
    if ($Body) {
      $Req.ContentLength = $Body.Length
      $s = $Req.GetRequestStream() ; $s.Write($Body, 0, $Body.Length) ; $s.Close()
    }
    $resp = $Req.GetResponse()
  } catch {
    $ex = $_.Exception
    while ($ex -and -not ($ex -is [Net.WebException])) { $ex = $ex.InnerException }
    if (-not $ex -or -not $ex.Response) { return [pscustomobject]@{ Code = 0; Text = $_.Exception.Message } }
    $resp = $ex.Response
  }
  $reader = New-Object IO.StreamReader($resp.GetResponseStream())
  $text = $reader.ReadToEnd() ; $reader.Close()
  $code = [int]$resp.StatusCode ; $resp.Close()
  return [pscustomobject]@{ Code = $code; Text = $text }
}

function Invoke-DashboardImport {
  param([string] $Server, [string] $User, [string] $Password, [string] $OneLine, [bool] $TrustCert)

  Set-Tls $TrustCert
  $uri = 'https://{0}:{1}/SolarWinds/InformationService/v3/Json/Invoke/Orion.Dashboards.Instances/Import' -f $Server, $SwisPort
  $req = [Net.HttpWebRequest]::Create($uri)
  $req.Method = 'POST'
  $req.ContentType = 'application/json'
  $req.Timeout = 600000
  $req.ReadWriteTimeout = 600000
  $req.Headers['Authorization'] = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($User + ':' + $Password))
  # the verb takes one argument: the whole dashboard as a JSON string, so the body is ["<1-line json>"]
  $body = [Text.Encoding]::UTF8.GetBytes((New-Serializer).Serialize(@($OneLine)))
  return Get-HttpResult $req $body
}

function Test-Page {
  param([string] $Server, [string] $Url, [bool] $TrustCert)

  Set-Tls $TrustCert
  $req = [Net.HttpWebRequest]::Create('https://' + $Server + $Url)
  $req.AllowAutoRedirect = $false
  $req.Timeout = 30000
  $r = Get-HttpResult $req $null
  $meaning = switch ($r.Code) {
    { $_ -ge 300 -and $_ -lt 400 } { 'sent to the login page: the page is there and protected - OK' ; break }
    200 { 'served WITHOUT signing in: the page is there but not protected - check its web.config' ; break }
    404 { 'NOT FOUND: copy the page files to the folder above and make sure /customdash is mapped (Fix-CustomDash-VDir.ps1)' ; break }
    0   { 'no answer: ' + $r.Text ; break }
    default { 'unexpected answer' }
  }
  return ('{0}  ->  {1}  {2}' -f $Url, $r.Code, $meaning)
}

function Describe-ImportResult {
  param($R)
  switch ($R.Code) {
    200 { return 'IMPORTED. Open it in the console under My Dashboards. Server said: ' + $R.Text }
    { $_ -eq 401 -or $_ -eq 403 } { return ('REFUSED ({0}): wrong username or password, or the account may not use SWIS / import dashboards.' -f $R.Code) }
    0   { return ('NO ANSWER from port {0}: {1}' -f $SwisPort, $R.Text) }
    default {
      $t = $R.Text ; if ($t.Length -gt 600) { $t = $t.Substring(0, 600) + '...' }
      return ('FAILED ({0}): {1}' -f $R.Code, $t)
    }
  }
}

function Write-Log {
  param([string] $Message)
  $script:ui.Log.AppendText(('[{0:HH:mm:ss}] {1}' -f (Get-Date), $Message) + "`r`n")
}

function Update-Where {
  if ($script:ui.Doc) { $script:ui.Where.Text = Format-Destinations $script:ui.Doc $script:ui.Server.Text.Trim() }
}

# ================================================================== window
function New-ImportForm {
  $f = New-Object Windows.Forms.Form
  $f.Text = 'SolarWinds dashboard import'
  $f.Size = New-Object Drawing.Size(980, 800)
  $f.StartPosition = 'CenterScreen'
  $f.Font = New-Object Drawing.Font('Segoe UI', 9)
  # handlers run after this function returns, so everything they use lives in $script:ui
  $script:ui = @{ Form = $f; Doc = $null }
  $ui = $script:ui

  function Add-Label ($text, $x, $y, $w) {
    $l = New-Object Windows.Forms.Label
    $l.Text = $text ; $l.Location = New-Object Drawing.Point($x, $y) ; $l.Size = New-Object Drawing.Size($w, 20)
    $f.Controls.Add($l)
  }
  function Add-Box ($x, $y, $w, $h, $multi) {
    $t = New-Object Windows.Forms.TextBox
    $t.Location = New-Object Drawing.Point($x, $y) ; $t.Size = New-Object Drawing.Size($w, $h)
    if ($multi) { $t.Multiline = $true ; $t.ScrollBars = 'Both' ; $t.ReadOnly = $true ; $t.WordWrap = $false
                  $t.Font = New-Object Drawing.Font('Consolas', 9) ; $t.Anchor = 'Top,Left,Right' }
    $f.Controls.Add($t) ; return $t
  }
  function Add-Button ($text, $x, $y, $w) {
    $b = New-Object Windows.Forms.Button
    $b.Text = $text ; $b.Location = New-Object Drawing.Point($x, $y) ; $b.Size = New-Object Drawing.Size($w, 28)
    $f.Controls.Add($b) ; return $b
  }

  Add-Label 'SolarWinds server' 12 16 130
  $ui.Server = Add-Box 150 13 250 22 $false
  Add-Label 'Username' 420 16 70
  $ui.User = Add-Box 495 13 170 22 $false
  Add-Label 'Password' 680 16 65
  $ui.Pass = Add-Box 750 13 200 22 $false
  $ui.Pass.UseSystemPasswordChar = $true
  $ui.Trust = New-Object Windows.Forms.CheckBox
  $ui.Trust.Text = 'Trust the server''s own (self-signed) certificate - SWIS uses one by default'
  $ui.Trust.Location = New-Object Drawing.Point(150, 40) ; $ui.Trust.Size = New-Object Drawing.Size(600, 22)
  $ui.Trust.Checked = $true
  $f.Controls.Add($ui.Trust)

  Add-Label 'Dashboard file' 12 76 130
  $ui.File = Add-Box 150 73 690 22 $false
  $ui.File.ReadOnly = $true
  $ui.Browse = Add-Button 'Browse...' 850 70 100

  Add-Label 'Where it goes' 12 108 300
  $ui.Where = Add-Box 12 128 938 210 $true
  Add-Label '1-line JSON  (SWQL Studio: Orion.Dashboards.Instances > Import > Invoke, paste as the argument)' 12 346 700
  $ui.Json = Add-Box 12 366 938 120 $true

  $ui.Copy = Add-Button 'Copy 1-line JSON' 12 494 150
  $ui.Save = Add-Button 'Save 1-line JSON...' 170 494 150
  $ui.Check = Add-Button 'Check page' 328 494 120
  $ui.Import = Add-Button 'Import into SolarWinds' 760 494 190
  $ui.Import.Font = New-Object Drawing.Font('Segoe UI', 9, [Drawing.FontStyle]::Bold)
  foreach ($b in $ui.Copy, $ui.Save, $ui.Check, $ui.Import) { $b.Enabled = $false }

  Add-Label 'Log' 12 532 100
  $ui.Log = Add-Box 12 552 938 195 $true
  $ui.Log.Anchor = 'Top,Bottom,Left,Right'

  $ui.Browse.Add_Click({
    $dlg = New-Object Windows.Forms.OpenFileDialog
    $dlg.Title = 'Choose the exported dashboard JSON'
    $dlg.Filter = 'Dashboard JSON (*.json)|*.json|All files (*.*)|*.*'
    if ($dlg.ShowDialog($script:ui.Form) -ne 'OK') { return }
    try {
      $script:ui.Form.Cursor = 'WaitCursor'
      $script:ui.Doc = Read-Dashboard $dlg.FileName
      $script:ui.File.Text = $dlg.FileName
      Update-Where
      $show = $script:ui.Doc.OneLine
      if ($show.Length -gt 200000) { $show = $show.Substring(0, 200000) + '   ... (shortened on screen; Copy and Save use all of it)' }
      $script:ui.Json.Text = $show
      foreach ($b in $script:ui.Copy, $script:ui.Save, $script:ui.Import) { $b.Enabled = $true }
      $script:ui.Check.Enabled = ($script:ui.Doc.Pages.Count -gt 0)
      Write-Log ("loaded {0}: {1} dashboard(s), {2} widget(s), 1-line JSON {3:N0} characters" -f (Split-Path $dlg.FileName -Leaf), $script:ui.Doc.Dashboards.Count, $script:ui.Doc.WidgetCount, $script:ui.Doc.Bytes)
    } catch {
      $script:ui.Doc = $null
      foreach ($b in $script:ui.Copy, $script:ui.Save, $script:ui.Check, $script:ui.Import) { $b.Enabled = $false }
      Write-Log ('cannot use that file: ' + $_.Exception.Message)
    } finally { $script:ui.Form.Cursor = 'Default' }
  })

  $ui.Server.Add_TextChanged({ Update-Where })

  $ui.Copy.Add_Click({
    [Windows.Forms.Clipboard]::SetText($script:ui.Doc.OneLine)
    Write-Log ('1-line JSON copied to the clipboard ({0:N0} characters)' -f $script:ui.Doc.Bytes)
  })

  $ui.Save.Add_Click({
    $dlg = New-Object Windows.Forms.SaveFileDialog
    $dlg.Filter = 'JSON (*.json)|*.json'
    $dlg.FileName = [IO.Path]::GetFileNameWithoutExtension($script:ui.Doc.Path) + '.oneline.json'
    $dlg.InitialDirectory = Split-Path $script:ui.Doc.Path
    if ($dlg.ShowDialog($script:ui.Form) -ne 'OK') { return }
    [IO.File]::WriteAllText($dlg.FileName, $script:ui.Doc.OneLine, (New-Object Text.UTF8Encoding($false)))
    Write-Log ('saved ' + $dlg.FileName)
  })

  $ui.Check.Add_Click({
    $server = $script:ui.Server.Text.Trim()
    if (-not $server) { Write-Log 'enter the SolarWinds server first' ; return }
    $script:ui.Form.Cursor = 'WaitCursor'
    try { foreach ($p in $script:ui.Doc.Pages) { Write-Log (Test-Page $server $p.Url $script:ui.Trust.Checked) } }
    finally { $script:ui.Form.Cursor = 'Default' }
  })

  $ui.Import.Add_Click({
    $server = $script:ui.Server.Text.Trim() ; $user = $script:ui.User.Text.Trim()
    if (-not $server -or -not $user -or -not $script:ui.Pass.Text) { Write-Log 'enter the server, username and password first' ; return }
    $names = ($script:ui.Doc.Dashboards | ForEach-Object { $_.Name }) -join ', '
    $ok = [Windows.Forms.MessageBox]::Show($script:ui.Form, ("Import '{0}' into {1}?" -f $names, $server), 'Import dashboard', 'OKCancel', 'Question')
    if ($ok -ne 'OK') { return }
    $script:ui.Form.Cursor = 'WaitCursor'
    try {
      Write-Log ("importing '{0}' into {1} as {2} ..." -f $names, $server, $user)
      $r = Invoke-DashboardImport $server $user $script:ui.Pass.Text $script:ui.Doc.OneLine $script:ui.Trust.Checked
      Write-Log (Describe-ImportResult $r)
    } finally { $script:ui.Form.Cursor = 'Default' }
  })

  return $ui
}

# ================================================================== run
if ($SelfTest) {
  $ui = New-ImportForm
  "window built: {0} controls" -f $ui.Form.Controls.Count
  $d = Read-Dashboard $SelfTest
  # the same script-scope path the buttons use after the window is up
  $script:ui.Doc = $d ; $script:ui.Server.Text = $SelfTestServer ; Update-Where ; Write-Log 'selftest'
  "window fills in: where-it-goes {0} lines, log {1} line(s)" -f $script:ui.Where.Lines.Count, ($script:ui.Log.Lines | Where-Object { $_ }).Count
  $ui.Form.Dispose()
  "file: {0}  dashboards: {1}  widgets: {2}  1-line chars: {3}" -f (Split-Path $SelfTest -Leaf), $d.Dashboards.Count, $d.WidgetCount, $d.Bytes
  "1-line has no line breaks: {0}" -f (-not $d.OneLine.Contains("`n"))
  Format-Destinations $d $SelfTestServer
  foreach ($p in $d.Pages) { 'check page: ' + (Test-Page $SelfTestServer $p.Url $true) }
  'import with a wrong password: ' + (Describe-ImportResult (Invoke-DashboardImport $SelfTestServer 'selftest-not-a-user' 'wrong' $d.OneLine $true))
  return
}

[Windows.Forms.Application]::EnableVisualStyles()
$ui = New-ImportForm
[void]$ui.Form.ShowDialog()
$ui.Form.Dispose()
